import { HttpResponse, delay, http } from 'msw';
import { describe, expect, it, vi } from 'vitest';
import { createVoiceStudio } from '../../src/clients/voicestudio.js';
import { msw } from '../setup.js';

const base = 'https://vs.test';
const vs = createVoiceStudio({ baseUrl: base, apiKey: 'KEY' });

describe('voicestudio client', () => {
  it('createProfile posts multipart and returns the id', async () => {
    let form: FormData | undefined; let auth: string | null = null;
    msw.use(http.post(`${base}/profiles`, async ({ request }) => { form = await request.formData(); auth = request.headers.get('authorization'); return HttpResponse.json({ id: 'ab12cd34', name: 'u1' }); }));
    const id = await vs.createProfile({ name: 'u1', audio: new Uint8Array([1]), referenceText: 'hello world' });
    expect(id).toBe('ab12cd34');
    expect(auth).toBe('Bearer KEY');
    expect(form?.get('name')).toBe('u1');
    expect(form?.get('ref_text')).toBe('hello world');
    expect(form?.get('kind')).toBe('clone');
    expect((form?.get('ref_audio') as File).name).toBe('sample.m4a');
  });
  it('deleteProfile ignores 404', async () => {
    msw.use(http.delete(`${base}/profiles/gone`, () => new HttpResponse(null, { status: 404 })));
    await expect(vs.deleteProfile('gone')).resolves.toBeUndefined();
  });
  it('transcribe returns text', async () => {
    msw.use(http.post(`${base}/v1/audio/transcriptions`, async ({ request }) => {
      const f = await request.formData();
      return f.get('file') instanceof File ? HttpResponse.json({ text: 'I never do anything right' }) : new HttpResponse(null, { status: 400 });
    }));
    expect(await vs.transcribe(new Uint8Array([1]))).toBe('I never do anything right');
  });
  it('synthesize returns mp3 bytes and sends voice + input', async () => {
    let body: any;
    msw.use(http.post(`${base}/v1/audio/speech`, async ({ request }) => { body = await request.json(); return HttpResponse.arrayBuffer(new Uint8Array([7, 7]).buffer, { headers: { 'content-type': 'audio/mpeg' } }); }));
    expect(await vs.synthesize({ text: 'I am learning', voice: 'ab12cd34' })).toEqual(new Uint8Array([7, 7]));
    expect(body).toMatchObject({ voice: 'ab12cd34', input: 'I am learning', response_format: 'mp3' });
  });
  it('throws with status and response body on failure', async () => {
    msw.use(http.post(`${base}/v1/audio/speech`, () => new HttpResponse('boom', { status: 500 })));
    await expect(vs.synthesize({ text: 'x', voice: 'v' })).rejects.toThrow('VoiceStudio POST /v1/audio/speech: 500 boom');
  });
  it('names the request when the connection fails', async () => {
    msw.use(http.post(`${base}/v1/audio/speech`, () => HttpResponse.error()));
    await expect(vs.synthesize({ text: 'x', voice: 'v' })).rejects.toThrow(/^VoiceStudio POST \/v1\/audio\/speech: .+/);
  });
  it('times out after timeoutMs', async () => {
    const quick = createVoiceStudio({ baseUrl: base, apiKey: 'KEY', timeoutMs: 50 });
    msw.use(http.post(`${base}/v1/audio/speech`, async () => { await delay(500); return HttpResponse.arrayBuffer(new ArrayBuffer(1)); }));
    await expect(quick.synthesize({ text: 'x', voice: 'v' })).rejects.toThrow(/VoiceStudio POST \/v1\/audio\/speech: .*(timeout|abort)/i);
  });
  it('passes a timeout signal to fetch', async () => {
    msw.use(http.delete(`${base}/profiles/p1`, () => new HttpResponse(null, { status: 200 })));
    const spy = vi.spyOn(globalThis, 'fetch');
    try {
      await vs.deleteProfile('p1');
      expect(spy.mock.calls[0]?.[1]?.signal).toBeInstanceOf(AbortSignal);
    } finally { spy.mockRestore(); }
  });
});
