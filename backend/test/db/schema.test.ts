import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, turns, users } from '../../src/db/schema.js';
import { makeTestDb } from '../helpers/db.js';

describe('schema', () => {
  it('has profile on users, crisis on sessions, and turns cascading from sessions', async () => {
    const db = await makeTestDb();
    const [u] = await db.insert(users).values({ appleSub: 'a', profile: 'notes', profileUpdatedAt: new Date() }).returning();
    expect(u.profile).toBe('notes');
    const [s] = await db.insert(sessions).values({ userId: u.id, recordingKey: 'r' }).returning();
    expect(s.crisis).toBe(false);
    const [t] = await db.insert(turns).values({ sessionId: s.id, recordingKey: 'turns/x.m4a' }).returning();
    expect(t.status).toBe('UPLOADED');
    expect(t.crisis).toBe(false);
    expect(t.closing).toBe(false);
    await db.delete(sessions).where(eq(sessions.id, s.id));
    expect(await db.select().from(turns)).toEqual([]);
  });
});
