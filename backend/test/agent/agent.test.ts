import { describe, expect, it } from 'vitest';
import { createAgent } from '../../src/agent/agent.js';
import { renderContext, type AgentContext, type ContextSession } from '../../src/agent/context.js';
import type { LLMRequest } from '../../src/agent/llm.js';
import { CHAT_INSTRUCTIONS, PROFILE_INSTRUCTIONS, REFRAME_INSTRUCTIONS, THERAPIST_SYSTEM } from '../../src/agent/prompts.js';

const session: ContextSession = {
  createdAt: new Date('2026-10-01T10:00:00Z'), transcript: 'I always mess things up at work', affirmation: 'I am learning at work', crisis: false,
  turns: [{ userText: 'Everyone noticed', agentText: 'What makes you think everyone noticed?' }],
};
const ctx: AgentContext = { profile: 'Tends to catastrophize about work.', recent: [session] };
const empty: AgentContext = { profile: null, recent: [] };

function stubLLM(reply: string) {
  const calls: LLMRequest[] = [];
  const llm = async (req: LLMRequest) => { calls.push(req); return reply; };
  return { llm, calls };
}

describe('renderContext', () => {
  it('renders profile and recent sessions oldest first with turns', () => {
    const out = renderContext(ctx);
    expect(out).toContain('Tends to catastrophize about work.');
    expect(out).toContain('[2026-10-01] Thought: "I always mess things up at work"');
    expect(out).toContain('Affirmation: "I am learning at work"');
    expect(out).toContain('Person: Everyone noticed');
    expect(out).toContain('You: What makes you think everyone noticed?');
  });
  it('says so when there is no history', () => {
    const out = renderContext(empty);
    expect(out).toContain('None yet');
    expect(out).toContain('No sessions yet');
  });
});

describe('agent.reframe', () => {
  it('sends system prompt, instructions, context and the thought in json mode; parses the result', async () => {
    const { llm, calls } = stubLLM('{"affirmation": "I am learning.", "crisis": false}');
    const r = await createAgent(llm).reframe(ctx, 'I always mess things up');
    expect(r).toEqual({ affirmation: 'I am learning.', crisis: false });
    expect(calls[0].system).toBe(THERAPIST_SYSTEM);
    expect(calls[0].json).toBe(true);
    expect(calls[0].messages).toHaveLength(1);
    expect(calls[0].messages[0].role).toBe('user');
    expect(calls[0].messages[0].content).toContain(REFRAME_INSTRUCTIONS);
    expect(calls[0].messages[0].content).toContain(renderContext(ctx));
    expect(calls[0].messages[0].content).toContain('New thought:\n"""I always mess things up"""');
  });
  it('parses fenced JSON', async () => {
    const { llm } = stubLLM('```json\n{"affirmation": "ok", "crisis": false}\n```');
    expect(await createAgent(llm).reframe(empty, 'x')).toEqual({ affirmation: 'ok', crisis: false });
  });
  it('keyword floor overrides the model', async () => {
    const { llm } = stubLLM('{"affirmation": "I am fine.", "crisis": false}');
    expect((await createAgent(llm).reframe(empty, 'I want to kill myself')).crisis).toBe(true);
  });
  it('throws on a malformed reply', async () => {
    const { llm } = stubLLM('{"text": "nope"}');
    await expect(createAgent(llm).reframe(empty, 'x')).rejects.toThrow('agent: bad reply');
    const bad = stubLLM('not json at all');
    await expect(createAgent(bad.llm).reframe(empty, 'x')).rejects.toThrow('agent: bad reply');
  });
});

describe('agent.chatTurn', () => {
  it('includes the session, prior turns and the new message; parses reply/crisis/closing', async () => {
    const { llm, calls } = stubLLM('{"reply": "What went wrong, specifically?", "crisis": false, "closing": false}');
    const r = await createAgent(llm).chatTurn(ctx, { transcript: 'I always mess up', affirmation: 'I am learning' },
      [{ userText: 'My boss sighed', agentText: 'A sigh can mean many things.' }], 'I think she hates me');
    expect(r).toEqual({ reply: 'What went wrong, specifically?', crisis: false, closing: false });
    const c = calls[0].messages[0].content;
    expect(calls[0].json).toBe(true);
    expect(c).toContain(CHAT_INSTRUCTIONS);
    expect(c).toContain('Thought: "I always mess up"');
    expect(c).toContain('Affirmation: "I am learning"');
    expect(c).toContain('Person: My boss sighed');
    expect(c).toContain('You: A sigh can mean many things.');
    expect(c).toContain('Person (latest): I think she hates me');
  });
  it('keyword floor overrides the model and forces closing false', async () => {
    const { llm } = stubLLM('{"reply": "ok", "crisis": false, "closing": true}');
    const r = await createAgent(llm).chatTurn(empty, { transcript: 't', affirmation: 'a' }, [], 'I want to end my life');
    expect(r.crisis).toBe(true);
    expect(r.closing).toBe(false);
  });
});

describe('agent.updateProfile', () => {
  it('sends old profile + session in plain-text mode and returns the trimmed reply', async () => {
    const { llm, calls } = stubLLM('  New notes.  ');
    expect(await createAgent(llm).updateProfile(ctx, session)).toBe('New notes.');
    expect(calls[0].json).toBeUndefined();
    const c = calls[0].messages[0].content;
    expect(c).toContain(PROFILE_INSTRUCTIONS);
    expect(c).toContain('Tends to catastrophize about work.');
    expect(c).toContain('Thought: "I always mess things up at work"');
  });
});
