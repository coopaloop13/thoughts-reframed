import { eq } from 'drizzle-orm';
import { sessions, users } from '../db/schema.js';
import { builder } from './builder.js';
import { requireUser } from './errors.js';
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
    if (before.voiceProfileId) await voice.deleteProfile(before.voiceProfileId);
    const [user] = await db.update(users).set({ voiceProfileId: profileId, voiceSampleKey: key }).where(eq(users.id, userId)).returning();
    return user;
  },
}));

builder.mutationField('deleteAccount', (t) => t.boolean({
  resolve: async (_r, _a, ctx) => {
    const userId = requireUser(ctx);
    const { db, r2, voice } = ctx.deps;
    const user = await loadUser(ctx, userId);
    if (user.voiceProfileId) await voice.deleteProfile(user.voiceProfileId);
    const keys = [user.voiceSampleKey];
    for (const s of await db.select().from(sessions).where(eq(sessions.userId, userId))) keys.push(s.recordingKey, s.audioKey);
    for (const k of keys) if (k) await r2.delete(k);
    await db.delete(users).where(eq(users.id, userId));
    return true;
  },
}));
