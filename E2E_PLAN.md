# Plan: Cross-Platform Automated UI Tests with Appium + WebdriverIO

## Context
The user wants an automated tool that goes through all app screens and verifies the whole app works — generalized across Android, iOS, and other apps in the monorepo. The tool must be free and open source.

**Chosen stack: Appium + WebdriverIO + Cucumber** — exactly the same stack already used in `treetracker-wallet-app/apps/bdd/`. This is fully free/open source, already familiar to the team, supports Android and iOS, and follows the exact existing pattern in the monorepo.

---

## Approach

Create `treetracker-android/e2e/` following the **identical structure** as `treetracker-wallet-app/apps/bdd/`. The two test suites use the same tooling and can be extended to any other app in the monorepo by adding a new `capabilities.ts` entry.

---

## New Directory Structure

```
treetracker-android/e2e/
├── package.json                        # WebdriverIO + Cucumber deps (mirrors apps/bdd)
├── tsconfig.json                       # TypeScript config (mirrors apps/bdd)
├── wdio.base.conf.ts                   # Shared config: Cucumber, reporters, video, hooks
├── wdio.mobile.conf.ts                 # Appium service + Android/iOS capabilities
├── .env.example                        # APK_PATH, DEVICE_NAME env vars
├── utils/
│   ├── capabilities.ts                 # Android (org.greenstand) + iOS capabilities
│   └── artifacts.ts                    # Video/screenshot helpers (copy from apps/bdd)
├── features/
│   ├── 01_splash_to_dashboard.feature  # Returning user: Splash → Dashboard
│   ├── 02_signup_flow.feature          # First-run: Splash → Language → Sign Up
│   ├── 03_capture_setup.feature        # Dashboard → User Select → Wallet → Session Note
│   ├── 04_tree_capture.feature         # Camera → Review → Height
│   ├── 05_settings.feature             # Settings → Profile → Delete Profile
│   ├── 06_messages.feature             # Messages → Chat / Survey / Announcement
│   ├── 07_org.feature                  # Org Picker → Add Org
│   └── step-definitions/
│       └── android.steps.ts            # Appium step implementations
└── test-artifacts/                     # Auto-generated: reports, videos, screenshots
```

---

## Key Configuration Values for treetracker-android

**`utils/capabilities.ts`** — overrides the `com.gtw.app` wallet entries with:
```typescript
export const CAPABILITY_ANDROID = [{
  platformName: "Android",
  "appium:deviceName": process.env.DEVICE_NAME || "emulator-5554",
  "appium:app": process.env.APK_PATH,                          // path to app-debug.apk
  "appium:automationName": "UiAutomator2",
  "appium:appPackage": "org.greenstand.android.TreeTracker",
  "appium:appActivity": "org.greenstand.android.TreeTracker.activities.TreeTrackerActivity",
  "appium:autoGrantPermissions": true,                         // grants CAMERA + LOCATION automatically
  "appium:noReset": false,
  "appium:newCommandTimeout": 240,
}];
```

`"appium:autoGrantPermissions": true` handles the location + camera permission dialogs that `SplashScreen` triggers — no extra steps needed.

---

## Feature Files (all 25 screens covered across 7 flows)

### Example: `01_splash_to_dashboard.feature`
```gherkin
@native
Feature: Splash to Dashboard (returning user)

  Scenario: Returning user lands on Dashboard
    Given the app is launched with an existing user
    Then I should see "Trees Synced"
    And I should see the upload button
```

### Example: `02_signup_flow.feature`
```gherkin
@native
Feature: First-run signup flow

  Scenario: New user completes signup
    Given the app is launched fresh
    Then I should see the language selection screen
    When I tap "English"
    And I tap "Continue"
    Then I should see the signup screen
    And I should see "Phone Number"
```

### Example: `05_settings.feature`
```gherkin
@native
Feature: Settings and profile management

  Scenario: Navigate to settings and view profile
    Given the app is launched with an existing user
    When I navigate to Settings
    Then I should see "Settings"
    When I tap "Profiles"
    Then I should see "Select Profile"
    When I tap on the first profile
    Then I should see "Delete Profile"
```

