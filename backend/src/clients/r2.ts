import { AwsClient } from 'aws4fetch';
import type { R2 } from '../deps.js';

export function createR2(cfg: { accountId: string; accessKeyId: string; secretAccessKey: string; bucket: string }): R2 {
  const aws = new AwsClient({ accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey, service: 's3', region: 'auto' });
  const url = (key: string) => `https://${cfg.accountId}.r2.cloudflarestorage.com/${cfg.bucket}/${key}`;
  const call = async (method: string, key: string, init?: RequestInit) => {
    const res = await aws.fetch(url(key), { method, ...init });
    if (!res.ok) throw new Error(`R2 ${method} ${key}: ${res.status}`);
    return res;
  };
  return {
    put: async (key, body, contentType) => { await call('PUT', key, { body, headers: { 'content-type': contentType } }); },
    get: async (key) => new Uint8Array(await (await call('GET', key)).arrayBuffer()),
    delete: async (key) => { await call('DELETE', key); },
    presignGet: async (key) => {
      const signed = await aws.sign(new Request(`${url(key)}?X-Amz-Expires=3600`, { method: 'GET' }), { aws: { signQuery: true } });
      return signed.url;
    },
  };
}
