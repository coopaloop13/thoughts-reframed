import { eq } from 'drizzle-orm';
import { users, type UserRow } from '../db/schema.js';
import { builder } from './builder.js';
import { gqlError, requireUser } from './errors.js';

export const UserType = builder.objectRef<UserRow>('User').implement({
  fields: (t) => ({
    id: t.exposeID('id'),
    hasVoice: t.boolean({ resolve: (u) => u.voiceProfileId !== null }),
  }),
});

export async function loadUser(ctx: { deps: { db: import('../db/client.js').Db } }, id: string): Promise<UserRow> {
  const [u] = await ctx.deps.db.select().from(users).where(eq(users.id, id));
  if (!u) throw gqlError('NOT_FOUND', 'User not found');
  return u;
}

builder.queryField('me', (t) => t.field({ type: UserType, resolve: (_r, _a, ctx) => loadUser(ctx, requireUser(ctx)) }));
