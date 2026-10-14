import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, turns, users } from '../../src/db/schema.js';
import { gql, makeTestDeps, signIn } from '../helpers/app.js';
import { gqlUpload } from '../helpers/upload.js';

const ENROLL = 'mutation($s:File!,$t:String!){ enrollVoice(sample:$s, referenceText:$t){ id } }';
const SEND = 'mutation($id:ID!,$r:File!){ sendTurn(sessionId:$id, recording:$r){ id status userText agentText audioUrl crisis closing error createdAt } }';
const rec = { field: 'r', bytes: new Uint8Array([7]), name: 'turn.m4a', type: 'audio/mp4' };
const sample = { field: 's', bytes: new Uint8Array([5]), name: 'v.m4a', type: 'audio/mp4' };

async function withCompletedSession() {
  const t = await makeTestDeps();
  const { token, user } = await signIn(t.yoga, t.apple);
  await gqlUpload(t.yoga, { query: ENROLL, variables: { t: 'x' }, file: sample }, token);
  const [session] = await t.deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r', status: 'COMPLETED', transcript: 'thought', reframedText: 'aff', audioKey: 'affirmations/a.mp3' }).returning();
  return { ...t, token, user, session };
}

describe('sendTurn', () => {
  it('stores the recording, returns UPLOADED, starts the turn pipeline', async () => {
    const { yoga, token, fakes, startedTurns, session } = await withCompletedSession();
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors).toBeUndefined();
    const turn = r.data.sendTurn;
    expect(turn.status).toBe('UPLOADED');
    expect(turn.crisis).toBe(false);
    expect(turn.closing).toBe(false);
    expect(fakes.r2.get(`turns/${turn.id}.m4a`)).toEqual(rec.bytes);
    expect(startedTurns).toEqual([turn.id]);
  });
  it('rejects a session that is not COMPLETED', async () => {
    const { yoga, token, deps, session, fakes } = await withCompletedSession();
    await deps.db.update(sessions).set({ status: 'REFRAMING' }).where(eq(sessions.id, session.id));
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('SESSION_NOT_READY');
    expect([...fakes.r2.keys()].some((k) => k.startsWith('turns/'))).toBe(false);
  });
  it('rejects while a previous turn is still in flight', async () => {
    const { yoga, token, deps, session } = await withCompletedSession();
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'TRANSCRIBING' });
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('TURN_IN_PROGRESS');
  });
  it('allows a new turn after a FAILED one', async () => {
    const { yoga, token, deps, session } = await withCompletedSession();
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'FAILED' });
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors).toBeUndefined();
  });
  it('is NOT_FOUND for someone else’s session', async () => {
    const { yoga, apple, session } = await withCompletedSession();
    const other = await signIn(yoga, apple, 'other');
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'x' }, file: sample }, other.token);
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, other.token);
    expect(r.errors?.[0].extensions?.code).toBe('NOT_FOUND');
  });
  it('requires an enrolled voice', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    const [s] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r', status: 'COMPLETED' }).returning();
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: s.id }, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('VOICE_NOT_ENROLLED');
  });
});

describe('Session.turns, Session.crisis, User.profile', () => {
  it('exposes turns oldest first with presigned audio, crisis, and profile', async () => {
    const { yoga, token, deps, session, user } = await withCompletedSession();
    await deps.db.update(sessions).set({ crisis: true }).where(eq(sessions.id, session.id));
    await deps.db.update(users).set({ profile: 'remembers you' }).where(eq(users.id, user.id));
    const t0 = new Date('2026-01-01T00:00:00Z');
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'COMPLETED', userText: 'u2', agentText: 'a2', audioKey: 'turns/b.mp3', createdAt: new Date(+t0 + 1000) });
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'COMPLETED', userText: 'u1', agentText: 'a1', audioKey: 'turns/a.mp3', createdAt: t0 });
    const r = await gql(yoga, { query: `{ me { profile } session(id:"${session.id}"){ crisis turns { userText agentText audioUrl } } }` }, token);
    expect(r.errors).toBeUndefined();
    expect(r.data.me.profile).toBe('remembers you');
    expect(r.data.session.crisis).toBe(true);
    expect(r.data.session.turns).toEqual([
      { userText: 'u1', agentText: 'a1', audioUrl: 'https://r2.test/turns/a.mp3?signed' },
      { userText: 'u2', agentText: 'a2', audioUrl: 'https://r2.test/turns/b.mp3?signed' },
    ]);
  });
});
