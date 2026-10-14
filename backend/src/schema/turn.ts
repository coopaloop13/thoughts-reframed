import { and, asc, eq, notInArray } from 'drizzle-orm';
import { sessions, turns, type TurnRow } from '../db/schema.js';
import { builder, type Context } from './builder.js';
import { gqlError, requireUser } from './errors.js';
import { SessionStatusEnum, SessionType, loadOwnedSession } from './session.js';
import { loadUser } from './user.js';
import { bytesOf } from './voice.js';

export const TurnType = builder.objectRef<TurnRow>('Turn').implement({
  fields: (t) => ({
    id: t.exposeID('id'),
    status: t.field({ type: SessionStatusEnum, resolve: (r) => r.status }),
    userText: t.exposeString('userText', { nullable: true }),
    agentText: t.exposeString('agentText', { nullable: true }),
    audioUrl: t.string({ nullable: true, resolve: (r, _a, ctx) => (r.audioKey ? ctx.deps.r2.presignGet(r.audioKey) : null) }),
    crisis: t.exposeBoolean('crisis'),
    closing: t.exposeBoolean('closing'),
    error: t.exposeString('error', { nullable: true }),
    createdAt: t.field({ type: 'DateTime', resolve: (r) => r.createdAt }),
  }),
});

builder.objectField(SessionType, 'turns', (t) => t.field({
  type: [TurnType],
  resolve: (s, _a, ctx) => ctx.deps.db.select().from(turns).where(eq(turns.sessionId, s.id)).orderBy(asc(turns.createdAt)),
}));

export async function loadOwnedTurn(ctx: Pick<Context, 'deps'>, userId: string, id: string): Promise<TurnRow | null> {
  const [row] = await ctx.deps.db.select({ turn: turns }).from(turns)
    .innerJoin(sessions, eq(turns.sessionId, sessions.id))
    .where(and(eq(turns.id, id), eq(sessions.userId, userId)));
  return row?.turn ?? null;
}

builder.mutationField('sendTurn', (t) => t.field({
  type: TurnType,
  args: { sessionId: t.arg.id({ required: true }), recording: t.arg({ type: 'File', required: true }) },
  resolve: async (_r, { sessionId, recording }, ctx) => {
    const userId = requireUser(ctx);
    const user = await loadUser(ctx, userId);
    if (!user.voiceProfileId) throw gqlError('VOICE_NOT_ENROLLED', 'Enroll a voice before chatting');
    const session = await loadOwnedSession(ctx, userId, String(sessionId));
    if (!session) throw gqlError('NOT_FOUND', 'Session not found');
    if (session.status !== 'COMPLETED') throw gqlError('SESSION_NOT_READY', 'Wait for the affirmation before chatting');
    const [inFlight] = await ctx.deps.db.select({ id: turns.id }).from(turns)
      .where(and(eq(turns.sessionId, session.id), notInArray(turns.status, ['COMPLETED', 'FAILED']))).limit(1);
    if (inFlight) throw gqlError('TURN_IN_PROGRESS', 'The previous reply is still on its way');
    const id = crypto.randomUUID();
    const key = `turns/${id}.m4a`;
    await ctx.deps.r2.put(key, await bytesOf(recording), 'audio/mp4');
    const [row] = await ctx.deps.db.insert(turns).values({ id, sessionId: session.id, recordingKey: key }).returning();
    ctx.deps.startTurn(id);
    return row;
  },
}));
