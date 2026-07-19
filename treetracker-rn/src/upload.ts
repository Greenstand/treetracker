// S3 upload to the dev buckets via the dev Cognito identity pool (unauthenticated),
// replicating ObjectStorageClient.kt + UploadBundle.createV2 so captures land on
// dev-admin.treetracker.org/verify.
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { fromCognitoIdentityPool } from "@aws-sdk/credential-provider-cognito-identity";
import * as FileSystem from "expo-file-system/legacy";
import { CONFIG } from "./config";
import { uuidLike } from "./uuid";
import {
  Capture,
  Session,
  User,
  getState,
  markAllUploaded,
} from "./store";

const s3 = new S3Client({
  region: CONFIG.region,
  credentials: fromCognitoIdentityPool({
    identityPoolId: CONFIG.identityPoolId,
    clientConfig: { region: CONFIG.region },
  }),
});

function base64ToBytes(b64: string): Uint8Array {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const lookup = new Uint8Array(256);
  for (let i = 0; i < chars.length; i++) lookup[chars.charCodeAt(i)] = i;
  const clean = b64.replace(/[^A-Za-z0-9+/]/g, "");
  const len = clean.length;
  const pad = b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0;
  const bytesLen = (len * 3) / 4 - pad;
  const bytes = new Uint8Array(bytesLen);
  let p = 0;
  for (let i = 0; i < len; i += 4) {
    const e1 = lookup[clean.charCodeAt(i)];
    const e2 = lookup[clean.charCodeAt(i + 1)];
    const e3 = lookup[clean.charCodeAt(i + 2)];
    const e4 = lookup[clean.charCodeAt(i + 3)];
    if (p < bytesLen) bytes[p++] = (e1 << 2) | (e2 >> 4);
    if (p < bytesLen) bytes[p++] = ((e2 & 15) << 4) | (e3 >> 2);
    if (p < bytesLen) bytes[p++] = ((e3 & 3) << 6) | e4;
  }
  return bytes;
}

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

// Upload one image; returns its public URL (same key/url shape as Android).
export async function uploadImage(
  uri: string,
  lat: number,
  lon: number,
): Promise<string> {
  const b64 = await FileSystem.readAsStringAsync(uri, {
    encoding: FileSystem.EncodingType.Base64,
  });
  const body = base64ToBytes(b64);
  const d = new Date();
  const ts = `${d.getFullYear()}.${pad(d.getMonth() + 1)}.${pad(d.getDate())}.${pad(
    d.getHours(),
  )}.${pad(d.getMinutes())}.${pad(d.getSeconds())}`;
  const name = uri.split("/").pop() || "tree.jpg";
  const key = `${ts}_${lat}_${lon}_${uuidLike()}_${name}`;
  await s3.send(
    new PutObjectCommand({
      Bucket: CONFIG.imagesBucket,
      Key: key,
      Body: body,
      ContentType: "image/jpeg",
      ACL: "public-read",
    }),
  );
  return `https://${CONFIG.imagesBucket}.s3.${CONFIG.region}.amazonaws.com/${key}`;
}

// Upload a V2 bundle JSON to the batch-uploads bucket.
export async function uploadBundle(
  user: User,
  sessions: Session[],
  captures: Capture[],
): Promise<void> {
  const bundle = {
    pack_format_version: CONFIG.packFormatVersion,
    device_id: "treetracker-rn-e2e",
    wallet_registrations: null,
    captures: captures.map((c) => ({
      session_id: c.sessionId,
      id: c.id,
      lat: c.lat,
      lon: c.lon,
      note: c.note,
      image_url: c.imageUrl,
      captured_at: c.capturedAt,
      abs_step_count: c.absStepCount,
      delta_step_count: c.deltaStepCount,
      rotation_matrix: null,
      extra_attributes: null,
    })),
    device_configurations: null,
    sessions: sessions.map((s) => ({
      id: s.id,
      originating_wallet_registration_id: s.originUserId,
      target_wallet: s.targetWallet,
      organization: s.organization,
      device_configuration_id: "treetracker-rn-device-config",
    })),
    tracks: null,
    messages: null,
  };
  const json = JSON.stringify(bundle);
  const d = new Date();
  const ts = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}-${pad(
    d.getHours(),
  )}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
  const key = `${ts}_${uuidLike()}_${user.uuid}.json`;
  await s3.send(
    new PutObjectCommand({
      Bucket: CONFIG.batchUploadsBucket,
      Key: key,
      Body: json,
      ContentType: "application/json",
      ACL: "public-read",
    }),
  );
}

// Upload all pending captures: each image -> images bucket, then one V2 bundle
// -> batch-uploads bucket, then mark them uploaded (flips dashboard counts).
export async function uploadPending(): Promise<void> {
  const { users, sessions, captures } = getState();
  const user = users[0];
  const pending = captures.filter((c) => !c.uploaded);
  if (!user || pending.length === 0) return;

  const urls: Record<string, string> = {};
  const withUrls: Capture[] = [];
  for (const c of pending) {
    const url = await uploadImage(c.photoPath, c.lat, c.lon);
    urls[c.id] = url;
    withUrls.push({ ...c, imageUrl: url });
  }
  const sessIds = new Set(withUrls.map((c) => c.sessionId));
  const sess = sessions.filter((s) => sessIds.has(s.id));
  await uploadBundle(user, sess, withUrls);
  await markAllUploaded(urls);
}
