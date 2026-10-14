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
