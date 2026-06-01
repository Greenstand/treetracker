#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="us-east-1"
AWS="aws --endpoint-url=$ENDPOINT --region=$REGION"

echo "Waiting for LocalStack to be ready..."
until $AWS s3 ls &>/dev/null 2>&1; do
  sleep 2
done

echo "Creating S3 buckets..."
$AWS s3 mb s3://treetracker-images-local 2>/dev/null || true
$AWS s3 mb s3://treetracker-bulk-pack-local 2>/dev/null || true

echo "Creating SQS queues..."
$AWS sqs create-queue --queue-name treetracker-bulk-pack 2>/dev/null || true
$AWS sqs create-queue --queue-name treetracker-field-data 2>/dev/null || true

echo "Creating S3 -> SQS event notification for bulk-pack bucket..."
QUEUE_ARN=$($AWS sqs get-queue-attributes \
  --queue-url "$ENDPOINT/000000000000/treetracker-bulk-pack" \
  --attribute-names QueueArn \
  --query Attributes.QueueArn --output text)

$AWS s3api put-bucket-notification-configuration \
  --bucket treetracker-bulk-pack-local \
  --notification-configuration "{
    \"QueueConfigurations\": [{
      \"QueueArn\": \"$QUEUE_ARN\",
      \"Events\": [\"s3:ObjectCreated:*\"]
    }]
  }" 2>/dev/null || true

echo "LocalStack seeded successfully."
