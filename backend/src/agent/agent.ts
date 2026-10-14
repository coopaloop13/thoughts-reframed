import { renderContext, renderSession, type AgentContext, type ContextSession, type ContextTurn } from './context.js';
import { hasCrisisLanguage } from './crisis.js';
import type { LLM } from './llm.js';
import { CHAT_INSTRUCTIONS, PROFILE_INSTRUCTIONS, REFRAME_INSTRUCTIONS, THERAPIST_SYSTEM } from './prompts.js';

export type ReframeResult = { affirmation: string; crisis: boolean };
export type ChatResult = { reply: string; crisis: boolean; closing: boolean };
export type Agent = {
  reframe(ctx: AgentContext, transcript: string): Promise<ReframeResult>;
  chatTurn(ctx: AgentContext, session: { transcript: string; affirmation: string }, prior: ContextTurn[], userText: string): Promise<ChatResult>;
  updateProfile(ctx: AgentContext, session: ContextSession): Promise<string>;
};

function parseJson(text: string): Record<string, unknown> {
  const body = text.replace(/^\s*```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '');
  try {
    const v = JSON.parse(body);
    if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>;
  } catch { /* fall through */ }
  throw new Error('agent: bad reply');
}
const str = (o: Record<string, unknown>, k: string): string => {
  const v = o[k];
  if (typeof v !== 'string' || !v.trim()) throw new Error('agent: bad reply');
  return v.trim();
};
const bool = (o: Record<string, unknown>, k: string): boolean => o[k] === true;

export function createAgent(llm: LLM): Agent {
  const ask = (content: string, json = true) => llm({ system: THERAPIST_SYSTEM, messages: [{ role: 'user', content }], ...(json ? { json } : {}) });
  return {
    async reframe(ctx, transcript) {
      const o = parseJson(await ask(`${REFRAME_INSTRUCTIONS}\n\n${renderContext(ctx)}\n\nNew thought:\n"""${transcript}"""`));
      return { affirmation: str(o, 'affirmation'), crisis: hasCrisisLanguage(transcript) || bool(o, 'crisis') };
    },
    async chatTurn(ctx, session, prior, userText) {
      const convo = prior.flatMap((t) => [`Person: ${t.userText}`, `You: ${t.agentText}`]).join('\n');
      const content = `${CHAT_INSTRUCTIONS}\n\n${renderContext(ctx)}\n\nThis session:\nThought: "${session.transcript}"\nAffirmation: "${session.affirmation}"\n\nConversation so far:\n${convo || '(none yet)'}\n\nPerson (latest): ${userText}`;
      const o = parseJson(await ask(content));
      const crisis = hasCrisisLanguage(userText) || bool(o, 'crisis');
      return { reply: str(o, 'reply'), crisis, closing: !crisis && bool(o, 'closing') };
    },
    async updateProfile(ctx, session) {
      const content = `${PROFILE_INSTRUCTIONS}\n\nOld notes:\n${ctx.profile?.trim() || '(none)'}\n\nSession just finished:\n${renderSession(session)}`;
      return (await ask(content, false)).trim();
    },
  };
}
