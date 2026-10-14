import { describe, expect, it } from 'vitest';
import { loadContext, loadContextSession } from '../../src/agent/context.js';
import { sessions, turns, users } from '../../src/db/schema.js';
import { makeTestDb } from '../helpers/db.js';

async function seed() {
  const db = await makeTestDb();
  const [u] = await db.insert(users).values({ appleSub: 'a', profile: 'notes' }).returning();
  const t0 = +new Date('2026-01-01T00:00:00Z');
  const ids: string[] = [];
  for (let i = 0; i < 7; i++) {
    const [s] = await db.insert(sessions).values({ userId: u.id, recordingKey: `r${i}`, status: 'COMPLETED', transcript: `thought ${i}`, reframedText: `aff ${i}`, createdAt: new Date(t0 + i * 1000) }).returning();
    ids.push(s.id);
  }
  await db.insert(sessions).values({ userId: u.id, recordingKey: 'pending', status: 'REFRAMING', transcript: 'in flight', createdAt: new Date(t0 + 99_000) });
  await db.insert(turns).values({ sessionId: ids[6], recordingKey: 'k', status: 'COMPLETED', userText: 'u1', agentText: 'a1', createdAt: new Date(t0 + 1) });
  await db.insert(turns).values({ sessionId: ids[6], recordingKey: 'k', status: 'FAILED', userText: 'ignored', createdAt: new Date(t0 + 2) });
  await db.insert(turns).values({ sessionId: ids[6], recordingKey: 'k', status: 'COMPLETED', userText: 'u2', agentText: 'a2', createdAt: new Date(t0 + 3) });
  return { db, u, ids };
}

describe('loadContext', () => {
  it('returns profile and the last 5 completed sessions oldest first, with completed turns in order', async () => {
    const { db, u } = await seed();
    const ctx = await loadContext(db, u.id);
    expect(ctx.profile).toBe('notes');
    expect(ctx.recent.map((s) => s.transcript)).toEqual(['thought 2', 'thought 3', 'thought 4', 'thought 5', 'thought 6']);
    expect(ctx.recent[4].turns).toEqual([{ userText: 'u1', agentText: 'a1' }, { userText: 'u2', agentText: 'a2' }]);
    expect(ctx.recent[0].turns).toEqual([]);
  });
  it('can exclude the current session', async () => {
    const { db, u, ids } = await seed();
    const ctx = await loadContext(db, u.id, { exclude: ids[6] });
    expect(ctx.recent.map((s) => s.transcript)).toEqual(['thought 1', 'thought 2', 'thought 3', 'thought 4', 'thought 5']);
  });
  it('is empty for a new user', async () => {
    const db = await makeTestDb();
    const [u] = await db.insert(users).values({ appleSub: 'new' }).returning();
    expect(await loadContext(db, u.id)).toEqual({ profile: null, recent: [] });
  });
});

describe('loadContextSession', () => {
  it('returns the session with its completed turns, null when missing', async () => {
    const { db, ids } = await seed();
    const s = await loadContextSession(db, ids[6]);
    expect(s?.transcript).toBe('thought 6');
    expect(s?.affirmation).toBe('aff 6');
    expect(s?.turns.map((t) => t.userText)).toEqual(['u1', 'u2']);
    expect(await loadContextSession(db, '00000000-0000-0000-0000-000000000000')).toBeNull();
  });
});
