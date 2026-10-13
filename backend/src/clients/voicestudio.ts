import type { VoiceStudio } from '../deps.js';

export function createVoiceStudio(cfg: { baseUrl: string; apiKey: string }): VoiceStudio {
  const call = async (method: string, path: string, init: RequestInit = {}, okStatuses: number[] = []) => {
    const res = await fetch(cfg.baseUrl + path, { ...init, method, signal: AbortSignal.timeout(180_000), headers: { authorization: `Bearer ${cfg.apiKey}`, ...(init.headers ?? {}) } });
    if (!res.ok && !okStatuses.includes(res.status)) throw new Error(`VoiceStudio ${method} ${path}: ${res.status}`);
    return res;
  };
  const audioForm = (field: string, audio: Uint8Array, extra: Record<string, string>) => {
    const form = new FormData();
    form.append(field, new File([audio as BlobPart], 'sample.m4a', { type: 'audio/mp4' }));
    for (const [k, v] of Object.entries(extra)) form.append(k, v);
    return form;
  };
  return {
    createProfile: async ({ name, audio, referenceText }) => {
      const res = await call('POST', '/profiles', { body: audioForm('ref_audio', audio, { name, ref_text: referenceText, kind: 'clone' }) });
      return (await res.json() as { id: string }).id;
    },
    deleteProfile: async (id) => { await call('DELETE', `/profiles/${id}`, {}, [404]); },
    transcribe: async (audio) => {
      const res = await call('POST', '/v1/audio/transcriptions', { body: audioForm('file', audio, { model: 'whisper-1' }) });
      return (await res.json() as { text: string }).text;
    },
    synthesize: async ({ text, voice }) => {
      const res = await call('POST', '/v1/audio/speech', {
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ model: 'tts-1', voice, input: text, response_format: 'mp3' }),
      });
      return new Uint8Array(await res.arrayBuffer());
    },
  };
}
