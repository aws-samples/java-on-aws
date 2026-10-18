import { AsyncLocalStorage } from 'node:async_hooks';
import { randomUUID } from 'node:crypto';

import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

export const currentSession = new AsyncLocalStorage<string>();
const files = new Map<string, { name: string; data: Uint8Array | string; mediaType: string }[]>();

const BUCKET = process.env.ARTIFACTS_BUCKET!;
const s3 = new S3Client({ region: process.env.AWS_REGION });

export function store(name: string, data: Uint8Array, mediaType: string) {
  const id = currentSession.getStore() ?? 'default';
  files.set(id, [...(files.get(id) ?? []), { name, data, mediaType }]);
}

// >> Add a file that another agent already uploaded: keep its presigned link
export function storeLink(name: string, url: string, mediaType: string) {
  const id = currentSession.getStore() ?? 'default';
  files.set(id, [...(files.get(id) ?? []), { name, data: url, mediaType }]);
}
// <<

async function link(name: string, data: Uint8Array, mediaType: string) {
  const key = `artifacts/${randomUUID()}/${name}`;
  await s3.send(new PutObjectCommand({ Bucket: BUCKET, Key: key, Body: data, ContentType: mediaType }));
  return getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: key }), { expiresIn: 3600 });
}

export async function asMarkdown(conversationId: string) {
  const parts: string[] = [];
  for (const { name, data, mediaType } of files.get(conversationId) ?? []) {
    // >> Links from other agents are used as they are; own files are uploaded
    const url = typeof data === 'string' ? data : await link(name, data, mediaType);
    // <<
    parts.push(mediaType.startsWith('image/') ? `\n\n![${name}](${url})` : `\n\n[Download ${name}](${url})`);
  }
  files.delete(conversationId);
  return parts.join('');
}
