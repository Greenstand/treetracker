#!/usr/bin/env bash
#
# e2e.sh — ONE command to run the Android capture→verify e2e and pass it.
#
# Installs the host toolchain (Android SDK + JDK21 + node + emulator/AVD), builds the
# `local` APK if missing, boots the emulator, aligns chromedriver to the host Chrome, then
# runs apps/e2e (02_signup + 03_capture_setup) against http://localhost:8088.
#
# The backend is NOT started by this script — it only CHECKS the gateway and stops with a
# warning if it's not up. Bring the backend up yourself first with ./k3s/up.sh.
#
# Usage:
#   ./k3s/e2e.sh                 # everything: install → apk → backend → emulator → test
#   ./k3s/e2e.sh <step>          # one step: install | avd | apk | backend | emulator | test
#
# Idempotent: re-running skips work already done (installed tools, running emulator, up backend).
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root (this script lives in k3s/)
ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
AVD="${AVD:-greenstand_test}"
SYS_IMG="${SYS_IMG:-system-images;android-34;google_apis;arm64-v8a}"
AVD_DEVICE="${AVD_DEVICE:-pixel_6}"
JDK21="${JDK21:-/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home}"
APK="$ROOT/treetracker-android/app/build/outputs/apk/local/app-local.apk"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8088}"
E2E_DIR="$ROOT/apps/e2e"
SPECS=(./features/02_signup_flow.feature ./features/03_capture_setup.feature)

export PATH="/opt/homebrew/bin:$PATH"
export ANDROID_SDK_ROOT="$ANDROID_HOME" ANDROID_HOME
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# ── Helpers ─────────────────────────────────────────────────────────────────
c_grn=$'\033[32m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
log()  { echo "${c_grn}▶${c_off} $*"; }
info() { echo "${c_dim}  $*${c_off}"; }
die()  { echo "${c_red}✖ $*${c_off}" >&2; exit 1; }

