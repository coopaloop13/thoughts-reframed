import { existsSync, readFileSync } from 'node:fs';
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

async function upload(query: string, field: string, variables: Record<string, unknown>) {
  const form = new FormData();
  form.append('operations', JSON.stringify({ query, variables: { [field]: null, ...variables } }));
  form.append('map', JSON.stringify({ '0': [`variables.${field}`] }));
  form.append('0', new File([audio], 'sample.m4a', { type: 'audio/mp4' }));
  const res = await fetch(`${url}/graphql`, { method: 'POST', body: form, headers: { authorization: `Bearer ${token}` } });
  const json = await res.json() as any;
  if (json.errors) throw new Error(JSON.stringify(json.errors));
  return json.data;
}

console.log('enrolling voice…');
await upload('mutation($s:File!,$t:String!){ enrollVoice(sample:$s, referenceText:$t){ hasVoice } }', 's',
  { t: 'This is my voice, recorded so the app can speak as me.' });
console.log('creating session…');
const { createSession } = await upload('mutation($r:File!){ createSession(recording:$r){ id } }', 'r', {});
const ws = createClient({ url: `${url.replace(/^http/, 'ws')}/graphql`, webSocketImpl: WebSocket, connectionParams: { token } });
await new Promise<void>((resolve, reject) => {
  ws.subscribe({ query: `subscription { sessionUpdated(id:"${createSession.id}") { status transcript reframedText audioUrl error } }` }, {
    next: ({ data }: any) => { console.log(data.sessionUpdated); if (['COMPLETED', 'FAILED'].includes(data.sessionUpdated.status)) resolve(); },
    error: reject, complete: resolve,
  });
});
await fetch(`${url}/graphql`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ query: 'mutation{ deleteAccount }' }) });
await ws.dispose();
process.exit(0);