---

## Step Definitions Pattern (`android.steps.ts`)

Steps use **UIAutomator text selectors** — no `testTag` changes needed in the app source:

```typescript
import { Given, When, Then } from "@wdio/cucumber-framework";
import { $, browser, expect } from "@wdio/globals";

// Find elements by visible text (works on all Compose screens)
const byText = (text: string) => $(`android=new UiSelector().text("${text}")`);
const byTextContains = (text: string) => $(`android=new UiSelector().textContains("${text}")`);

Given("the app is launched with an existing user", async () => {
  // App launched via Appium capabilities; wait for Dashboard
  await (await byText("Trees Synced")).waitForDisplayed({ timeout: 20000 });
});

Given("the app is launched fresh", async () => {
  await browser.terminateApp("org.greenstand.android.TreeTracker");
  await browser.activateApp("org.greenstand.android.TreeTracker");
  await (await byTextContains("Language")).waitForDisplayed({ timeout: 15000 });
});

When("I tap {string}", async (text: string) => {
  const el = await byText(text);
  await el.waitForDisplayed({ timeout: 10000 });
  await el.click();
});

Then("I should see {string}", async (text: string) => {
  const el = await byText(text);
  await expect(el).toBeDisplayed();
});
```

---

## `package.json` (mirrors `apps/bdd/package.json`)

```json
{
  "name": "@greenstand/android-e2e",
  "scripts": {
    "test:android": "cross-env PLATFORM=android wdio run ./wdio.mobile.conf.ts",
    "test:ios":     "cross-env PLATFORM=ios wdio run ./wdio.mobile.conf.ts",
    "report":       "node scripts/generate-cucumber-report.js"
  },
  "devDependencies": {
    "@wdio/cli": "^9.18.4",
    "@wdio/cucumber-framework": "^9.18.0",
    "@wdio/globals": "^9.17.0",
    "@wdio/local-runner": "^9.18.4",
    "@wdio/spec-reporter": "^9.18.0",
    "cross-env": "^10.1.0",
    "dotenv": "^17.2.3",
    "ts-node": "^10.9.2",
    "typescript": "^5.9.2",
    "wdio-cucumberjs-json-reporter": "^6.0.1",
    "wdio-video-reporter": "^6.1.1",
    "wdio-wait-for": "^3.1.0"
  }
}
```

---

## Implementation Steps

1. **Create `treetracker-android/e2e/` directory structure**
2. **Copy + adapt** `wdio.base.conf.ts` and `wdio.mobile.conf.ts` from `apps/bdd/` — only change: `cucumberOpts.require` path and `capabilities.ts` import
3. **Write `utils/capabilities.ts`** with treetracker-android's appPackage + appActivity
4. **Read screen source files** to identify landmark text for each of the 25 screens — used in `assertVisible` step assertions
5. **Write 7 feature files** covering all screens grouped by user flow
6. **Write `android.steps.ts`** with UIAutomator text selectors (no app source changes needed)
7. **Run**: build APK → start emulator → run tests

---

## Extending to Other Apps

To add another app (e.g. wallet native, iOS):
- Add a new entry to `utils/capabilities.ts` with the new appPackage/bundleId
- Add feature files under `features/` for that app's screens
- Tag them `@wallet-native` or similar, filter in config

This scales to any app in the monorepo with zero new tooling.

---

## Prerequisites & Verification

```bash
# One-time global installs (free, open source)
npm install -g appium
appium driver install uiautomator2     # Android
appium driver install xcuitest         # iOS (Mac only)

# Build the APK
cd treetracker-android
./gradlew assembleDebug
# APK at: app/build/outputs/apk/debug/app-debug.apk

# Start emulator (Android Studio AVD or `emulator -avd <name>`)

# Run all tests
cd e2e
APK_PATH=../app/build/outputs/apk/debug/app-debug.apk npm run test:android

# Run a single feature
APK_PATH=... npx wdio run ./wdio.mobile.conf.ts --spec features/01_splash_to_dashboard.feature
```

Test results: HTML report + MP4 video per scenario in `test-artifacts/`.
