import { describe, expect, it, vi } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, turns, users } from '../../src/db/schema.js';
import { runTurn, sweepStuckTurns } from '../../src/pipeline/turn.js';
import { makeTestDeps } from '../helpers/app.js';

type Deps = Awaited<ReturnType<typeof makeTestDeps>>['deps'];

async function seed(deps: Deps, over: Partial<typeof turns.$inferInsert> = {}) {
  const [u] = await deps.db.insert(users).values({ appleSub: `s-${Math.random()}`, voiceProfileId: 'vp1' }).returning();
  const [s] = await deps.db.insert(sessions).values({ userId: u.id, recordingKey: 'r', status: 'COMPLETED', transcript: 'I always mess up', reframedText: 'I am learning', audioKey: 'a' }).returning();
  const [t] = await deps.db.insert(turns).values({ sessionId: s.id, recordingKey: 'turns/x.m4a', ...over }).returning();
  return { u, s, t };
}
const statusesSeen = (deps: Deps, id: string) => {
  const seen: string[] = [];
  const it = deps.pubsub.subscribe('turn', id);
  (async () => { for await (const r of it) seen.push(r.status); })();
  return seen;
};
const by = async (deps: Deps, id: string) => (await deps.db.select().from(turns).where(eq(turns.id, id)))[0];

describe('runTurn', () => {
  it('transcribes, asks the agent with prior turns, synthesizes, completes, refreshes profile', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.voice.transcript = 'Everyone noticed';
    const { s, t, u } = await seed(deps);
    await deps.db.insert(turns).values({ sessionId: s.id, recordingKey: 'k', status: 'COMPLETED', userText: 'earlier', agentText: 'reply earlier', createdAt: new Date(+t.createdAt - 1000) });
    const seen = statusesSeen(deps, t.id);
    await runTurn(deps, t.id);
    const row = await by(deps, t.id);
    expect(row.status).toBe('COMPLETED');
    expect(row.userText).toBe('Everyone noticed');
    expect(row.agentText).toBe('Reply: Everyone noticed');
    expect(row.audioKey).toBe(`turns/${t.id}.mp3`);
    expect(fakes.r2.get(row.audioKey!)).toEqual(fakes.voice.synthesized);
    expect(fakes.voice.lastSynthesize).toEqual({ text: 'Reply: Everyone noticed', voice: 'vp1' });
    expect(fakes.agentCalls.chat[0]).toEqual({ prior: [{ userText: 'earlier', agentText: 'reply earlier' }], userText: 'Everyone noticed' });
    expect((await deps.db.select().from(users).where(eq(users.id, u.id)))[0].profile).toBe('Notes after: I always mess up');
    await new Promise((r) => setTimeout(r, 0));
    expect(seen).toEqual(['TRANSCRIBING', 'REFRAMING', 'SYNTHESIZING', 'COMPLETED']);
  });
  it('stores crisis and closing from the agent', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.crisis = true; fakes.closing = true;
    const { t } = await seed(deps);
    await runTurn(deps, t.id);
    const row = await by(deps, t.id);
    expect(row.crisis).toBe(true);
    expect(row.closing).toBe(true);
  });
  it('fails with EMPTY_TRANSCRIPT on silence', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.voice.transcript = '   ';
    const { t } = await seed(deps);
    await runTurn(deps, t.id);
    const row = await by(deps, t.id);
    expect(row.status).toBe('FAILED');
    expect(row.error).toBe('EMPTY_TRANSCRIPT');
    expect(fakes.agentCalls.chat).toEqual([]);
  });
  it('marks FAILED when the agent throws, without throwing', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.agentFail = true;
    const { t } = await seed(deps);
    const seen = statusesSeen(deps, t.id);
    await expect(runTurn(deps, t.id)).resolves.toBeUndefined();
    const row = await by(deps, t.id);
    expect(row.status).toBe('FAILED');
    expect(row.error).toBe('llm 500');
    await new Promise((r) => setTimeout(r, 0));
    expect(seen).toEqual(['TRANSCRIBING', 'REFRAMING', 'FAILED']);
  });
  it('resumes from the first missing stage', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.voice.fail = 'transcribe';
    const { t } = await seed(deps, { status: 'REFRAMING', userText: 'already here' });
    await runTurn(deps, t.id);
    expect((await by(deps, t.id)).agentText).toBe('Reply: already here');
  });
  it('is a no-op for terminal turns and never rejects when the db is down', async () => {
    const { deps, fakes } = await makeTestDeps();
    const { t } = await seed(deps, { status: 'COMPLETED', userText: 'u', agentText: 'a', audioKey: 'k' });
    await runTurn(deps, t.id);
    expect(fakes.agentCalls.chat).toEqual([]);
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    await expect(runTurn({ ...deps, db: { select() { throw new Error('db down'); } } as any }, 'x')).resolves.toBeUndefined();
    spy.mockRestore();
  });
});

describe('sweepStuckTurns', () => {
  it('re-runs only non-terminal turns older than the threshold', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    const old = new Date(Date.now() - 10 * 60_000);
    const stuck = await seed(deps, { status: 'TRANSCRIBING', updatedAt: old });
    const fresh = await seed(deps, { status: 'TRANSCRIBING' });
    const done = await seed(deps, { status: 'COMPLETED', updatedAt: old });
    expect(await sweepStuckTurns(deps)).toEqual([stuck.t.id]);
    expect((await by(deps, stuck.t.id)).status).toBe('COMPLETED');
    expect((await by(deps, fresh.t.id)).status).toBe('TRANSCRIBING');
    expect((await by(deps, done.t.id)).status).toBe('COMPLETED');
  });
});
