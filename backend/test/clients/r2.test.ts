import { HttpResponse, http } from 'msw';
import { describe, expect, it } from 'vitest';
import { createR2 } from '../../src/clients/r2.js';
import { msw } from '../setup.js';

const base = 'https://acct.r2.cloudflarestorage.com/bucket';
const r2 = createR2({ accountId: 'acct', accessKeyId: 'AK', secretAccessKey: 'SK', bucket: 'bucket' });

describe('r2 client', () => {
  it('PUTs with content type and a signed Authorization header', async () => {
    let seen: Request | undefined;
    msw.use(http.put(`${base}/recordings/a.m4a`, async ({ request }) => { seen = request; return new HttpResponse(null, { status: 200 }); }));
    await r2.put('recordings/a.m4a', new Uint8Array([9]), 'audio/mp4');
    expect(seen?.headers.get('content-type')).toBe('audio/mp4');
    expect(seen?.headers.get('authorization')).toMatch(/^AWS4-HMAC-SHA256 Credential=AK\//);
  });
  it('GETs bytes', async () => {
    msw.use(http.get(`${base}/affirmations/a.mp3`, () => HttpResponse.arrayBuffer(new Uint8Array([1, 2]).buffer)));
    expect(await r2.get('affirmations/a.mp3')).toEqual(new Uint8Array([1, 2]));
  });
  it('throws on non-2xx', async () => {
    msw.use(http.get(`${base}/missing`, () => new HttpResponse(null, { status: 404 })));
    await expect(r2.get('missing')).rejects.toThrow('R2 GET missing: 404');
  });
  it('DELETEs', async () => {
    let called = false;
    msw.use(http.delete(`${base}/voices/u.m4a`, () => { called = true; return new HttpResponse(null, { status: 204 }); }));
    await r2.delete('voices/u.m4a');
    expect(called).toBe(true);
  });
  it('presigns a GET for one hour without hitting the network', async () => {
    const url = new URL(await r2.presignGet('affirmations/a.mp3'));
    expect(url.origin + url.pathname).toBe(`${base}/affirmations/a.mp3`);
    expect(url.searchParams.get('X-Amz-Expires')).toBe('3600');
    expect(url.searchParams.get('X-Amz-Signature')).toBeTruthy();
  });
});
