import { createPubSub } from 'graphql-yoga';
import type { YogaServerInstance } from 'graphql-yoga';
import { createApp } from '../../src/app.js';
import { jwtSecretFrom } from '../../src/auth/jwt.js';
import type { Deps } from '../../src/deps.js';
import { makeAppleSigner } from './apple.js';
import { makeTestDb } from './db.js';

export async function makeTestDeps() {
  const apple = await makeAppleSigner();
  const r2 = new Map<string, Uint8Array>();
  const voice = { profiles: new Map<string, string>(), transcript: 'I always mess things up', synthesized: new Uint8Array([1, 2, 3]), fail: undefined as undefined | 'transcribe' | 'synthesize' | 'createProfile' };
  const fakes = { r2, voice, reframeFail: false };
  let profileSeq = 0;
  const deps: Deps = {
    db: await makeTestDb(),
    pubsub: createPubSub(),
    jwtSecret: jwtSecretFrom('test'),
    appleJwks: apple.jwks,
    appleAudience: apple.audience,
    r2: {
      put: async (k, b) => { r2.set(k, b); },
      get: async (k) => { const v = r2.get(k); if (!v) throw new Error(`no object ${k}`); return v; },
      delete: async (k) => { r2.delete(k); },
      presignGet: async (k) => `https://r2.test/${k}?signed`,
    },
    voice: {
      createProfile: async ({ name }) => { if (voice.fail === 'createProfile') throw new Error('voicestudio 500'); const id = `vp${++profileSeq}`; voice.profiles.set(id, name); return id; },
      deleteProfile: async (id) => { voice.profiles.delete(id); },
      transcribe: async () => { if (voice.fail === 'transcribe') throw new Error('voicestudio 500'); return voice.transcript; },
      synthesize: async () => { if (voice.fail === 'synthesize') throw new Error('voicestudio 500'); return voice.synthesized; },
    },
    reframe: async (t) => { if (fakes.reframeFail) throw new Error('openai 500'); return `Reframed: ${t}`; },
  };
  return { deps, apple, fakes, yoga: createApp(deps) };
}

export async function gql(yoga: YogaServerInstance<any, any>, body: { query: string; variables?: Record<string, unknown> }, token?: string) {
  const res = await yoga.fetch(new Request('http://test/graphql', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  }));
  return res.json() as Promise<{ data?: any; errors?: { message: string; extensions?: { code?: string } }[] }>;
}

export async function signIn(yoga: YogaServerInstance<any, any>, apple: Awaited<ReturnType<typeof makeAppleSigner>>, sub = 'apple-1') {
  const identityToken = await apple.sign({ sub });
  const r = await gql(yoga, { query: 'mutation($t:String!){ signInWithApple(identityToken:$t){ token user { id hasVoice } } }', variables: { t: identityToken } });
  return r.data.signInWithApple as { token: string; user: { id: string; hasVoice: boolean } };
}
