// Dev environment config (mirrors the Android `dev` build variant).
export const CONFIG = {
  region: "eu-central-1",
  // dev Cognito identity pool (unauthenticated) — matches s3_dev_identity_pool_id
  identityPoolId: "eu-central-1:3f3395cc-3835-470d-8fd9-c96304a6b07f",
  imagesBucket: "treetracker-dev-images",
  batchUploadsBucket: "treetracker-dev-batch-uploads",
  apiGateway: "https://dev-k8s.treetracker.org",
  packFormatVersion: "2",
};
