import { describe, expect, it } from 'vitest';
import { sessions } from '../../src/db/schema.js';
import { gql, makeTestDeps, signIn } from '../helpers/app.js';
import { gqlUpload } from '../helpers/upload.js';

const ENROLL = 'mutation($s:File!,$t:String!){ enrollVoice(sample:$s, referenceText:$t){ id } }';
const CREATE = 'mutation($r:File!){ createSession(recording:$r){ id status transcript reframedText audioUrl error createdAt } }';
const rec = { field: 'r', bytes: new Uint8Array([4, 4]), name: 'rec.m4a', type: 'audio/mp4' };
const sample = { field: 's', bytes: new Uint8Array([5]), name: 'v.m4a', type: 'audio/mp4' };

async function enrolledUser() {
  const t = await makeTestDeps();
  const { token, user } = await signIn(t.yoga, t.apple);
  await gqlUpload(t.yoga, { query: ENROLL, variables: { t: 'x' }, file: sample }, token);
  return { ...t, token, user };
}

describe('createSession', () => {
  it('stores the recording, returns UPLOADED, starts the pipeline', async () => {
    const { yoga, token, fakes, started } = await enrolledUser();
    const r = await gqlUpload(yoga, { query: CREATE, variables: {}, file: rec }, token);
    expect(r.errors).toBeUndefined();
    const s = r.data.createSession;
    expect(s.status).toBe('UPLOADED');
    expect(s.audioUrl).toBeNull();
    expect(fakes.r2.get(`recordings/${s.id}.m4a`)).toEqual(rec.bytes);
    expect(started).toEqual([s.id]);
  });
  it('fails VOICE_NOT_ENROLLED before uploading', async () => {
    const { yoga, apple, fakes, started } = await makeTestDeps();
    const { token } = await signIn(yoga, apple);
    const r = await gqlUpload(yoga, { query: CREATE, variables: {}, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('VOICE_NOT_ENROLLED');
    expect(fakes.r2.size).toBe(0);
    expect(started).toEqual([]);
  });
});

describe('session queries', () => {
  it('session returns own session with presigned audioUrl, null for others', async () => {
    const { yoga, token, deps, user, apple } = await enrolledUser();
    const [row] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r', status: 'COMPLETED', audioKey: 'affirmations/a.mp3' }).returning();
    const mine = await gql(yoga, { query: `{ session(id:"${row.id}"){ id status audioUrl } }` }, token);
    expect(mine.data.session).toEqual({ id: row.id, status: 'COMPLETED', audioUrl: 'https://r2.test/affirmations/a.mp3?signed' });
    const other = await signIn(yoga, apple, 'someone-else');
    const theirs = await gql(yoga, { query: `{ session(id:"${row.id}"){ id } }` }, other.token);
    expect(theirs.data.session).toBeNull();
  });
  it('sessions lists newest first with limit and before cursor', async () => {
    const { yoga, token, deps, user } = await enrolledUser();
    const t0 = new Date('2026-01-01T00:00:00Z');
    for (let i = 0; i < 3; i++) await deps.db.insert(sessions).values({ userId: user.id, recordingKey: `r${i}`, createdAt: new Date(+t0 + i * 1000) });
    const all = await gql(yoga, { query: '{ sessions { createdAt } }' }, token);
    expect(all.data.sessions.map((s: any) => s.createdAt)).toEqual(['2026-01-01T00:00:02.000Z', '2026-01-01T00:00:01.000Z', '2026-01-01T00:00:00.000Z']);
    const page = await gql(yoga, { query: '{ sessions(limit: 1, before: "2026-01-01T00:00:02.000Z") { createdAt } }' }, token);
    expect(page.data.sessions.map((s: any) => s.createdAt)).toEqual(['2026-01-01T00:00:01.000Z']);
  });
});
