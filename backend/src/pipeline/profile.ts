import { eq } from 'drizzle-orm';
import { loadContext, loadContextSession } from '../agent/context.js';
import { users } from '../db/schema.js';
import type { Deps } from '../deps.js';

// ponytail: last-writer-wins; turns within a session are sequential so this is safe. Add a per-user lock if concurrent sessions appear.
export async function refreshProfile(deps: Deps, userId: string, sessionId: string): Promise<void> {
  const [ctx, session] = await Promise.all([loadContext(deps.db, userId, { exclude: sessionId }), loadContextSession(deps.db, sessionId)]);
  if (!session) return;
  const profile = await deps.agent.updateProfile(ctx, session);
  await deps.db.update(users).set({ profile, profileUpdatedAt: new Date() }).where(eq(users.id, userId));
}

export const refreshProfileQuietly = (deps: Deps, userId: string, sessionId: string) =>
  refreshProfile(deps, userId, sessionId).catch((e) => console.error('profile refresh failed', sessionId, e));
