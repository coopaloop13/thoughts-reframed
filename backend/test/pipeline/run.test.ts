import { describe, expect, it, vi } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, users, type SessionRow } from '../../src/db/schema.js';
import { runPipeline, sweepStuckSessions } from '../../src/pipeline/run.js';
import { makeTestDeps } from '../helpers/app.js';

async function seed(deps: Awaited<ReturnType<typeof makeTestDeps>>['deps'], over: Partial<typeof sessions.$inferInsert> = {}) {
  const [u] = await deps.db.insert(users).values({ appleSub: `s-${Math.random()}`, voiceProfileId: 'vp1' }).returning();
  const [s] = await deps.db.insert(sessions).values({ userId: u.id, recordingKey: 'recordings/x.m4a', ...over }).returning();
  return s;
}
const statusesSeen = (deps: Awaited<ReturnType<typeof makeTestDeps>>['deps'], id: string) => {
  const seen: string[] = [];
  const it = deps.pubsub.subscribe('session', id);
  (async () => { for await (const s of it) seen.push(s.status); })();
  return seen;
};

describe('runPipeline', () => {
  it('passes the user context to the agent and stores the crisis flag', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    fakes.crisis = true;
    const s = await seed(deps);
    await deps.db.update(users).set({ profile: 'old notes' }).where(eq(users.id, s.userId));
    await runPipeline(deps, s.id);
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('COMPLETED');
    expect(row.crisis).toBe(true);
    expect(fakes.agentCalls.reframe[0].profile).toBe('old notes');
  });
  it('refreshes the profile after completing', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    const s = await seed(deps);
    await runPipeline(deps, s.id);
    const [u] = await deps.db.select().from(users).where(eq(users.id, s.userId));
    expect(u.profile).toBe('Notes after: I always mess things up');
    expect(u.profileUpdatedAt).toBeInstanceOf(Date);
    expect(fakes.agentCalls.profile[0].affirmation).toBe('Reframed: I always mess things up');
  });
  it('keeps the session COMPLETED when the profile refresh fails', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    fakes.profileFail = true;
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const s = await seed(deps);
    await runPipeline(deps, s.id);
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('COMPLETED');
    const [u] = await deps.db.select().from(users).where(eq(users.id, s.userId));
    expect(u.profile).toBeNull();
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });
  it('runs all stages, stores mp3, publishes each transition', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    const s = await seed(deps);
    const seen = statusesSeen(deps, s.id);
    await runPipeline(deps, s.id);
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('COMPLETED');
    expect(row.transcript).toBe('I always mess things up');
    expect(row.reframedText).toBe('Reframed: I always mess things up');
    expect(row.audioKey).toBe(`affirmations/${s.id}.mp3`);
    expect(fakes.r2.get(row.audioKey!)).toEqual(fakes.voice.synthesized);
    await new Promise((r) => setTimeout(r, 0));
    expect(seen).toEqual(['TRANSCRIBING', 'REFRAMING', 'SYNTHESIZING', 'COMPLETED']);
  });
  it('marks FAILED with the error and publishes, without throwing', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    fakes.agentFail = true;
    const s = await seed(deps);
    const seen = statusesSeen(deps, s.id);
    await expect(runPipeline(deps, s.id)).resolves.toBeUndefined();
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('FAILED');
    expect(row.error).toBe('llm 500');
    expect(row.transcript).toBe('I always mess things up');
    await new Promise((r) => setTimeout(r, 0));
    expect(seen).toEqual(['TRANSCRIBING', 'REFRAMING', 'FAILED']);
  });
  it('resumes from the first missing stage', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    fakes.voice.fail = 'transcribe';
    const s = await seed(deps, { status: 'REFRAMING', transcript: 'already transcribed' });
    await runPipeline(deps, s.id);
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('COMPLETED');
    expect(row.reframedText).toBe('Reframed: already transcribed');
  });
  it('is a no-op for terminal sessions', async () => {
    const { deps, fakes } = await makeTestDeps();
    const s = await seed(deps, { status: 'COMPLETED', transcript: 't', reframedText: 'r', audioKey: 'a' });
    await runPipeline(deps, s.id);
    expect(fakes.r2.size).toBe(0);
  });
});

describe('runPipeline hardening', () => {
  it('never rejects when the db is down', async () => {
    const { deps } = await makeTestDeps();
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const broken = { ...deps, db: { select() { throw new Error('db down'); } } as any };
    await expect(runPipeline(broken, 'any-id')).resolves.toBeUndefined();
    spy.mockRestore();
  });
  it('stops without side effects when the session is deleted mid-run', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    const s = await seed(deps);
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    deps.voice.transcribe = async () => { await deps.db.delete(sessions).where(eq(sessions.id, s.id)); return 't'; };
    await expect(runPipeline(deps, s.id)).resolves.toBeUndefined();
    expect([...fakes.r2.keys()].some((k) => k.startsWith('affirmations/'))).toBe(false);
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });
});

describe('sweepStuckSessions', () => {
  it('re-runs only non-terminal sessions older than the threshold', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    const old = new Date(Date.now() - 10 * 60_000);
    const stuck = await seed(deps, { status: 'TRANSCRIBING', updatedAt: old });
    const fresh = await seed(deps, { status: 'TRANSCRIBING' });
    const done = await seed(deps, { status: 'COMPLETED', updatedAt: old });
    expect(await sweepStuckSessions(deps)).toEqual([stuck.id]);
    const by = async (id: string) => (await deps.db.select().from(sessions).where(eq(sessions.id, id)))[0] as SessionRow;
    expect((await by(stuck.id)).status).toBe('COMPLETED');
    expect((await by(fresh.id)).status).toBe('TRANSCRIBING');
    expect((await by(done.id)).status).toBe('COMPLETED');
  });
});
