import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { makeTestDb } from './helpers/db.js';
import { sessions, users } from '../src/db/schema.js';

describe('schema', () => {
  it('inserts a user and a session with default status UPLOADED', async () => {
    const db = await makeTestDb();
    const [u] = await db.insert(users).values({ appleSub: 'sub-1' }).returning();
    const [s] = await db.insert(sessions).values({ userId: u.id, recordingKey: `recordings/x.m4a` }).returning();
    expect(s.status).toBe('UPLOADED');
    expect(s.transcript).toBeNull();
    const found = await db.select().from(sessions).where(eq(sessions.userId, u.id));
    expect(found).toHaveLength(1);
  });
  it('cascades session delete when the user is deleted', async () => {
    const db = await makeTestDb();
    const [u] = await db.insert(users).values({ appleSub: 'sub-2' }).returning();
    await db.insert(sessions).values({ userId: u.id, recordingKey: 'r' });
    await db.delete(users).where(eq(users.id, u.id));
    expect(await db.select().from(sessions)).toHaveLength(0);
  });
});
