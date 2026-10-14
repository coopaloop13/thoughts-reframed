import { and, asc, eq, lt, notInArray } from 'drizzle-orm';
import { loadContext, type ContextTurn } from '../agent/context.js';
import { sessions, turns, users, type SessionStatus, type TurnRow } from '../db/schema.js';
import type { Deps } from '../deps.js';
import { refreshProfileQuietly } from './profile.js';

const TERMINAL: SessionStatus[] = ['COMPLETED', 'FAILED'];

// ponytail: duplicated from run.ts rather than a generic over two Drizzle tables; 10 lines beats fighting the table generics.
async function transition(deps: Deps, id: string, patch: Partial<typeof turns.$inferInsert> & { status: SessionStatus }): Promise<TurnRow> {
  const [row] = await deps.db.update(turns).set({ ...patch, updatedAt: new Date() }).where(and(eq(turns.id, id), notInArray(turns.status, TERMINAL))).returning();
  if (!row) throw new Error('turn gone');
  deps.pubsub.publish('turn', id, row);
  return row;
}

async function priorTurns(deps: Deps, sessionId: string, before: Date): Promise<ContextTurn[]> {
  const rows = await deps.db.select().from(turns)
    .where(and(eq(turns.sessionId, sessionId), eq(turns.status, 'COMPLETED'), lt(turns.createdAt, before)))
    .orderBy(asc(turns.createdAt));
  return rows.flatMap((r) => (r.userText && r.agentText ? [{ userText: r.userText, agentText: r.agentText }] : []));
}

export async function runTurn(deps: Deps, turnId: string): Promise<void> {
  try {
    const [t] = await deps.db.select().from(turns).where(eq(turns.id, turnId));
    if (!t || TERMINAL.includes(t.status)) return;
    const [s] = await deps.db.select().from(sessions).where(eq(sessions.id, t.sessionId));
    if (!s) throw new Error('session gone');
    try {
      let userText = t.userText;
      if (!userText) {
        await transition(deps, turnId, { status: 'TRANSCRIBING' });
        userText = (await deps.voice.transcribe(await deps.r2.get(t.recordingKey))).trim();
        if (!userText) throw new Error('EMPTY_TRANSCRIPT');
      }
      let { agentText, crisis, closing } = t;
      if (!agentText) {
        await transition(deps, turnId, { status: 'REFRAMING', userText });
        const [ctx, prior] = await Promise.all([loadContext(deps.db, s.userId, { exclude: s.id }), priorTurns(deps, s.id, t.createdAt)]);
        const r = await deps.agent.chatTurn(ctx, { transcript: s.transcript ?? '', affirmation: s.reframedText ?? '' }, prior, userText);
        agentText = r.reply;
        crisis = r.crisis;
        closing = r.closing;
      }
      await transition(deps, turnId, { status: 'SYNTHESIZING', userText, agentText, crisis, closing });
      const [user] = await deps.db.select().from(users).where(eq(users.id, s.userId));
      if (!user?.voiceProfileId) throw new Error('VOICE_NOT_ENROLLED');
      const mp3 = await deps.voice.synthesize({ text: agentText, voice: user.voiceProfileId });
      const audioKey = `turns/${turnId}.mp3`;
      await deps.r2.put(audioKey, mp3, 'audio/mpeg');
      await transition(deps, turnId, { status: 'COMPLETED', audioKey });
      await refreshProfileQuietly(deps, s.userId, s.id);
    } catch (err) {
      await transition(deps, turnId, { status: 'FAILED', error: err instanceof Error ? err.message : String(err) });
    }
  } catch (err) {
    console.error('turn pipeline failed', turnId, err);
  }
}

export async function sweepStuckTurns(deps: Deps, olderThanMs = 120_000): Promise<string[]> {
  const cutoff = new Date(Date.now() - olderThanMs);
  const stuck = await deps.db.select({ id: turns.id }).from(turns).where(and(notInArray(turns.status, TERMINAL), lt(turns.updatedAt, cutoff)));
  for (const { id } of stuck) await runTurn(deps, id);
  return stuck.map((r) => r.id);
}

export const createTurnStarter = (deps: Deps) => (id: string) => {
  void runTurn(deps, id).catch((e) => console.error('turn pipeline crashed', id, e));
};
