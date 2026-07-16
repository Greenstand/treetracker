// Polyfills for the AWS SDK v3. react-native-get-random-values is a NATIVE module
// not bundled in Expo Go, so load it defensively: in Expo Go it's absent (S3 upload
// is disabled there) but the UI still boots. In a dev/standalone build it loads
// normally and uploads work. require() (not import) so order + try/catch work.
try {
  require("react-native-get-random-values");
} catch (e) {
  // eslint-disable-next-line no-console
  console.warn(
    "[treetracker-rn] react-native-get-random-values unavailable (Expo Go) — S3 upload disabled",
  );
}
require("react-native-url-polyfill/auto");

const { registerRootComponent } = require("expo");
const App = require("./App").default;

registerRootComponent(App);
