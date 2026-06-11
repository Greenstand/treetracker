// AWS SDK stub used for the Expo Go UI preview. The real @aws-sdk packages pull
// in Node built-ins (node:stream, ...) that the React Native runtime lacks, which
// breaks the Metro bundle. Aliasing @aws-sdk/* to this stub (see metro.config.js)
// lets the UI bundle + run; the S3 upload simply no-ops in the preview.
// (For a real build/e2e, drop the alias and add proper node-builtin polyfills.)
function notAvailable() {
  throw new Error("S3 upload is disabled in the Expo Go preview build");
}

class S3Client {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  constructor(_config) {}
  async send() {
    notAvailable();
  }
}

class PutObjectCommand {
  constructor(input) {
    this.input = input;
  }
}

function fromCognitoIdentityPool() {
  return async () => notAvailable();
}

module.exports = { S3Client, PutObjectCommand, fromCognitoIdentityPool };
