// Metro config. For the Expo Go UI preview, alias @aws-sdk/* to a stub so the
// bundle doesn't pull Node built-ins (node:stream) that RN lacks. Remove this
// alias (and add real node-builtin polyfills) when building for upload/e2e.
const { getDefaultConfig } = require("expo/metro-config");
const path = require("path");

const config = getDefaultConfig(__dirname);

const awsStub = path.resolve(__dirname, "src/awsStub.js");
const originalResolveRequest = config.resolver.resolveRequest;

config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName.startsWith("@aws-sdk/")) {
    return { type: "sourceFile", filePath: awsStub };
  }
  const resolver = originalResolveRequest || context.resolveRequest;
  return resolver(context, moduleName, platform);
};

module.exports = config;
