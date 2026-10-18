import { randomUUID } from 'node:crypto';

import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import type { UserModelMessage } from 'ai';

import { guardedText } from './guardrail.js';

const BUCKET = process.env.ARTIFACTS_BUCKET!;
const s3 = new S3Client({ region: process.env.AWS_REGION });
const MEDIA_TYPES: Record<string, string> = {
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp', pdf: 'application/pdf',
};

// The user's message: the prompt, plus the attached file as a file part
export async function userMessage(prompt: string, file: { fileName?: string; fileBase64?: string }): Promise<UserModelMessage> {
  if (!file.fileName || !file.fileBase64) {
    return { role: 'user', content: [guardedText(prompt)] };
  }
  // >> Upload the file to S3 and add its URI to the prompt, so tools such as `extractReceipt` can read it
  const data = Buffer.from(file.fileBase64, 'base64');
  const key = `artifacts/uploads/${randomUUID()}/${file.fileName}`;
  await s3.send(new PutObjectCommand({ Bucket: BUCKET, Key: key, Body: data }));
  const text = `${prompt}\n[Attached file: ${file.fileName}, S3 URI: s3://${BUCKET}/${key}]`;
  // <<
  // >> The model reads images and PDFs as file parts; other files reach it only through the S3 URI
  const mediaType = MEDIA_TYPES[file.fileName.split('.').pop()!.toLowerCase()];
  return {
    role: 'user',
    content: mediaType ? [guardedText(text), { type: 'file', data, mediaType }] : [guardedText(text)],
  };
  // <<
}
