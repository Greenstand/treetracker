// Standalone UUID helper (no AWS dependency) so screens that only need an id
// don't pull the AWS SDK into the bundle. Uses crypto.randomUUID when the
// react-native-get-random-values polyfill is present, else a Math.random fallback.
export function uuidLike(): string {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const g: any = globalThis as any;
  if (g.crypto?.randomUUID) {
    try {
      return g.crypto.randomUUID();
    } catch {
      /* fall through */
    }
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
