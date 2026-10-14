import { existsSync, readFileSync } from 'node:fs';
import { eq } from 'drizzle-orm';
import { createClient } from 'graphql-ws';
import WebSocket from 'ws';
import { users } from '../src/db/schema.js';
import { signUserToken, jwtSecretFrom } from '../src/auth/jwt.js';
import { createDb } from '../src/db/client.js';
import { loadEnv } from '../src/env.js';

const fixture = new URL('../test/fixtures/sample.m4a', import.meta.url);
if (!existsSync(fixture)) {
  console.error('Missing backend/test/fixtures/sample.m4a (see test/fixtures/README.md)');
  process.exit(1);
}

const env = loadEnv();
const url = process.env.SMOKE_URL ?? `http://localhost:${env.PORT}`;
const db = createDb(env.DATABASE_URL);
const [user] = await db.insert(users).values({ appleSub: `smoke-${Date.now()}` }).returning();
const token = await signUserToken(user.id, jwtSecretFrom(env.JWT_SECRET));
const audio = readFileSync(fixture);
const TIMEOUT_MS = 5 * 60 * 1000;

async function upload(query: string, field: string, variables: Record<string, unknown>) {
  const form = new FormData();
  form.append('operations', JSON.stringify({ query, variables: { [field]: null, ...variables } }));
  form.append('map', JSON.stringify({ '0': [`variables.${field}`] }));
  form.append('0', new File([audio], 'sample.m4a', { type: 'audio/mp4' }));
  const res = await fetch(`${url}/graphql`, { method: 'POST', body: form, headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
  const json = await res.json() as any;
  if (json.errors) throw new Error(JSON.stringify(json.errors));
  return json.data;
}

let ws: ReturnType<typeof createClient> | undefined;
let code = 1;
try {
  console.log('enrolling voice…');
  await upload('mutation($s:File!,$t:String!){ enrollVoice(sample:$s, referenceText:$t){ hasVoice } }', 's',
    { t: 'This is my voice, recorded so the app can speak as me.' });
  console.log('creating session…');
  const { createSession } = await upload('mutation($r:File!){ createSession(recording:$r){ id } }', 'r', {});
  const client = ws = createClient({ url: `${url.replace(/^http/, 'ws')}/graphql`, webSocketImpl: WebSocket, connectionParams: { token } });
  const final = await new Promise<any>((resolve, reject) => {
    let last: any;
    const timer = setTimeout(() => reject(new Error(`timed out after ${TIMEOUT_MS / 1000}s waiting for a terminal status`)), TIMEOUT_MS);
    timer.unref();
    client.subscribe({
      query: 'subscription($id:ID!){ sessionUpdated(id:$id){ status transcript reframedText audioUrl error } }',
      variables: { id: createSession.id },
    }, {
      next: ({ data }: any) => {
        last = data.sessionUpdated;
        console.log(last);
        if (['COMPLETED', 'FAILED'].includes(last.status)) resolve(last);
      },
      error: reject,
      complete: () => reject(new Error('subscription ended without a terminal status')),
    });
  });
  if (final.status !== 'COMPLETED' || !final.audioUrl) { console.error('smoke FAILED, final row:', final); throw new Error('session did not complete'); }

  console.log('sending a chat turn…');
  const { sendTurn } = await upload('mutation($id:ID!,$r:File!){ sendTurn(sessionId:$id, recording:$r){ id } }', 'r', { id: createSession.id });
  const turn = await new Promise<any>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timed out waiting for the turn')), TIMEOUT_MS);
    timer.unref();
    client.subscribe({
      query: 'subscription($id:ID!){ turnUpdated(id:$id){ status userText agentText audioUrl crisis closing error } }',
      variables: { id: sendTurn.id },
    }, {
      next: ({ data }: any) => { console.log(data.turnUpdated); if (['COMPLETED', 'FAILED'].includes(data.turnUpdated.status)) resolve(data.turnUpdated); },
      error: reject,
      complete: () => reject(new Error('turn subscription ended without a terminal status')),
    });
  });
  if (turn.status !== 'COMPLETED' || !turn.audioUrl) { console.error('smoke FAILED, turn:', turn); throw new Error('turn did not complete'); }

  // The pipeline publishes COMPLETED before the profile refresh (an LLM call) finishes, so poll instead of reading once.
  const PROFILE_WAIT_MS = 60_000;
  const deadline = Date.now() + PROFILE_WAIT_MS;
  let profile: string | null = null;
  while (!profile && Date.now() < deadline) {
    const meRes = await fetch(`${url}/graphql`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ query: '{ me { profile } }' }) });
    profile = ((await meRes.json() as any).data?.me?.profile as string | null) ?? null;
    if (!profile) await new Promise((r) => setTimeout(r, 2_000));
  }
  console.log('profile:', profile);
  if (!profile) throw new Error(`profile was not written within ${PROFILE_WAIT_MS / 1000}s`);
  code = 0;

  const res = await fetch(`${url}/graphql`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ query: 'mutation{ deleteAccount }' }) });
  const del = await res.json().catch(() => ({})) as any;
  if (!res.ok || del.errors) console.error('deleteAccount failed (db fallback will clean up):', res.status, JSON.stringify(del.errors ?? del));
  else console.log('deleteAccount ok');
} catch (e) {
  console.error('smoke FAILED:', e);
} finally {
  await ws?.dispose();
  await db.delete(users).where(eq(users.id, user.id)).catch((e) => console.error('fallback user delete failed:', e));
}
process.exit(code);