# Put a usable node (>=18) on PATH: prefer existing, else newest nvm, else brew.
ensure_node() {
  command -v node >/dev/null 2>&1 && return 0
  local d
  for d in "$HOME"/.nvm/versions/node/*/bin; do [ -x "$d/node" ] && PATH="$d:$PATH"; done
  command -v node >/dev/null 2>&1 && return 0
  log "installing node (brew)"; brew install node >/dev/null || die "node install failed"
}

sdkmanager() { JAVA_HOME="$JDK21" "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "$@"; }
avdmanager() { JAVA_HOME="$JDK21" "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" "$@"; }
gw_up()      { [ "$(curl -s -o /dev/null -m 4 -w '%{http_code}' "$GATEWAY_URL/" 2>/dev/null)" = 200 ]; }

# ── 1. Host software (Android SDK, JDK21, node, emulator, system image) ───────
# Presence-based: only download what's actually missing. sdkmanager needs to reach
# dl.google.com, which this machine's fake-IP DNS breaks — so when the packages already
# exist we skip it entirely (no network required).
step_install() {
  log "host toolchain"
  command -v brew >/dev/null 2>&1 || die "Homebrew required (https://brew.sh)"
  [ -d "$ANDROID_HOME/cmdline-tools/latest" ] || { info "android-commandlinetools"; brew install android-commandlinetools >/dev/null || die "sdk install failed"; }
  [ -d "$JDK21" ] || { info "temurin@21"; brew install --cask temurin@21 >/dev/null || die "jdk21 install failed"; }
  ensure_node; info "node $(node -v)"

  # figure out which SDK packages are missing (by their on-disk location)
  local missing=()
  [ -x "$ANDROID_HOME/platform-tools/adb" ]      || missing+=("platform-tools")
  [ -x "$ANDROID_HOME/emulator/emulator" ]       || missing+=("emulator")
  [ -d "$ANDROID_HOME/platforms/android-34" ]    || missing+=("platforms;android-34")
  [ -d "$ANDROID_HOME/build-tools/34.0.0" ]      || missing+=("build-tools;34.0.0")
  [ -d "$ANDROID_HOME/${SYS_IMG//;//}" ]         || missing+=("$SYS_IMG")

  if [ ${#missing[@]} -eq 0 ]; then
    info "SDK packages already present (platform-tools, emulator, android-34, system image) — skipping sdkmanager"
  else
    info "installing missing SDK packages: ${missing[*]} (needs dl.google.com)"
    yes 2>/dev/null | sdkmanager --licenses >/dev/null 2>&1 || true
    sdkmanager "${missing[@]}" >/dev/null 2>&1 \
      || die "sdkmanager failed for: ${missing[*]} — likely can't reach dl.google.com (DNS/network)"
  fi
  command -v adb >/dev/null 2>&1 || die "adb not on PATH ($ANDROID_HOME/platform-tools)"
}

# ── 2. AVD ────────────────────────────────────────────────────────────────────
step_avd() {
  log "emulator AVD '$AVD'"
  if "$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | grep -qx "$AVD"; then
    info "already exists"; return 0
  fi
  info "creating from $SYS_IMG"
  echo no | avdmanager create avd -n "$AVD" -k "$SYS_IMG" -d "$AVD_DEVICE" --force >/dev/null \
    || die "AVD create failed"
}

# ── 3. APK (build the `local` build type only if missing) ─────────────────────
step_apk() {
  if [ -f "$APK" ]; then log "APK present ($(basename "$APK"))"; return 0; fi
  log "building local APK (gradle, JDK21)"
  [ -d "$JDK21" ] || die "JDK21 missing — run ./k3s/e2e.sh install"
  ( cd "$ROOT/treetracker-android" && JAVA_HOME="$JDK21" ANDROID_HOME="$ANDROID_HOME" ./gradlew :app:assembleLocal ) \
    >/tmp/e2e-apk-build.log 2>&1 || die "APK build failed (see /tmp/e2e-apk-build.log)"
  [ -f "$APK" ] || die "APK not produced at $APK"
}

# ── 4. Backend (local k3s + Ambassador gateway) — CHECK ONLY, never start it ──
step_backend() {
  log "backend gateway check"
  gw_up || die "backend not reachable at $GATEWAY_URL — bring it up first with ./k3s/up.sh"
  info "gateway up ($GATEWAY_URL)"
}

# ── 5. Emulator (windowed) ────────────────────────────────────────────────────
step_emulator() {
  log "emulator"
  if adb devices 2>/dev/null | grep -q 'emulator-5554'; then info "already running"; else
    pkill -9 -f "qemu-system-aarch64.*$AVD" 2>/dev/null || true; sleep 2
    adb kill-server >/dev/null 2>&1 || true; adb start-server >/dev/null 2>&1 || true
    nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -no-snapshot -gpu swiftshader_indirect -no-audio \
      </dev/null >/tmp/e2e-emulator.log 2>&1 & disown
    info "booting $AVD ..."
  fi
  adb wait-for-device
  local i; for i in $(seq 1 80); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 3
  done
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] || die "emulator never finished booting"
  info "emulator-5554 ready"
}

# Keep the e2e's chromedriver in lockstep with the host Chrome major (the /verify step
# drives Chrome; a mismatch = "only supports Chrome version N").
align_chromedriver() {
  local chrome major cur
  chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$chrome" ] || { info "host Chrome not found — skipping chromedriver align"; return 0; }
  major="$("$chrome" --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  cur="$(node -e "try{console.log(require('$E2E_DIR/node_modules/chromedriver/package.json').version.split('.')[0])}catch(e){console.log('0')}")"
  [ -n "$major" ] || return 0
  if [ "$cur" != "$major" ]; then
    info "chromedriver $cur → ^$major (host Chrome $major)"
    ( cd "$E2E_DIR" && npm install --no-audit --no-fund --save-dev "chromedriver@^$major" >/dev/null 2>&1 ) \
      || info "chromedriver align failed (continuing)"
  fi
}

# ── 6. Run the e2e ─────────────────────────────────────────────────────────────
step_test() {
  log "e2e (apps/e2e: 02_signup + 03_capture_setup → $GATEWAY_URL)"
  ensure_node
  gw_up || die "backend gateway not up — run ./k3s/e2e.sh backend"
  adb devices 2>/dev/null | grep -q 'emulator-5554' || die "emulator not running — run ./k3s/e2e.sh emulator"
  [ -f "$APK" ] || die "APK missing — run ./k3s/e2e.sh apk"
  ( cd "$E2E_DIR" && [ -d node_modules ] || npm install --no-audit --no-fund >/dev/null 2>&1 ) || die "apps/e2e npm install failed"
  align_chromedriver
  ( cd "$E2E_DIR" && WDIO_TAGS="${WDIO_TAGS:-not @skip}" ANDROID_HOME="$ANDROID_HOME" ANDROID_SDK_ROOT="$ANDROID_HOME" \
      npx wdio run ./wdio.conf.ts $(printf -- '--spec %s ' "${SPECS[@]}") ) \
    || die "e2e FAILED"
  log "e2e PASSED ✅"
}

run_all() { step_install; step_avd; step_apk; step_backend; step_emulator; step_test; }

case "${1:-all}" in
  all) run_all ;;
  install|avd|apk|backend|emulator|test) "step_${1}" ;;
  *) die "unknown step '${1}'. steps: install avd apk backend emulator test (or 'all')" ;;
esac
