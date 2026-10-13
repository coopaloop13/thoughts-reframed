import { and, desc, eq, lt } from 'drizzle-orm';
import { SESSION_STATUSES, sessions, type SessionRow } from '../db/schema.js';
import { builder } from './builder.js';
import { gqlError, requireUser } from './errors.js';
import { loadUser } from './user.js';
import { bytesOf } from './voice.js';

const SessionStatusEnum = builder.enumType('SessionStatus', { values: SESSION_STATUSES });

export const SessionType = builder.objectRef<SessionRow>('Session').implement({
  fields: (t) => ({
    id: t.exposeID('id'),
    status: t.field({ type: SessionStatusEnum, resolve: (s) => s.status }),
    transcript: t.exposeString('transcript', { nullable: true }),
    reframedText: t.exposeString('reframedText', { nullable: true }),
    error: t.exposeString('error', { nullable: true }),
    createdAt: t.field({ type: 'DateTime', resolve: (s) => s.createdAt }),
    audioUrl: t.string({ nullable: true, resolve: (s, _a, ctx) => (s.audioKey ? ctx.deps.r2.presignGet(s.audioKey) : null) }),
  }),
});

export async function loadOwnedSession(ctx: { deps: { db: import('../db/client.js').Db } }, userId: string, id: string): Promise<SessionRow | null> {
  const [s] = await ctx.deps.db.select().from(sessions).where(and(eq(sessions.id, id), eq(sessions.userId, userId)));
  return s ?? null;
}

builder.queryField('session', (t) => t.field({
  type: SessionType, nullable: true,
  args: { id: t.arg.id({ required: true }) },
  resolve: (_r, { id }, ctx) => loadOwnedSession(ctx, requireUser(ctx), String(id)),
}));

builder.queryField('sessions', (t) => t.field({
  type: [SessionType],
  args: { limit: t.arg.int({ defaultValue: 20 }), before: t.arg({ type: 'DateTime' }) },
  resolve: (_r, { limit, before }, ctx) => {
    const userId = requireUser(ctx);
    const where = before ? and(eq(sessions.userId, userId), lt(sessions.createdAt, before)) : eq(sessions.userId, userId);
    return ctx.deps.db.select().from(sessions).where(where).orderBy(desc(sessions.createdAt)).limit(Math.min(limit ?? 20, 100));
  },
}));

builder.mutationField('createSession', (t) => t.field({
  type: SessionType,
  args: { recording: t.arg({ type: 'File', required: true }) },
  resolve: async (_r, { recording }, ctx) => {
    const userId = requireUser(ctx);
    const user = await loadUser(ctx, userId);
    if (!user.voiceProfileId) throw gqlError('VOICE_NOT_ENROLLED', 'Enroll a voice before creating sessions');
    const id = crypto.randomUUID();
    const key = `recordings/${id}.m4a`;
    await ctx.deps.r2.put(key, await bytesOf(recording), 'audio/mp4');
    const [row] = await ctx.deps.db.insert(sessions).values({ id, userId, recordingKey: key }).returning();
    ctx.deps.startPipeline(id);
    return row;
  },
}));
