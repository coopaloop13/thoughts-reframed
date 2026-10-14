import { and, asc, desc, eq, inArray, ne } from 'drizzle-orm';
import type { Db } from '../db/client.js';
import { sessions, turns, users, type SessionRow } from '../db/schema.js';

export type ContextTurn = { userText: string; agentText: string };
export type ContextSession = { createdAt: Date; transcript: string; affirmation: string; crisis: boolean; turns: ContextTurn[] };
export type AgentContext = { profile: string | null; recent: ContextSession[] };

const day = (d: Date) => d.toISOString().slice(0, 10);

export function renderSession(s: ContextSession): string {
  const lines = [`[${day(s.createdAt)}] Thought: "${s.transcript}" → Affirmation: "${s.affirmation}"${s.crisis ? ' (crisis flagged)' : ''}`];
  for (const t of s.turns) lines.push(`  Person: ${t.userText}`, `  You: ${t.agentText}`);
  return lines.join('\n');
}

export function renderContext(ctx: AgentContext): string {
  const profile = ctx.profile?.trim() || 'None yet — this is a new person.';
  const recent = ctx.recent.length ? ctx.recent.map(renderSession).join('\n') : 'No sessions yet.';
  return `Your notes about this person:\n${profile}\n\nRecent sessions (oldest first):\n${recent}`;
}

async function turnsFor(db: Db, sessionIds: string[]): Promise<Map<string, ContextTurn[]>> {
  const map = new Map<string, ContextTurn[]>();
  if (!sessionIds.length) return map;
  const rows = await db.select().from(turns)
    .where(and(inArray(turns.sessionId, sessionIds), eq(turns.status, 'COMPLETED')))
    .orderBy(asc(turns.createdAt));
  for (const t of rows) {
    if (!t.userText || !t.agentText) continue;
    map.set(t.sessionId, [...(map.get(t.sessionId) ?? []), { userText: t.userText, agentText: t.agentText }]);
  }
  return map;
}

const toContextSession = (s: SessionRow, t: ContextTurn[]): ContextSession =>
  ({ createdAt: s.createdAt, transcript: s.transcript ?? '', affirmation: s.reframedText ?? '', crisis: s.crisis, turns: t });

export async function loadContext(db: Db, userId: string, opts: { limit?: number; exclude?: string } = {}): Promise<AgentContext> {
  const [user] = await db.select({ profile: users.profile }).from(users).where(eq(users.id, userId));
  const where = [eq(sessions.userId, userId), eq(sessions.status, 'COMPLETED' as const)];
  if (opts.exclude) where.push(ne(sessions.id, opts.exclude));
  const rows = await db.select().from(sessions).where(and(...where)).orderBy(desc(sessions.createdAt)).limit(opts.limit ?? 5);
  const byId = await turnsFor(db, rows.map((r) => r.id));
  return { profile: user?.profile ?? null, recent: rows.reverse().map((s) => toContextSession(s, byId.get(s.id) ?? [])) };
}

export async function loadContextSession(db: Db, sessionId: string): Promise<ContextSession | null> {
  const [s] = await db.select().from(sessions).where(eq(sessions.id, sessionId));
  if (!s) return null;
  const byId = await turnsFor(db, [s.id]);
  return toContextSession(s, byId.get(s.id) ?? []);
}
