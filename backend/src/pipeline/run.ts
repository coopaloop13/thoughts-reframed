import { and, eq, lt, notInArray } from 'drizzle-orm';
import { sessions, users, type SessionRow, type SessionStatus } from '../db/schema.js';
import type { Deps } from '../deps.js';

const TERMINAL: SessionStatus[] = ['COMPLETED', 'FAILED'];

async function transition(deps: Deps, id: string, patch: Partial<typeof sessions.$inferInsert> & { status: SessionStatus }): Promise<SessionRow> {
  const [row] = await deps.db.update(sessions).set({ ...patch, updatedAt: new Date() }).where(and(eq(sessions.id, id), notInArray(sessions.status, TERMINAL))).returning();
  if (!row) throw new Error('session gone');
  deps.pubsub.publish('session', id, row);
  return row;
}

// ponytail: in-process runner + boot sweeper; move to a Cloudflare Queue consumer if jobs get lost in practice.
export async function runPipeline(deps: Deps, sessionId: string): Promise<void> {
  try {
    const [s] = await deps.db.select().from(sessions).where(eq(sessions.id, sessionId));
    if (!s || TERMINAL.includes(s.status)) return;
    try {
      let transcript = s.transcript;
      if (!transcript) {
        await transition(deps, sessionId, { status: 'TRANSCRIBING' });
        transcript = await deps.voice.transcribe(await deps.r2.get(s.recordingKey));
      }
      let reframedText = s.reframedText;
      if (!reframedText) {
        await transition(deps, sessionId, { status: 'REFRAMING', transcript });
        reframedText = await deps.reframe(transcript);
      }
      await transition(deps, sessionId, { status: 'SYNTHESIZING', transcript, reframedText });
      const [user] = await deps.db.select().from(users).where(eq(users.id, s.userId));
      if (!user?.voiceProfileId) throw new Error('VOICE_NOT_ENROLLED');
      const mp3 = await deps.voice.synthesize({ text: reframedText, voice: user.voiceProfileId });
      const audioKey = `affirmations/${sessionId}.mp3`;
      await deps.r2.put(audioKey, mp3, 'audio/mpeg');
      await transition(deps, sessionId, { status: 'COMPLETED', audioKey });
    } catch (err) {
      await transition(deps, sessionId, { status: 'FAILED', error: err instanceof Error ? err.message : String(err) });
    }
  } catch (err) {
    console.error('pipeline failed', sessionId, err);
  }
}

export async function sweepStuckSessions(deps: Deps, olderThanMs = 120_000): Promise<string[]> {
  const cutoff = new Date(Date.now() - olderThanMs);
  const stuck = await deps.db.select({ id: sessions.id }).from(sessions)
    .where(and(notInArray(sessions.status, TERMINAL), lt(sessions.updatedAt, cutoff)));
  for (const { id } of stuck) await runPipeline(deps, id);
  return stuck.map((s) => s.id);
}

export const createPipelineStarter = (deps: Deps) => (id: string) => {
  void runPipeline(deps, id).catch((e) => console.error('pipeline crashed', id, e));
};
