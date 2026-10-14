import { eq } from 'drizzle-orm';
import { sessions, turns, users } from '../db/schema.js';
import { builder } from './builder.js';
import { gqlError, requireUser } from './errors.js';
import { UserType, loadUser } from './user.js';

export const bytesOf = async (f: File) => new Uint8Array(await f.arrayBuffer());

builder.mutationField('enrollVoice', (t) => t.field({
  type: UserType,
  args: { sample: t.arg({ type: 'File', required: true }), referenceText: t.arg.string({ required: true }) },
  resolve: async (_r, { sample, referenceText }, ctx) => {
    const userId = requireUser(ctx);
    const { db, r2, voice } = ctx.deps;
    const before = await loadUser(ctx, userId);
    const audio = await bytesOf(sample);
    const key = `voices/${userId}.m4a`;
    await r2.put(key, audio, 'audio/mp4');
    const profileId = await voice.createProfile({ name: userId, audio, referenceText });
    const [user] = await db.update(users).set({ voiceProfileId: profileId, voiceSampleKey: key }).where(eq(users.id, userId)).returning();
    if (before.voiceProfileId) {
      try { await voice.deleteProfile(before.voiceProfileId); } catch (err) { console.error('failed to delete old voice profile', before.voiceProfileId, err); }
    }
    return user;
  },
}));

export const PREVIEW_SENTENCE = "Here's how your reframed thoughts will sound.";

builder.mutationField('previewVoice', (t) => t.string({
  resolve: async (_r, _a, ctx) => {
    const userId = requireUser(ctx);
    const { r2, voice } = ctx.deps;
    const user = await loadUser(ctx, userId);
    if (!user.voiceProfileId) throw gqlError('VOICE_NOT_ENROLLED', 'Enroll a voice before previewing it');
    const key = `voices/${userId}-preview.mp3`;
    await r2.put(key, await voice.synthesize({ text: PREVIEW_SENTENCE, voice: user.voiceProfileId }), 'audio/mpeg');
    return r2.presignGet(key);
  },
}));

builder.mutationField('deleteAccount', (t) => t.boolean({
  resolve: async (_r, _a, ctx) => {
    const userId = requireUser(ctx);
    const { db, r2, voice } = ctx.deps;
    const user = await loadUser(ctx, userId);
    // Deterministic key: covers a sample uploaded by an enrollment that failed before the row was updated.
    const keys: (string | null)[] = [`voices/${userId}.m4a`, `voices/${userId}-preview.mp3`];
    for (const s of await db.select().from(sessions).where(eq(sessions.userId, userId))) keys.push(s.recordingKey, s.audioKey);
    for (const t of await db.select({ recordingKey: turns.recordingKey, audioKey: turns.audioKey }).from(turns)
      .innerJoin(sessions, eq(turns.sessionId, sessions.id)).where(eq(sessions.userId, userId))) keys.push(t.recordingKey, t.audioKey);
    for (const k of keys) if (k) await r2.delete(k);
    if (user.voiceProfileId) await voice.deleteProfile(user.voiceProfileId);
    await db.delete(users).where(eq(users.id, userId));
    return true;
  },
}));
