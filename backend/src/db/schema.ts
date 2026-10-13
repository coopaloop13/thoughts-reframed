import { pgEnum, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

export const SESSION_STATUSES = ['UPLOADED', 'TRANSCRIBING', 'REFRAMING', 'SYNTHESIZING', 'COMPLETED', 'FAILED'] as const;
export type SessionStatus = (typeof SESSION_STATUSES)[number];
export const sessionStatus = pgEnum('session_status', SESSION_STATUSES);

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  appleSub: text('apple_sub').notNull().unique(),
  voiceProfileId: text('voice_profile_id'),
  voiceSampleKey: text('voice_sample_key'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const sessions = pgTable('sessions', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  status: sessionStatus('status').notNull().default('UPLOADED'),
  recordingKey: text('recording_key').notNull(),
  transcript: text('transcript'),
  reframedText: text('reframed_text'),
  audioKey: text('audio_key'),
  error: text('error'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

export type UserRow = typeof users.$inferSelect;
export type SessionRow = typeof sessions.$inferSelect;
