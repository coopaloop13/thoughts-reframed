# Therapist Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stateless OpenAI reframe with a CBT-style therapist agent that remembers each person (profile + recent sessions), offers an optional spoken follow-up conversation per session, and handles crisis language safely.

**Architecture:** A provider-agnostic `LLM` function type with an OpenAI adapter. On top of it, `createAgent(llm)` exposes three deterministic calls (`reframe`, `chatTurn`, `updateProfile`) whose context is assembled from Postgres by `loadContext`. A new `turns` table mirrors `sessions` so the follow-up chat reuses the transcribe → agent → synthesize pipeline and the subscription pattern. iOS adds a chat screen, a crisis card, and a read-only profile screen.

**Tech Stack:** Node 22 / TypeScript, graphql-yoga 5 + Pothos, drizzle-orm + Postgres (pglite in tests), vitest + msw, VoiceStudio (transcribe + TTS), OpenAI chat completions (JSON mode). SwiftUI iOS 17+, Apollo iOS 2.x, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-14-therapist-agent-design.md`

## Global Constraints

- Every change is TDD: failing test first (`superpowers:test-driven-development`). Ponytail mode: smallest working change, reuse before writing, stdlib before deps. No new npm or SPM dependencies.
- Backend tests never touch the network (`test/setup.ts` msw errors on unhandled non-localhost requests). Postgres is in-memory pglite running the real migrations from `backend/drizzle/`.
- GraphQL errors use `gqlError(code, message)` from `backend/src/schema/errors.ts`; `extensions.code` must be one of the `ErrorCode` union.
- Session/turn status order: `UPLOADED → TRANSCRIBING → REFRAMING → SYNTHESIZING → COMPLETED | FAILED`. Every transition writes the row then publishes on pubsub.
- Secrets never enter the repo. No new env vars are needed (the OpenAI adapter reuses `OPENAI_API_KEY`, `OPENAI_MODEL`).
- iOS: Views never import Apollo; they use `API` and plain models. Any `UNAUTHENTICATED` error → `AppState.signOut()`. Theme colours only (`Color.forest`, `.sand`, `.surface`, `.muted`, `.clay`), fonts via `Font.display(_:)`, `.card()`, `PrimaryButtonStyle` / `SecondaryButtonStyle` / `RecordButtonStyle`. Never raw hex or `.blue`.
- Every commit message ends with a `Co-Authored-By: Claude <model> <noreply@anthropic.com>` line naming the model that made the commit (the commit blocks below show Fable 5.1 as the example; substitute your own model name).
- Hotline copy is US only for now: call 988, text HOME to 741741.
- Run backend commands from `backend/`, iOS commands from `ios/`.

## Review Focus

1. **LLM wraps JSON in a markdown fence or adds prose.** The agent must still parse it. → Task 2 test "parses fenced JSON".
2. **Crisis keyword present but model returns `crisis: false`.** Final flag must be true. → Task 2 test "keyword floor overrides model".
3. **`sendTurn` while a previous turn is still processing.** Must be rejected with `TURN_IN_PROGRESS`, not queued. → Task 6 test.
4. **`deleteAccount` must remove turn recordings and reply audio from R2.** → Task 6 test "deleteAccount removes turn objects".
5. **Silence recorded in chat (empty transcript).** Turn must FAIL with `EMPTY_TRANSCRIPT` instead of sending an empty message to the agent. → Task 7 test.
6. **Profile refresh fails after a session completed.** Session must stay COMPLETED and the error only logged. → Task 5 test.

---

### Task 1: `LLM` seam and OpenAI adapter

**Files:**
- Create: `backend/src/agent/llm.ts`
- Modify: `backend/src/clients/openai.ts`
- Test: `backend/test/clients/openai.test.ts`

**Interfaces:**
- Produces: `type LLMMessage = { role: 'user' | 'assistant'; content: string }`, `type LLMRequest = { system: string; messages: LLMMessage[]; json?: boolean }`, `type LLM = (req: LLMRequest) => Promise<string>`, `createOpenAILLM(cfg: { apiKey: string; model: string }): LLM`. The existing `createReframer` stays until Task 5 removes it.

- [ ] **Step 1: Write the failing tests**

Append to `backend/test/clients/openai.test.ts`:

```ts
import { createOpenAILLM } from '../../src/clients/openai.js';

describe('createOpenAILLM', () => {
  const llm = createOpenAILLM({ apiKey: 'OK', model: 'gpt-test' });
  it('sends system + messages and returns trimmed content', async () => {
    let body: any; let auth: string | null = null;
    msw.use(http.post(url, async ({ request }) => { body = await request.json(); auth = request.headers.get('authorization');
      return HttpResponse.json({ choices: [{ message: { content: '  hello  ' } }] }); }));
    expect(await llm({ system: 'SYS', messages: [{ role: 'user', content: 'hi' }] })).toBe('hello');
    expect(auth).toBe('Bearer OK');
    expect(body.model).toBe('gpt-test');
    expect(body.messages).toEqual([{ role: 'system', content: 'SYS' }, { role: 'user', content: 'hi' }]);
    expect(body.response_format).toBeUndefined();
  });
  it('requests JSON mode when json is true', async () => {
    let body: any;
    msw.use(http.post(url, async ({ request }) => { body = await request.json(); return HttpResponse.json({ choices: [{ message: { content: '{}' } }] }); }));
    await llm({ system: 'S', messages: [{ role: 'user', content: 'u' }], json: true });
    expect(body.response_format).toEqual({ type: 'json_object' });
  });
  it('throws on non-2xx and on empty content', async () => {
    msw.use(http.post(url, () => new HttpResponse('nope', { status: 500 })));
    await expect(llm({ system: 'S', messages: [] })).rejects.toThrow('OpenAI: 500');
    msw.use(http.post(url, () => HttpResponse.json({ choices: [{ message: { content: '' } }] })));
    await expect(llm({ system: 'S', messages: [] })).rejects.toThrow('OpenAI: empty response');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && npx vitest run test/clients/openai.test.ts`
Expected: FAIL, `createOpenAILLM` is not exported.

- [ ] **Step 3: Create the seam and the adapter**

Create `backend/src/agent/llm.ts`:

```ts
export type LLMMessage = { role: 'user' | 'assistant'; content: string };
export type LLMRequest = { system: string; messages: LLMMessage[]; json?: boolean };
/** Provider seam: one chat completion in, text out. Adapters live in src/clients/. */
export type LLM = (req: LLMRequest) => Promise<string>;
```

Append to `backend/src/clients/openai.ts` (leave `createReframer` in place for now):

```ts
import type { LLM } from '../agent/llm.js';

export function createOpenAILLM(cfg: { apiKey: string; model: string }): LLM {
  return async ({ system, messages, json }) => {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      signal: AbortSignal.timeout(60_000),
      headers: { authorization: `Bearer ${cfg.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        model: cfg.model,
        messages: [{ role: 'system', content: system }, ...messages],
        ...(json ? { response_format: { type: 'json_object' } } : {}),
      }),
    });
    if (!res.ok) throw new Error(`OpenAI: ${res.status}`);
    const data = await res.json() as { choices?: { message?: { content?: string } }[] };
    const text = data.choices?.[0]?.message?.content?.trim();
    if (!text) throw new Error('OpenAI: empty response');
    return text;
  };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && npx vitest run test/clients/openai.test.ts`
Expected: PASS (old `reframer` tests and new `createOpenAILLM` tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/agent/llm.ts backend/src/clients/openai.ts backend/test/clients/openai.test.ts
git commit -m "feat(backend): LLM seam with OpenAI adapter (json mode)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Prompts, crisis floor, context rendering, and the agent

**Files:**
- Create: `backend/src/agent/crisis.ts`, `backend/src/agent/prompts.ts`, `backend/src/agent/context.ts` (render only; DB loading comes in Task 4), `backend/src/agent/agent.ts`
- Test: `backend/test/agent/crisis.test.ts`, `backend/test/agent/agent.test.ts`

**Interfaces:**
- Consumes: `LLM`, `LLMRequest` from Task 1.
- Produces:
  - `hasCrisisLanguage(text: string): boolean`
  - `THERAPIST_SYSTEM`, `REFRAME_INSTRUCTIONS`, `CHAT_INSTRUCTIONS`, `PROFILE_INSTRUCTIONS` (strings)
  - `type ContextTurn = { userText: string; agentText: string }`
  - `type ContextSession = { createdAt: Date; transcript: string; affirmation: string; crisis: boolean; turns: ContextTurn[] }`
  - `type AgentContext = { profile: string | null; recent: ContextSession[] }`
  - `renderContext(ctx: AgentContext): string`
  - `type ReframeResult = { affirmation: string; crisis: boolean }`
  - `type ChatResult = { reply: string; crisis: boolean; closing: boolean }`
  - `type Agent = { reframe(ctx, transcript): Promise<ReframeResult>; chatTurn(ctx, session: { transcript: string; affirmation: string }, prior: ContextTurn[], userText: string): Promise<ChatResult>; updateProfile(ctx, session: ContextSession): Promise<string> }`
  - `createAgent(llm: LLM): Agent`

- [ ] **Step 1: Write the failing crisis test**

Create `backend/test/agent/crisis.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { hasCrisisLanguage } from '../../src/agent/crisis.js';

describe('hasCrisisLanguage', () => {
  it.each([
    'I want to kill myself', 'sometimes I think about suicide', 'I just want to end it all',
    'I have been hurting myself again', 'everyone would be better off without me', 'I want to die',
  ])('flags %s', (t) => expect(hasCrisisLanguage(t)).toBe(true));
  it.each(['I always mess things up', 'this project is killing me', 'I could die of embarrassment'])
    ('does not flag %s', (t) => expect(hasCrisisLanguage(t)).toBe(false));
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/agent/crisis.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement the crisis floor**

Create `backend/src/agent/crisis.ts`:

```ts
// Keyword floor under the model's own judgement: a hit here is always a crisis, whatever the model says.
// Deliberately narrow so "this project is killing me" does not trip it.
export const CRISIS_PATTERN =
  /\b(suicid\w*|kill(ing)? myself|end (it all|my life)|want(ing)? to die|self[- ]?harm\w*|hurt(ing)? myself|cut(ting)? myself|better off without me|better off dead|no reason to (live|go on))\b/i;

export const hasCrisisLanguage = (text: string): boolean => CRISIS_PATTERN.test(text);
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd backend && npx vitest run test/agent/crisis.test.ts`
Expected: PASS.

- [ ] **Step 5: Write the prompts**

Create `backend/src/agent/prompts.ts`:

```ts
export const THERAPIST_SYSTEM = `You are Reframed, a warm, steady companion trained in Cognitive Behavioral Therapy (CBT). You help one person notice negative self-talk, examine it, and find a more balanced, kinder view. Over time you help them see what is going well in their life, not only what is going wrong.

How you work (CBT):
1. Name the thought and the feeling behind it.
2. Spot the thinking pattern: all-or-nothing, catastrophizing, mind-reading, overgeneralizing, "should" statements, labeling, discounting the positive, personalizing, emotional reasoning.
3. Examine the evidence for and against the thought, gently.
4. Build a balanced alternative the person can actually believe.
5. Notice strengths, effort, and small wins; say them plainly.

Tone:
- Warm, plain, unhurried. Short sentences. One question at a time.
- Realistic and kind, never saccharine. No toxic positivity, no exclamation marks, no clinical jargon.
- Use the person's own words and subject matter. Do not change what they are talking about.
- Use your notes about the person (profile and recent sessions) to notice patterns and progress, and say so when it helps. Never recite the notes back to them.
- You are not a doctor. Do not diagnose, prescribe, or promise outcomes.

Safety:
- If the person mentions suicide, wanting to die, self-harm, harming others, or abuse, stop the CBT work. Respond with care, tell them they deserve support right now, and encourage them to reach a crisis line or someone they trust. Keep it brief and human, and set "crisis": true where the output has that field.

When the instructions ask for JSON, reply with a single JSON object in exactly that shape and nothing else.`;

export const REFRAME_INSTRUCTIONS = `Task: rewrite the person's new thought as a first-person affirmation they could say to themselves.
- One or two sentences, under 40 words, present tense, "I" statements.
- Keep their subject matter. Realistic and kind. No exclamation marks.
- If this thought repeats a pattern from your notes, let the affirmation quietly answer that pattern.
- If the thought contains crisis language, do not write an affirmation. Instead write two or three caring sentences acknowledging what they said, telling them they deserve support right now, and encouraging them to contact a crisis line or someone they trust.
Reply with JSON: {"affirmation": string, "crisis": boolean}`;

export const CHAT_INSTRUCTIONS = `Task: continue a short conversation that helps the person work through the thought below using CBT. Each reply is read aloud to them, so write for the ear: two to four short sentences, at most one question.
- Move through the steps across the conversation: name the thought and feeling, spot the pattern, weigh the evidence, build a balanced thought, notice a strength or small win.
- When a balanced thought has been reached and the person seems settled, or they say they are done, close warmly in one or two sentences and set "closing": true. Otherwise set "closing": false.
- If the latest message contains crisis language, follow the safety rules, set "crisis": true and "closing": false.
Reply with JSON: {"reply": string, "crisis": boolean, "closing": boolean}`;

export const PROFILE_INSTRUCTIONS = `Task: update your private notes about this person after the session below. Write the complete new notes, replacing the old ones.
- At most 200 words, plain text, no headings, no JSON, no quotation of the person at length.
- Cover: recurring themes and situations; thinking patterns you have noticed; what has helped them; signs of progress; anything to be gentle about.
- Keep what is still true from the old notes, drop what is stale, add what is new.
- If crisis thoughts came up, record only "has mentioned crisis thoughts; approach with extra care", nothing more specific.`;
```

- [ ] **Step 6: Write the failing agent tests**

Create `backend/test/agent/agent.test.ts`:

```ts
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
```

- [ ] **Step 7: Run it to verify it fails**

Run: `cd backend && npx vitest run test/agent/agent.test.ts`
Expected: FAIL, modules not found.

- [ ] **Step 8: Implement context rendering and the agent**

Create `backend/src/agent/context.ts` (the DB loaders are added in Task 4):

```ts
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
```

Create `backend/src/agent/agent.ts`:

```ts
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
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd backend && npx vitest run test/agent`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add backend/src/agent backend/test/agent
git commit -m "feat(backend): therapist agent — prompts, crisis floor, context rendering

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Schema and migration — profile, crisis, turns

**Files:**
- Modify: `backend/src/db/schema.ts`, `backend/src/deps.ts` (pubsub type only)
- Create: `backend/drizzle/0001_therapist_agent.sql` (generated), `backend/test/db/schema.test.ts`

**Interfaces:**
- Produces: `users.profile`, `users.profileUpdatedAt`, `sessions.crisis`, table `turns` with `TurnRow = typeof turns.$inferSelect`; `SessionPubSub` gains channel `turn: [id: string, payload: TurnRow]`.

- [ ] **Step 1: Write the failing test**

Create `backend/test/db/schema.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, turns, users } from '../../src/db/schema.js';
import { makeTestDb } from '../helpers/db.js';

describe('schema', () => {
  it('has profile on users, crisis on sessions, and turns cascading from sessions', async () => {
    const db = await makeTestDb();
    const [u] = await db.insert(users).values({ appleSub: 'a', profile: 'notes', profileUpdatedAt: new Date() }).returning();
    expect(u.profile).toBe('notes');
    const [s] = await db.insert(sessions).values({ userId: u.id, recordingKey: 'r' }).returning();
    expect(s.crisis).toBe(false);
    const [t] = await db.insert(turns).values({ sessionId: s.id, recordingKey: 'turns/x.m4a' }).returning();
    expect(t.status).toBe('UPLOADED');
    expect(t.crisis).toBe(false);
    expect(t.closing).toBe(false);
    await db.delete(sessions).where(eq(sessions.id, s.id));
    expect(await db.select().from(turns)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/db/schema.test.ts`
Expected: FAIL, `turns` is not exported.

- [ ] **Step 3: Extend the Drizzle schema**

In `backend/src/db/schema.ts`, change the import to `import { boolean, pgEnum, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';`, add to `users`:

```ts
  profile: text('profile'),
  profileUpdatedAt: timestamp('profile_updated_at', { withTimezone: true }),
```

add to `sessions` after `error`:

```ts
  crisis: boolean('crisis').notNull().default(false),
```

and append:

```ts
export const turns = pgTable('turns', {
  id: uuid('id').primaryKey().defaultRandom(),
  sessionId: uuid('session_id').notNull().references(() => sessions.id, { onDelete: 'cascade' }),
  status: sessionStatus('status').notNull().default('UPLOADED'),
  recordingKey: text('recording_key').notNull(),
  userText: text('user_text'),
  agentText: text('agent_text'),
  audioKey: text('audio_key'),
  crisis: boolean('crisis').notNull().default(false),
  closing: boolean('closing').notNull().default(false),
  error: text('error'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

export type TurnRow = typeof turns.$inferSelect;
```

- [ ] **Step 4: Generate the migration**

Run: `cd backend && npx drizzle-kit generate --name therapist_agent`
Expected: writes `drizzle/0001_therapist_agent.sql` and updates `drizzle/meta/`. Open the SQL and confirm it contains `ALTER TABLE "users" ADD COLUMN "profile"`, `ALTER TABLE "sessions" ADD COLUMN "crisis"`, and `CREATE TABLE "turns"`.

- [ ] **Step 5: Extend the pubsub type**

In `backend/src/deps.ts` change the `SessionRow` import to `import type { SessionRow, TurnRow } from './db/schema.js';` and:

```ts
export type SessionPubSub = PubSub<{ session: [id: string, payload: SessionRow]; turn: [id: string, payload: TurnRow] }>;
```

- [ ] **Step 6: Run the tests**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: all PASS, typecheck clean.

- [ ] **Step 7: Commit**

```bash
git add backend/src/db/schema.ts backend/src/deps.ts backend/drizzle backend/test/db/schema.test.ts
git commit -m "feat(backend): schema — user profile, session crisis flag, turns table

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Context loaders

**Files:**
- Modify: `backend/src/agent/context.ts`
- Test: `backend/test/agent/context.test.ts`

**Interfaces:**
- Consumes: `turns`, `sessions`, `users` from Task 3; `Db` from `src/db/client.ts`.
- Produces: `loadContext(db: Db, userId: string, opts?: { limit?: number; exclude?: string }): Promise<AgentContext>`, `loadContextSession(db: Db, sessionId: string): Promise<ContextSession | null>`.

- [ ] **Step 1: Write the failing test**

Create `backend/test/agent/context.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { loadContext, loadContextSession } from '../../src/agent/context.js';
import { sessions, turns, users } from '../../src/db/schema.js';
import { makeTestDb } from '../helpers/db.js';

async function seed() {
  const db = await makeTestDb();
  const [u] = await db.insert(users).values({ appleSub: 'a', profile: 'notes' }).returning();
  const t0 = +new Date('2026-01-01T00:00:00Z');
  const ids: string[] = [];
  for (let i = 0; i < 7; i++) {
    const [s] = await db.insert(sessions).values({ userId: u.id, recordingKey: `r${i}`, status: 'COMPLETED', transcript: `thought ${i}`, reframedText: `aff ${i}`, createdAt: new Date(t0 + i * 1000) }).returning();
    ids.push(s.id);
  }
  await db.insert(sessions).values({ userId: u.id, recordingKey: 'pending', status: 'REFRAMING', transcript: 'in flight', createdAt: new Date(t0 + 99_000) });
  await db.insert(turns).values({ sessionId: ids[6], recordingKey: 'k', status: 'COMPLETED', userText: 'u1', agentText: 'a1', createdAt: new Date(t0 + 1) });
  await db.insert(turns).values({ sessionId: ids[6], recordingKey: 'k', status: 'FAILED', userText: 'ignored', createdAt: new Date(t0 + 2) });
  await db.insert(turns).values({ sessionId: ids[6], recordingKey: 'k', status: 'COMPLETED', userText: 'u2', agentText: 'a2', createdAt: new Date(t0 + 3) });
  return { db, u, ids };
}

describe('loadContext', () => {
  it('returns profile and the last 5 completed sessions oldest first, with completed turns in order', async () => {
    const { db, u } = await seed();
    const ctx = await loadContext(db, u.id);
    expect(ctx.profile).toBe('notes');
    expect(ctx.recent.map((s) => s.transcript)).toEqual(['thought 2', 'thought 3', 'thought 4', 'thought 5', 'thought 6']);
    expect(ctx.recent[4].turns).toEqual([{ userText: 'u1', agentText: 'a1' }, { userText: 'u2', agentText: 'a2' }]);
    expect(ctx.recent[0].turns).toEqual([]);
  });
  it('can exclude the current session', async () => {
    const { db, u, ids } = await seed();
    const ctx = await loadContext(db, u.id, { exclude: ids[6] });
    expect(ctx.recent.map((s) => s.transcript)).toEqual(['thought 1', 'thought 2', 'thought 3', 'thought 4', 'thought 5']);
  });
  it('is empty for a new user', async () => {
    const db = await makeTestDb();
    const [u] = await db.insert(users).values({ appleSub: 'new' }).returning();
    expect(await loadContext(db, u.id)).toEqual({ profile: null, recent: [] });
  });
});

describe('loadContextSession', () => {
  it('returns the session with its completed turns, null when missing', async () => {
    const { db, ids } = await seed();
    const s = await loadContextSession(db, ids[6]);
    expect(s?.transcript).toBe('thought 6');
    expect(s?.affirmation).toBe('aff 6');
    expect(s?.turns.map((t) => t.userText)).toEqual(['u1', 'u2']);
    expect(await loadContextSession(db, '00000000-0000-0000-0000-000000000000')).toBeNull();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run test/agent/context.test.ts`
Expected: FAIL, `loadContext` is not exported.

- [ ] **Step 3: Implement the loaders**

Append to `backend/src/agent/context.ts`:

```ts
import { and, asc, desc, eq, inArray, ne } from 'drizzle-orm';
import type { Db } from '../db/client.js';
import { sessions, turns, users, type SessionRow } from '../db/schema.js';

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
```

Move these imports to the top of the file (ES modules hoist them, but keep the file tidy).

- [ ] **Step 4: Run the tests**

Run: `cd backend && npx vitest run test/agent && npm run typecheck`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/agent/context.ts backend/test/agent/context.test.ts
git commit -m "feat(backend): load agent context (profile + recent sessions with turns)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Reframe pipeline on the agent, profile refresh, wiring

**Files:**
- Create: `backend/src/pipeline/profile.ts`
- Modify: `backend/src/deps.ts`, `backend/src/pipeline/run.ts`, `backend/src/server.ts`, `backend/test/helpers/app.ts`, `backend/test/pipeline/run.test.ts`
- Delete: `backend/src/pipeline/reframe-prompt.ts`, the `createReframer` function and its `reframer` describe block in `backend/src/clients/openai.ts` / `backend/test/clients/openai.test.ts`

**Interfaces:**
- Consumes: `Agent`, `createAgent`, `createOpenAILLM`, `loadContext`, `loadContextSession`.
- Produces: `Deps.agent: Agent` (replaces `Deps.reframe`); `refreshProfile(deps: Deps, userId: string, sessionId: string): Promise<void>`; test fakes `fakes.agentFail: boolean`, `fakes.crisis: boolean`, `fakes.closing: boolean`, `fakes.agentCalls: { reframe: AgentContext[]; chat: { prior: ContextTurn[]; userText: string }[]; profile: ContextSession[] }`.

- [ ] **Step 1: Replace the fake in the test helper**

In `backend/test/helpers/app.ts` add imports `import type { AgentContext, ContextSession, ContextTurn } from '../../src/agent/context.js';`. Replace `const fakes = { r2, voice, reframeFail: false, r2DeleteFail: false };` with:

```ts
  const agentCalls = { reframe: [] as AgentContext[], chat: [] as { prior: ContextTurn[]; userText: string }[], profile: [] as ContextSession[] };
  const fakes = { r2, voice, agentFail: false, profileFail: false, crisis: false, closing: false, agentCalls, r2DeleteFail: false };
```

and replace the `reframe:` entry in `deps` with:

```ts
    agent: {
      reframe: async (ctx, t) => { agentCalls.reframe.push(ctx); if (fakes.agentFail) throw new Error('llm 500'); return { affirmation: `Reframed: ${t}`, crisis: fakes.crisis }; },
      chatTurn: async (_ctx, _s, prior, userText) => { agentCalls.chat.push({ prior, userText }); if (fakes.agentFail) throw new Error('llm 500'); return { reply: `Reply: ${userText}`, crisis: fakes.crisis, closing: fakes.closing }; },
      updateProfile: async (_ctx, s) => { agentCalls.profile.push(s); if (fakes.profileFail) throw new Error('llm 500'); return `Notes after: ${s.transcript}`; },
    },
```

- [ ] **Step 2: Update and extend the pipeline tests**

In `backend/test/pipeline/run.test.ts`: replace `fakes.reframeFail = true;` with `fakes.agentFail = true;` and `expect(row.error).toBe('openai 500');` with `expect(row.error).toBe('llm 500');`. Add inside `describe('runPipeline', …)`:

```ts
  it('passes the user context to the agent and stores the crisis flag', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    fakes.crisis = true;
    const s = await seed(deps);
    await deps.db.update(users).set({ profile: 'old notes' }).where(eq(users.id, s.userId));
    await runPipeline(deps, s.id);
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('COMPLETED');
    expect(row.crisis).toBe(true);
    expect(fakes.agentCalls.reframe[0].profile).toBe('old notes');
  });
  it('refreshes the profile after completing', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    const s = await seed(deps);
    await runPipeline(deps, s.id);
    const [u] = await deps.db.select().from(users).where(eq(users.id, s.userId));
    expect(u.profile).toBe('Notes after: I always mess things up');
    expect(u.profileUpdatedAt).toBeInstanceOf(Date);
    expect(fakes.agentCalls.profile[0].affirmation).toBe('Reframed: I always mess things up');
  });
  it('keeps the session COMPLETED when the profile refresh fails', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('recordings/x.m4a', new Uint8Array([1]));
    fakes.profileFail = true;
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const s = await seed(deps);
    await runPipeline(deps, s.id);
    const [row] = await deps.db.select().from(sessions).where(eq(sessions.id, s.id));
    expect(row.status).toBe('COMPLETED');
    const [u] = await deps.db.select().from(users).where(eq(users.id, s.userId));
    expect(u.profile).toBeNull();
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd backend && npx vitest run test/pipeline/run.test.ts`
Expected: FAIL (type errors on `deps.agent` / `fakes.agentFail`, and the new tests).

- [ ] **Step 4: Change `Deps`, add `refreshProfile`, update the pipeline**

In `backend/src/deps.ts` add `import type { Agent } from './agent/agent.js';` and replace `reframe: (transcript: string) => Promise<string>;` with `agent: Agent;`.

Create `backend/src/pipeline/profile.ts`:

```ts
import { eq } from 'drizzle-orm';
import { loadContext, loadContextSession } from '../agent/context.js';
import { users } from '../db/schema.js';
import type { Deps } from '../deps.js';

// ponytail: last-writer-wins; turns within a session are sequential so this is safe. Add a per-user lock if concurrent sessions appear.
export async function refreshProfile(deps: Deps, userId: string, sessionId: string): Promise<void> {
  const [ctx, session] = await Promise.all([loadContext(deps.db, userId, { exclude: sessionId }), loadContextSession(deps.db, sessionId)]);
  if (!session) return;
  const profile = await deps.agent.updateProfile(ctx, session);
  await deps.db.update(users).set({ profile, profileUpdatedAt: new Date() }).where(eq(users.id, userId));
}

export const refreshProfileQuietly = (deps: Deps, userId: string, sessionId: string) =>
  refreshProfile(deps, userId, sessionId).catch((e) => console.error('profile refresh failed', sessionId, e));
```

In `backend/src/pipeline/run.ts` add imports `import { loadContext } from '../agent/context.js';` and `import { refreshProfileQuietly } from './profile.js';`, then replace the reframe block and the tail of the happy path:

```ts
      let reframedText = s.reframedText;
      let crisis = s.crisis;
      if (!reframedText) {
        await transition(deps, sessionId, { status: 'REFRAMING', transcript });
        const ctx = await loadContext(deps.db, s.userId);
        const r = await deps.agent.reframe(ctx, transcript);
        reframedText = r.affirmation;
        crisis = r.crisis;
      }
      await transition(deps, sessionId, { status: 'SYNTHESIZING', transcript, reframedText, crisis });
      const [user] = await deps.db.select().from(users).where(eq(users.id, s.userId));
      if (!user?.voiceProfileId) throw new Error('VOICE_NOT_ENROLLED');
      const mp3 = await deps.voice.synthesize({ text: reframedText, voice: user.voiceProfileId });
      const audioKey = `affirmations/${sessionId}.mp3`;
      await deps.r2.put(audioKey, mp3, 'audio/mpeg');
      await transition(deps, sessionId, { status: 'COMPLETED', audioKey });
      await refreshProfileQuietly(deps, s.userId, sessionId);
```

- [ ] **Step 5: Wire the server and remove the old reframer**

In `backend/src/server.ts` replace `import { createReframer } from './clients/openai.js';` with `import { createAgent } from './agent/agent.js';` and `import { createOpenAILLM } from './clients/openai.js';`, and replace the `reframe:` line in `depsFromEnv` with:

```ts
    agent: createAgent(createOpenAILLM({ apiKey: env.OPENAI_API_KEY, model: env.OPENAI_MODEL })),
```

Delete `backend/src/pipeline/reframe-prompt.ts`. In `backend/src/clients/openai.ts` delete `createReframer` and the `REFRAME_SYSTEM_PROMPT` import. In `backend/test/clients/openai.test.ts` delete the `reframer` describe block, the `createReframer` import, the `REFRAME_SYSTEM_PROMPT` import, and the `const reframe = …` line.

- [ ] **Step 6: Run everything**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: all PASS, typecheck clean (`grep -rn "reframe-prompt\|createReframer\|deps.reframe" src test` returns nothing).

- [ ] **Step 7: Commit**

```bash
git add -A backend/src backend/test
git commit -m "feat(backend): reframe through the therapist agent; refresh user profile after each session

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: GraphQL — `Turn`, `sendTurn`, `Session.turns`/`crisis`, `User.profile`, deleteAccount cleanup

**Files:**
- Create: `backend/src/schema/turn.ts`, `backend/test/schema/turn.test.ts`
- Modify: `backend/src/schema/errors.ts`, `backend/src/schema/session.ts`, `backend/src/schema/user.ts`, `backend/src/schema/voice.ts`, `backend/src/schema/index.ts`, `backend/src/deps.ts`, `backend/test/helpers/app.ts`, `backend/test/schema/voice.test.ts`

**Interfaces:**
- Consumes: `turns`, `TurnRow`, `loadOwnedSession`, `SessionType`, `gqlError`, `requireUser`, `bytesOf`.
- Produces: `TurnType`, `loadOwnedTurn(ctx, userId, id): Promise<TurnRow | null>`, `Deps.startTurn: (turnId: string) => void`, error codes `SESSION_NOT_READY`, `TURN_IN_PROGRESS`; test helper `startedTurns: string[]`.

- [ ] **Step 1: Write the failing tests**

Create `backend/test/schema/turn.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { sessions, turns } from '../../src/db/schema.js';
import { gql, makeTestDeps, signIn } from '../helpers/app.js';
import { gqlUpload } from '../helpers/upload.js';

const ENROLL = 'mutation($s:File!,$t:String!){ enrollVoice(sample:$s, referenceText:$t){ id } }';
const SEND = 'mutation($id:ID!,$r:File!){ sendTurn(sessionId:$id, recording:$r){ id status userText agentText audioUrl crisis closing error createdAt } }';
const rec = { field: 'r', bytes: new Uint8Array([7]), name: 'turn.m4a', type: 'audio/mp4' };
const sample = { field: 's', bytes: new Uint8Array([5]), name: 'v.m4a', type: 'audio/mp4' };

async function withCompletedSession() {
  const t = await makeTestDeps();
  const { token, user } = await signIn(t.yoga, t.apple);
  await gqlUpload(t.yoga, { query: ENROLL, variables: { t: 'x' }, file: sample }, token);
  const [session] = await t.deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r', status: 'COMPLETED', transcript: 'thought', reframedText: 'aff', audioKey: 'affirmations/a.mp3' }).returning();
  return { ...t, token, user, session };
}

describe('sendTurn', () => {
  it('stores the recording, returns UPLOADED, starts the turn pipeline', async () => {
    const { yoga, token, fakes, startedTurns, session } = await withCompletedSession();
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors).toBeUndefined();
    const turn = r.data.sendTurn;
    expect(turn.status).toBe('UPLOADED');
    expect(turn.crisis).toBe(false);
    expect(turn.closing).toBe(false);
    expect(fakes.r2.get(`turns/${turn.id}.m4a`)).toEqual(rec.bytes);
    expect(startedTurns).toEqual([turn.id]);
  });
  it('rejects a session that is not COMPLETED', async () => {
    const { yoga, token, deps, session, fakes } = await withCompletedSession();
    await deps.db.update(sessions).set({ status: 'REFRAMING' }).where(eq(sessions.id, session.id));
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('SESSION_NOT_READY');
    expect([...fakes.r2.keys()].some((k) => k.startsWith('turns/'))).toBe(false);
  });
  it('rejects while a previous turn is still in flight', async () => {
    const { yoga, token, deps, session } = await withCompletedSession();
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'TRANSCRIBING' });
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('TURN_IN_PROGRESS');
  });
  it('allows a new turn after a FAILED one', async () => {
    const { yoga, token, deps, session } = await withCompletedSession();
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'FAILED' });
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, token);
    expect(r.errors).toBeUndefined();
  });
  it('is NOT_FOUND for someone else’s session', async () => {
    const { yoga, apple, session } = await withCompletedSession();
    const other = await signIn(yoga, apple, 'other');
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'x' }, file: sample }, other.token);
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: session.id }, file: rec }, other.token);
    expect(r.errors?.[0].extensions?.code).toBe('NOT_FOUND');
  });
  it('requires an enrolled voice', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    const [s] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r', status: 'COMPLETED' }).returning();
    const r = await gqlUpload(yoga, { query: SEND, variables: { id: s.id }, file: rec }, token);
    expect(r.errors?.[0].extensions?.code).toBe('VOICE_NOT_ENROLLED');
  });
});

describe('Session.turns, Session.crisis, User.profile', () => {
  it('exposes turns oldest first with presigned audio, crisis, and profile', async () => {
    const { yoga, token, deps, session, user } = await withCompletedSession();
    await deps.db.update(sessions).set({ crisis: true }).where(eq(sessions.id, session.id));
    await deps.db.update(users).set({ profile: 'remembers you' }).where(eq(users.id, user.id));
    const t0 = new Date('2026-01-01T00:00:00Z');
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'COMPLETED', userText: 'u2', agentText: 'a2', audioKey: 'turns/b.mp3', createdAt: new Date(+t0 + 1000) });
    await deps.db.insert(turns).values({ sessionId: session.id, recordingKey: 'k', status: 'COMPLETED', userText: 'u1', agentText: 'a1', audioKey: 'turns/a.mp3', createdAt: t0 });
    const r = await gql(yoga, { query: `{ me { profile } session(id:"${session.id}"){ crisis turns { userText agentText audioUrl } } }` }, token);
    expect(r.errors).toBeUndefined();
    expect(r.data.me.profile).toBe('remembers you');
    expect(r.data.session.crisis).toBe(true);
    expect(r.data.session.turns).toEqual([
      { userText: 'u1', agentText: 'a1', audioUrl: 'https://r2.test/turns/a.mp3?signed' },
      { userText: 'u2', agentText: 'a2', audioUrl: 'https://r2.test/turns/b.mp3?signed' },
    ]);
  });
});
```

Add `import { eq } from 'drizzle-orm';` and `users` to the schema import at the top of that file.

In `backend/test/schema/voice.test.ts` add inside the existing `describe('deleteAccount', …)` block (the file already imports `gql`, `makeTestDeps`, `signIn`, `gqlUpload`, `sessions`, `users`, `ENROLL` and `sample`; extend the schema import to `{ sessions, turns, users }`):

```ts
  it('removes turn recordings and reply audio from R2', async () => {
    const { yoga, apple, deps, fakes } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample }, token);
    const [s] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'recordings/s.m4a', status: 'COMPLETED' }).returning();
    await deps.db.insert(turns).values({ sessionId: s.id, recordingKey: 'turns/t.m4a', audioKey: 'turns/t.mp3', status: 'COMPLETED' });
    for (const k of ['recordings/s.m4a', 'turns/t.m4a', 'turns/t.mp3']) fakes.r2.set(k, new Uint8Array([1]));
    const r = await gql(yoga, { query: 'mutation{ deleteAccount }' }, token);
    expect(r.data.deleteAccount).toBe(true);
    expect(fakes.r2.size).toBe(0);
    expect(await deps.db.select().from(turns)).toHaveLength(0);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd backend && npx vitest run test/schema/turn.test.ts test/schema/voice.test.ts`
Expected: FAIL, `sendTurn` unknown field; `startedTurns` undefined; R2 still has turn keys.

- [ ] **Step 3: Add the dep, error codes, and the resolvers**

`backend/src/deps.ts`: add `startTurn: (turnId: string) => void;` after `startPipeline`.

`backend/test/helpers/app.ts`: add `const startedTurns: string[] = [];`, add `startTurn: (id) => { startedTurns.push(id); },` to `deps`, and return `startedTurns` alongside `started`.

`backend/src/schema/errors.ts`: `export type ErrorCode = 'UNAUTHENTICATED' | 'INVALID_APPLE_TOKEN' | 'VOICE_NOT_ENROLLED' | 'NOT_FOUND' | 'SESSION_NOT_READY' | 'TURN_IN_PROGRESS';`

`backend/src/schema/session.ts`: add `crisis: t.exposeBoolean('crisis'),` to `SessionType` fields.

`backend/src/schema/user.ts`: add `profile: t.exposeString('profile', { nullable: true }),` to `UserType` fields.

Create `backend/src/schema/turn.ts`:

```ts
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
```

In `backend/src/schema/session.ts` export the enum: change `const SessionStatusEnum = …` to `export const SessionStatusEnum = …`.

`backend/src/schema/index.ts`: add `import './turn.js';` after `./session.js`.

`backend/src/schema/voice.ts` (`deleteAccount`): import `turns` and add after the sessions loop:

```ts
    for (const t of await db.select({ recordingKey: turns.recordingKey, audioKey: turns.audioKey }).from(turns)
      .innerJoin(sessions, eq(turns.sessionId, sessions.id)).where(eq(sessions.userId, userId))) keys.push(t.recordingKey, t.audioKey);
```

- [ ] **Step 4: Run the tests**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A backend/src backend/test
git commit -m "feat(backend): Turn type, sendTurn mutation, Session.turns/crisis, User.profile, turn cleanup on delete

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Turn pipeline, sweeper, and server wiring

**Files:**
- Create: `backend/src/pipeline/turn.ts`, `backend/test/pipeline/turn.test.ts`
- Modify: `backend/src/server.ts`

**Interfaces:**
- Consumes: `turns`, `sessions`, `users`, `loadContext`, `refreshProfileQuietly`, `Deps.agent`, `Deps.pubsub` channel `turn`.
- Produces: `runTurn(deps, turnId): Promise<void>`, `sweepStuckTurns(deps, olderThanMs?): Promise<string[]>`, `createTurnStarter(deps): (id: string) => void`.

- [ ] **Step 1: Write the failing tests**

Create `backend/test/pipeline/turn.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, turns, users } from '../../src/db/schema.js';
import { runTurn, sweepStuckTurns } from '../../src/pipeline/turn.js';
import { makeTestDeps } from '../helpers/app.js';

type Deps = Awaited<ReturnType<typeof makeTestDeps>>['deps'];

async function seed(deps: Deps, over: Partial<typeof turns.$inferInsert> = {}) {
  const [u] = await deps.db.insert(users).values({ appleSub: `s-${Math.random()}`, voiceProfileId: 'vp1' }).returning();
  const [s] = await deps.db.insert(sessions).values({ userId: u.id, recordingKey: 'r', status: 'COMPLETED', transcript: 'I always mess up', reframedText: 'I am learning', audioKey: 'a' }).returning();
  const [t] = await deps.db.insert(turns).values({ sessionId: s.id, recordingKey: 'turns/x.m4a', ...over }).returning();
  return { u, s, t };
}
const statusesSeen = (deps: Deps, id: string) => {
  const seen: string[] = [];
  const it = deps.pubsub.subscribe('turn', id);
  (async () => { for await (const r of it) seen.push(r.status); })();
  return seen;
};
const by = async (deps: Deps, id: string) => (await deps.db.select().from(turns).where(eq(turns.id, id)))[0];

describe('runTurn', () => {
  it('transcribes, asks the agent with prior turns, synthesizes, completes, refreshes profile', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.voice.transcript = 'Everyone noticed';
    const { s, t, u } = await seed(deps);
    await deps.db.insert(turns).values({ sessionId: s.id, recordingKey: 'k', status: 'COMPLETED', userText: 'earlier', agentText: 'reply earlier', createdAt: new Date(+t.createdAt - 1000) });
    const seen = statusesSeen(deps, t.id);
    await runTurn(deps, t.id);
    const row = await by(deps, t.id);
    expect(row.status).toBe('COMPLETED');
    expect(row.userText).toBe('Everyone noticed');
    expect(row.agentText).toBe('Reply: Everyone noticed');
    expect(row.audioKey).toBe(`turns/${t.id}.mp3`);
    expect(fakes.r2.get(row.audioKey!)).toEqual(fakes.voice.synthesized);
    expect(fakes.voice.lastSynthesize).toEqual({ text: 'Reply: Everyone noticed', voice: 'vp1' });
    expect(fakes.agentCalls.chat[0]).toEqual({ prior: [{ userText: 'earlier', agentText: 'reply earlier' }], userText: 'Everyone noticed' });
    expect((await deps.db.select().from(users).where(eq(users.id, u.id)))[0].profile).toBe('Notes after: I always mess up');
    await new Promise((r) => setTimeout(r, 0));
    expect(seen).toEqual(['TRANSCRIBING', 'REFRAMING', 'SYNTHESIZING', 'COMPLETED']);
  });
  it('stores crisis and closing from the agent', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.crisis = true; fakes.closing = true;
    const { t } = await seed(deps);
    await runTurn(deps, t.id);
    const row = await by(deps, t.id);
    expect(row.crisis).toBe(true);
    expect(row.closing).toBe(true);
  });
  it('fails with EMPTY_TRANSCRIPT on silence', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.voice.transcript = '   ';
    const { t } = await seed(deps);
    await runTurn(deps, t.id);
    const row = await by(deps, t.id);
    expect(row.status).toBe('FAILED');
    expect(row.error).toBe('EMPTY_TRANSCRIPT');
    expect(fakes.agentCalls.chat).toEqual([]);
  });
  it('marks FAILED when the agent throws, without throwing', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    fakes.agentFail = true;
    const { t } = await seed(deps);
    const seen = statusesSeen(deps, t.id);
    await expect(runTurn(deps, t.id)).resolves.toBeUndefined();
    const row = await by(deps, t.id);
    expect(row.status).toBe('FAILED');
    expect(row.error).toBe('llm 500');
    await new Promise((r) => setTimeout(r, 0));
    expect(seen).toEqual(['TRANSCRIBING', 'REFRAMING', 'FAILED']);
  });
  it('resumes from the first missing stage', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.voice.fail = 'transcribe';
    const { t } = await seed(deps, { status: 'REFRAMING', userText: 'already here' });
    await runTurn(deps, t.id);
    expect((await by(deps, t.id)).agentText).toBe('Reply: already here');
  });
  it('is a no-op for terminal turns and never rejects when the db is down', async () => {
    const { deps, fakes } = await makeTestDeps();
    const { t } = await seed(deps, { status: 'COMPLETED', userText: 'u', agentText: 'a', audioKey: 'k' });
    await runTurn(deps, t.id);
    expect(fakes.agentCalls.chat).toEqual([]);
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    await expect(runTurn({ ...deps, db: { select() { throw new Error('db down'); } } as any }, 'x')).resolves.toBeUndefined();
    spy.mockRestore();
  });
});

describe('sweepStuckTurns', () => {
  it('re-runs only non-terminal turns older than the threshold', async () => {
    const { deps, fakes } = await makeTestDeps();
    fakes.r2.set('turns/x.m4a', new Uint8Array([1]));
    const old = new Date(Date.now() - 10 * 60_000);
    const stuck = await seed(deps, { status: 'TRANSCRIBING', updatedAt: old });
    const fresh = await seed(deps, { status: 'TRANSCRIBING' });
    const done = await seed(deps, { status: 'COMPLETED', updatedAt: old });
    expect(await sweepStuckTurns(deps)).toEqual([stuck.t.id]);
    expect((await by(deps, stuck.t.id)).status).toBe('COMPLETED');
    expect((await by(deps, fresh.t.id)).status).toBe('TRANSCRIBING');
    expect((await by(deps, done.t.id)).status).toBe('COMPLETED');
  });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd backend && npx vitest run test/pipeline/turn.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement the turn pipeline**

Create `backend/src/pipeline/turn.ts`:

```ts
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
```

- [ ] **Step 4: Wire the server**

In `backend/src/server.ts`: import `{ createTurnStarter, sweepStuckTurns } from './pipeline/turn.js'`; in `depsFromEnv` change the two lines after `base` to:

```ts
  const deps = { ...base, startPipeline: () => {}, startTurn: () => {} } as Deps;
  deps.startPipeline = createPipelineStarter(deps);
  deps.startTurn = createTurnStarter(deps);
```

and extend the boot block so both sweepers run at boot and on the interval:

```ts
  const sweep = () => Promise.all([sweepStuckSessions(deps), sweepStuckTurns(deps)])
    .then(([s, t]) => { if (s.length) console.log('resumed sessions', s); if (t.length) console.log('resumed turns', t); })
    .catch((e) => console.error('sweep failed', e));
  sweep();
  setInterval(sweep, 120_000).unref();
```

- [ ] **Step 5: Run everything**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src/pipeline/turn.ts backend/src/server.ts backend/test/pipeline/turn.test.ts
git commit -m "feat(backend): turn pipeline — transcribe, agent chat turn, synthesize in the user's voice; sweeper

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: `turnUpdated` subscription

**Files:**
- Modify: `backend/src/schema/subscription.ts`, `backend/test/schema/subscription.test.ts`

**Interfaces:**
- Consumes: `TurnType`, `loadOwnedTurn` from Task 6; pubsub channel `turn`.
- Produces: `subscription turnUpdated(id: ID!): Turn!` with the same snapshot-then-stream semantics as `sessionUpdated`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/test/schema/subscription.test.ts` (reuse the file's `openSse` helper):

```ts
import { turns } from '../../src/db/schema.js';

const TSUB = (id: string) => `subscription { turnUpdated(id:"${id}") { id status agentText } }`;
const tev = (id: string, status: string, agentText: string | null = null) => ({ data: { turnUpdated: { id, status, agentText } } });

async function setupTurn() {
  const { yoga, apple, deps } = await makeTestDeps();
  const { token, user } = await signIn(yoga, apple);
  const [s] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r', status: 'COMPLETED' }).returning();
  const [row] = await deps.db.insert(turns).values({ sessionId: s.id, recordingKey: 'k' }).returning();
  const update = async (set: Partial<typeof turns.$inferInsert>) => {
    const [u] = await deps.db.update(turns).set(set).where(eq(turns.id, row.id)).returning();
    deps.pubsub.publish('turn', row.id, u);
  };
  return { yoga, apple, deps, token, row, update };
}

describe('turnUpdated', () => {
  it('sends the snapshot, streams updates, ends on terminal', async () => {
    const { yoga, token, row, update } = await setupTurn();
    const sse = await openSse(yoga, TSUB(row.id), token);
    expect(await sse.next()).toEqual(tev(row.id, 'UPLOADED'));
    await update({ status: 'REFRAMING' });
    expect(await sse.next()).toEqual(tev(row.id, 'REFRAMING'));
    await update({ status: 'COMPLETED', agentText: 'done' });
    expect(await sse.next()).toEqual(tev(row.id, 'COMPLETED', 'done'));
    expect(await sse.next()).toBeNull();
  });
  it('errors NOT_FOUND for someone else’s turn', async () => {
    const { yoga, apple, row } = await setupTurn();
    const other = await signIn(yoga, apple, 'other');
    const sse = await openSse(yoga, TSUB(row.id), other.token);
    expect((await sse.next()).errors[0].extensions.code).toBe('NOT_FOUND');
  });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd backend && npx vitest run test/schema/subscription.test.ts`
Expected: FAIL, `turnUpdated` unknown field.

- [ ] **Step 3: Implement**

In `backend/src/schema/subscription.ts` add `import { TurnType, loadOwnedTurn } from './turn.js';` and append:

```ts
builder.subscriptionField('turnUpdated', (t) => t.field({
  type: TurnType,
  args: { id: t.arg.id({ required: true }) },
  subscribe: async function* (_r, { id }, ctx) {
    const userId = requireUser(ctx);
    const it = ctx.deps.pubsub.subscribe('turn', String(id))[Symbol.asyncIterator]();
    const pending = it.next();
    pending.catch(() => {});
    try {
      const row = await loadOwnedTurn(ctx, userId, String(id));
      if (!row) throw gqlError('NOT_FOUND', 'Turn not found');
      yield row;
      if (done(row)) return;
      for (let r = await pending; !r.done; r = await it.next()) {
        yield r.value;
        if (done(r.value)) return;
      }
    } finally {
      await it.return?.();
    }
  },
  resolve: (payload) => payload,
}));
```

- [ ] **Step 4: Run the tests**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/schema/subscription.ts backend/test/schema/subscription.test.ts
git commit -m "feat(backend): turnUpdated subscription

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Schema export, smoke test, backend docs

**Files:**
- Modify: `backend/schema.graphql` (generated), `backend/scripts/smoke.ts`, `backend/CLAUDE.md`, `backend/test/schema/schema.test.ts` (if it snapshots the SDL)

- [ ] **Step 1: Export the schema**

Run: `cd backend && npm run schema:export && git diff --stat schema.graphql`
Expected: diff adds `type Turn`, `sendTurn`, `turnUpdated`, `Session.crisis`, `Session.turns`, `User.profile`. Add two assertions to `backend/test/schema/schema.test.ts` (it checks field types directly, not the SDL):

```ts
  expect(String(schema.getMutationType()!.getFields().sendTurn.type)).toBe('Turn!');
  expect(String(schema.getSubscriptionType()!.getFields().turnUpdated.type)).toBe('Turn!');
```

- [ ] **Step 2: Extend the smoke script**

In `backend/scripts/smoke.ts`, after `if (final.status === 'COMPLETED' && final.audioUrl) code = 0; else …`, replace that line with:

```ts
  if (final.status !== 'COMPLETED' || !final.audioUrl) { console.error('smoke FAILED, final row:', final); throw new Error('session did not complete'); }

  console.log('sending a chat turn…');
  const { sendTurn } = await upload('mutation($id:ID!,$r:File!){ sendTurn(sessionId:$id, recording:$r){ id } }', 'r', { id: createSession.id });
  const turn = await new Promise<any>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timed out waiting for the turn')), TIMEOUT_MS);
    timer.unref();
    client.subscribe({
      query: 'subscription($id:ID!){ turnUpdated(id:$id){ status userText agentText audioUrl crisis closing error } }',
      variables: { id: sendTurn.id },
    }, {
      next: ({ data }: any) => { console.log(data.turnUpdated); if (['COMPLETED', 'FAILED'].includes(data.turnUpdated.status)) resolve(data.turnUpdated); },
      error: reject,
      complete: () => reject(new Error('turn subscription ended without a terminal status')),
    });
  });
  if (turn.status !== 'COMPLETED' || !turn.audioUrl) { console.error('smoke FAILED, turn:', turn); throw new Error('turn did not complete'); }

  const meRes = await fetch(`${url}/graphql`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ query: '{ me { profile } }' }) });
  const me = (await meRes.json() as any).data?.me;
  console.log('profile:', me?.profile);
  if (!me?.profile) throw new Error('profile was not written');
  code = 0;
```

- [ ] **Step 3: Update backend/CLAUDE.md**

Under **Layout** add: `` `src/agent/` therapist agent: `llm.ts` provider seam, `agent.ts` (reframe / chatTurn / updateProfile), `context.ts` (profile + recent sessions), `prompts.ts`, `crisis.ts` keyword floor. `src/pipeline/turn.ts` chat turns, `src/pipeline/profile.ts` profile refresh. ``
Under **Conventions**, extend the error code list with `SESSION_NOT_READY, TURN_IN_PROGRESS`, and add: `Turns reuse SessionStatus; REFRAMING means "agent is thinking". A turn FAILS with EMPTY_TRANSCRIPT on silence.`

- [ ] **Step 4: Run smoke (needs Docker, `.env`, VoiceStudio pod up)**

Run: `cd backend && npm run voice:start && npm run dev` (separate terminal) then `npm run smoke`
Expected: exits 0, logs the turn reaching COMPLETED and a non-null profile. If the pod cannot start (A40 stock LOW), note it in the commit message and leave smoke for Task 14.

- [ ] **Step 5: Commit**

```bash
git add backend/schema.graphql backend/scripts/smoke.ts backend/CLAUDE.md backend/test/schema
git commit -m "chore(backend): export schema with turns; smoke covers a chat turn and profile

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: iOS models, operations, codegen, API seam

**Files:**
- Modify: `ios/ReframedThoughts/Network/Models.swift`, `ios/ReframedThoughts/Network/API.swift`, `ios/ReframedThoughts/Network/API+Live.swift`, `ios/ReframedThoughts/GraphQL/Operations.graphql`, `ios/ReframedThoughtsTests/Support/APIStub.swift`, `ios/ReframedThoughtsTests/CodegenTests.swift`, `ios/ReframedThoughtsTests/ModelsTests.swift`
- Generated: `ios/ReframedThoughts/Generated/` (never hand-edit)

**Interfaces:**
- Produces: `struct Turn { id, status: SessionStatus, userText: String?, agentText: String?, audioUrl: URL?, crisis: Bool, closing: Bool, error: String?, createdAt: Date }`; `Session` gains `var crisis: Bool = false`, `var turns: [Turn] = []`; `User` gains `var profile: String? = nil`; `API.sendTurn: (String, URL) async throws -> Turn`, `API.watchTurn: (String) -> AsyncThrowingStream<Turn, Error>`; `Turn.fixture(...)`.

- [ ] **Step 1: Write the failing tests**

Add to `ios/ReframedThoughtsTests/ModelsTests.swift`:

```swift
    @Test func sessionDefaultsHaveNoTurnsAndNoCrisis() {
        let s = Session.fixture()
        #expect(s.turns.isEmpty)
        #expect(!s.crisis)
        let t = Turn.fixture(agentText: "hi", closing: true)
        #expect(t.closing && t.agentText == "hi" && !t.crisis)
    }
```

Replace the body of `ios/ReframedThoughtsTests/CodegenTests.swift`'s test with:

```swift
        _ = GQL.MeQuery()
        _ = GQL.SessionUpdatedSubscription(id: "x")
        _ = GQL.TurnUpdatedSubscription(id: "x")
        _ = GQL.SendTurnMutation(sessionId: "s", recording: "recording")
        #expect(GQL.SessionStatus.completed.rawValue == "COMPLETED")
```

- [ ] **Step 2: Update models**

In `ios/ReframedThoughts/Network/Models.swift`:

```swift
struct User: Equatable, Hashable, Sendable { let id: String; let hasVoice: Bool; var profile: String? = nil }

struct Turn: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let status: SessionStatus
    let userText: String?
    let agentText: String?
    let audioUrl: URL?
    let crisis: Bool
    let closing: Bool
    let error: String?
    let createdAt: Date
}
```

and add to `Session` after `createdAt`:

```swift
    var crisis: Bool = false
    var turns: [Turn] = []
```

- [ ] **Step 3: Update the operations and regenerate**

`ios/ReframedThoughts/GraphQL/Operations.graphql`:

```graphql
fragment TurnFields on Turn {
  id status userText agentText audioUrl crisis closing error createdAt
}
fragment SessionFields on Session {
  id status transcript reframedText audioUrl error createdAt crisis turns { ...TurnFields }
}
query Me { me { id hasVoice profile } }
query Sessions($limit: Int, $before: DateTime) { sessions(limit: $limit, before: $before) { ...SessionFields } }
query Session($id: ID!) { session(id: $id) { ...SessionFields } }
mutation SignInWithApple($identityToken: String!) { signInWithApple(identityToken: $identityToken) { token user { id hasVoice } } }
mutation EnrollVoice($sample: File!, $referenceText: String!) { enrollVoice(sample: $sample, referenceText: $referenceText) { id hasVoice } }
mutation CreateSession($recording: File!) { createSession(recording: $recording) { ...SessionFields } }
mutation DeleteAccount { deleteAccount }
subscription SessionUpdated($id: ID!) { sessionUpdated(id: $id) { ...SessionFields } }
mutation PreviewVoice { previewVoice }
mutation SendTurn($sessionId: ID!, $recording: File!) { sendTurn(sessionId: $sessionId, recording: $recording) { ...TurnFields } }
subscription TurnUpdated($id: ID!) { turnUpdated(id: $id) { ...TurnFields } }
```

Run: `cd ios && Tools/apollo-ios-cli generate && xcodegen generate`
Expected: `Generated/` gains `TurnFields`, `SendTurnMutation`, `TurnUpdatedSubscription`.

- [ ] **Step 4: Extend the API seam, live implementation, and stub**

`ios/ReframedThoughts/Network/API.swift` add:

```swift
    var sendTurn: @Sendable (String, URL) async throws -> Turn
    var watchTurn: @Sendable (String) -> AsyncThrowingStream<Turn, Error>
```

`ios/ReframedThoughts/Network/API+Live.swift`: in `me:` build `User(id: u.id, hasVoice: u.hasVoice, profile: u.profile)`. Add after `previewVoice:`:

```swift
            sendTurn: { sessionId, url in
                try await mapped {
                    let file = try GraphQLFile(fieldName: "recording", originalName: "turn.m4a", mimeType: "audio/mp4", fileURL: url)
                    let r = try await client.upload(operation: GQL.SendTurnMutation(sessionId: sessionId, recording: "recording"), files: [file])
                    return Turn(try unwrap(r).sendTurn.fragments.turnFields)
                }
            },
            watchTurn: { id in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            let stream = try client.subscribe(subscription: GQL.TurnUpdatedSubscription(id: id), cachePolicy: .networkOnly)
                            for try await r in stream {
                                let t = Turn(try unwrap(r).turnUpdated.fragments.turnFields)
                                continuation.yield(t)
                                if t.status.isTerminal { break }
                            }
                            continuation.finish()
                        } catch {
                            let e = mapError(error)
                            continuation.finish(throwing: (e as? APIError) == .transport(APIError.networkUnavailable)
                                                ? APIError.transport(APIError.lostConnection) : e)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
```

Update the `Session` fragment init to pass `crisis: f.crisis, turns: f.turns.map { Turn($0.fragments.turnFields) }`, and add:

```swift
extension Turn {
    init(_ f: GQL.TurnFields) {
        self.init(id: f.id, status: SessionStatus(rawValue: f.status.rawValue) ?? .failed,
                  userText: f.userText, agentText: f.agentText,
                  audioUrl: f.audioUrl.flatMap(URL.init(string:)), crisis: f.crisis, closing: f.closing,
                  error: f.error, createdAt: Session.parseDate(f.createdAt) ?? .distantPast)
    }
}
```

`ios/ReframedThoughtsTests/Support/APIStub.swift`: add parameters

```swift
        sendTurn: @escaping @Sendable (String, URL) async throws -> Turn = { _, _ in throw APIError.server("unstubbed sendTurn") },
        watchTurn: @escaping @Sendable (String) -> AsyncThrowingStream<Turn, Error> = { _ in AsyncThrowingStream { $0.finish() } }
```

pass them to `API(...)`, and add:

```swift
extension Turn {
    static func fixture(id: String = "t1", status: SessionStatus = .uploaded, userText: String? = "I think she hates me", agentText: String? = nil, audioUrl: URL? = nil, crisis: Bool = false, closing: Bool = false, error: String? = nil, createdAt: Date = Date(timeIntervalSince1970: 0)) -> Turn {
        Turn(id: id, status: status, userText: userText, agentText: agentText, audioUrl: audioUrl, crisis: crisis, closing: closing, error: error, createdAt: createdAt)
    }
}
```

Also extend `Session.fixture` in the same file with `crisis: Bool = false, turns: [Turn] = []` parameters and pass them to the `Session(...)` initializer after `createdAt`.

- [ ] **Step 5: Run the iOS tests**

Run: `cd ios && xcodebuild test -project ReframedThoughts.xcodeproj -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -quiet CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`
Expected: build succeeds, all tests PASS including the new Models and Codegen tests.

- [ ] **Step 6: Commit**

```bash
git add ios/ReframedThoughts ios/ReframedThoughtsTests
git commit -m "feat(ios): Turn model, sendTurn/watchTurn API, profile on User, regenerated GraphQL

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: `ChatViewModel`

**Files:**
- Create: `ios/ReframedThoughts/Features/Chat/ChatViewModel.swift`, `ios/ReframedThoughtsTests/ChatViewModelTests.swift`

**Interfaces:**
- Consumes: `API.sendTurn`, `API.watchTurn`, `Recording`, `Turn`, `Session`.
- Produces: `ChatViewModel` with `Phase { idle, recording, sending, processing(SessionStatus), failed(String), permissionDenied }`, `turns: [Turn]`, `session: Session`, `isClosed`, `showsCrisis`, `canRecord`, `onReplyReady: ((URL) -> Void)?`, `record()`, `stopAndSend()`, `dismissError()`.

- [ ] **Step 1: Write the failing tests**

Create `ios/ReframedThoughtsTests/ChatViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import ReframedThoughts

@MainActor
struct ChatViewModelTests {
    func recording(permission: AudioRecorder.Permission = .granted) -> Recording {
        Recording(requestPermission: { permission }, start: {}, stop: { URL(fileURLWithPath: "/tmp/t.m4a") }, duration: { 2 })
    }
    nonisolated static func stream(_ turns: [Turn], thenThrow error: Error? = nil) -> AsyncThrowingStream<Turn, Error> {
        AsyncThrowingStream { c in turns.forEach { c.yield($0) }; if let error { c.finish(throwing: error) } else { c.finish() } }
    }
    let session = Session.fixture(id: "s1", status: .completed, reframedText: "I am learning")

    @Test func sendsTurnFollowsToCompletedAndPlaysReply() async {
        let done = Turn.fixture(status: .completed, agentText: "What went wrong?", audioUrl: URL(string: "https://r2/t.mp3"))
        let sent = Captured<String?>(nil)
        let api = API.stub(
            sendTurn: { id, _ in sent.value = id; return .fixture(status: .uploaded) },
            watchTurn: { _ in Self.stream([.fixture(status: .transcribing), .fixture(status: .reframing), done]) })
        let vm = ChatViewModel(session: session, api: api, recorder: recording(), onUnauthenticated: {})
        let played = Captured<URL?>(nil)
        vm.onReplyReady = { played.value = $0 }
        await vm.record(); await vm.stopAndSend()
        #expect(sent.value == "s1")
        #expect(vm.turns == [done])
        #expect(vm.phase == .idle)
        #expect(played.value == done.audioUrl)
        #expect(!vm.isClosed && !vm.showsCrisis && vm.canRecord)
    }
    @Test func closingTurnDisablesRecording() async {
        let done = Turn.fixture(status: .completed, agentText: "Take care.", closing: true)
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([done]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.isClosed && !vm.canRecord)
        await vm.record()
        #expect(vm.phase == .idle)
    }
    @Test func crisisFromSessionOrTurnShowsCard() async {
        let crisisSession = Session.fixture(id: "s2", status: .completed, reframedText: "You deserve support.", crisis: true)
        #expect(ChatViewModel(session: crisisSession, api: .stub(), recorder: recording(), onUnauthenticated: {}).showsCrisis)
        let done = Turn.fixture(status: .completed, agentText: "Please reach out.", crisis: true)
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([done]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.showsCrisis)
        #expect(vm.canRecord)
    }
    @Test func startsWithExistingTurns() {
        let old = Turn.fixture(id: "old", status: .completed, agentText: "earlier")
        let s = Session.fixture(id: "s3", status: .completed, turns: [old])
        let vm = ChatViewModel(session: s, api: .stub(), recorder: recording(), onUnauthenticated: {})
        #expect(vm.turns == [old])
    }
    @Test func failedTurnShowsMessageAndCanRetry() async {
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([.fixture(status: .failed, error: "EMPTY_TRANSCRIPT")]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.phase == .failed(ChatViewModel.failureMessage))
        vm.dismissError()
        #expect(vm.canRecord)
    }
    @Test func serverErrorUsesUserMessage() async {
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in throw APIError.server("The previous reply is still on its way") }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.phase == .failed("The previous reply is still on its way"))
    }
    @Test func unauthenticatedCallsBack() async {
        let called = Captured(false)
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in throw APIError.unauthenticated }), recorder: recording(), onUnauthenticated: { called.value = true })
        await vm.record(); await vm.stopAndSend()
        #expect(called.value)
    }
    @Test func permissionDenied() async {
        let vm = ChatViewModel(session: session, api: .stub(), recorder: recording(permission: .denied), onUnauthenticated: {})
        await vm.record()
        #expect(vm.phase == .permissionDenied)
    }
    @Test func streamEndingEarlyFails() async {
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.phase == .failed(APIError.lostConnection))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && xcodebuild test -project ReframedThoughts.xcodeproj -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -quiet CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -only-testing:ReframedThoughtsTests/ChatViewModelTests`
Expected: build FAILS, `ChatViewModel` undefined.

- [ ] **Step 3: Implement the view model**

Create `ios/ReframedThoughts/Features/Chat/ChatViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor @Observable
final class ChatViewModel {
    enum Phase: Equatable { case idle, recording, sending, processing(SessionStatus), failed(String), permissionDenied }
    private(set) var session: Session
    private(set) var turns: [Turn]
    private(set) var phase: Phase = .idle
    /// The view plays the agent's reply audio when a turn completes.
    var onReplyReady: ((URL) -> Void)?
    private let api: API
    private let recorder: Recording
    private let onUnauthenticated: () -> Void

    var isClosed: Bool { turns.last?.closing == true }
    var showsCrisis: Bool { session.crisis || turns.contains { $0.crisis } }
    var canRecord: Bool { phase == .idle && !isClosed }

    init(session: Session, api: API, recorder: Recording, onUnauthenticated: @escaping () -> Void) {
        self.session = session; self.turns = session.turns; self.api = api; self.recorder = recorder; self.onUnauthenticated = onUnauthenticated
    }

    func record() async {
        guard canRecord else { return }
        guard await recorder.requestPermission() == .granted else { phase = .permissionDenied; return }
        do { try recorder.start(); phase = .recording } catch { phase = .failed(error.localizedDescription) }
    }

    func stopAndSend() async {
        guard phase == .recording else { return }
        guard let url = recorder.stop() else { phase = .failed("Recording failed."); return }
        phase = .sending
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let turn = try await api.sendTurn(session.id, url)
            upsert(turn)
            await follow(turn.id)
        } catch { fail(error) }
    }

    func dismissError() { phase = .idle }

    private func follow(_ id: String) async {
        do {
            for try await t in api.watchTurn(id) {
                guard !Task.isCancelled else { return }
                upsert(t)
                switch t.status {
                case .completed:
                    phase = .idle
                    if let url = t.audioUrl { onReplyReady?(url) }
                    return
                case .failed: phase = .failed(Self.failureMessage); return
                default: phase = .processing(t.status)
                }
            }
            guard !Task.isCancelled else { return }
            phase = .failed(APIError.lostConnection)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func upsert(_ t: Turn) {
        if let i = turns.firstIndex(where: { $0.id == t.id }) { turns[i] = t } else { turns.append(t) }
    }

    private func fail(_ error: Error) {
        if case APIError.unauthenticated = error { onUnauthenticated(); return }
        phase = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
    }

    static let failureMessage = "I didn't catch that. Try saying it again."
}

extension SessionStatus {
    var chatLabel: String {
        switch self {
        case .uploaded: "Sending…"
        case .transcribing: "Listening…"
        case .reframing: "Thinking…"
        case .synthesizing: "Finding your voice…"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same `xcodebuild test … -only-testing:ReframedThoughtsTests/ChatViewModelTests` command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/ReframedThoughts/Features/Chat/ChatViewModel.swift ios/ReframedThoughtsTests
git commit -m "feat(ios): ChatViewModel — send a spoken turn, follow it, surface crisis/closing

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Chat screen, crisis card, playback hooks

**Files:**
- Create: `ios/ReframedThoughts/Features/Chat/ChatView.swift`, `ios/ReframedThoughts/Features/Chat/CrisisCard.swift`
- Modify: `ios/ReframedThoughts/Features/Record/PlaybackView.swift`

**Interfaces:**
- Consumes: `ChatViewModel`, `AudioPlayer`, `AudioRecorder`, `AppState.api`, theme helpers.
- Produces: `ChatView(session:)`, `CrisisCard()`, `PlaybackView` shows `CrisisCard` when `session.crisis`, lists `session.turns`, and offers "Work through this" (or "Continue" when turns exist) navigating to `ChatView`.

These are SwiftUI views with no logic beyond the view models already tested; they are verified by building and by the manual run in Task 14. Keep every colour and font on the theme.

- [ ] **Step 1: Crisis card**

Create `ios/ReframedThoughts/Features/Chat/CrisisCard.swift`:

```swift
import SwiftUI

/// Shown whenever a session or turn is flagged. Not dismissable within the session.
struct CrisisCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You deserve support right now").font(.display(20, weight: .medium))
            Text("If you're thinking about harming yourself, please reach out to someone who can help. You don't have to carry this alone.")
                .foregroundStyle(Color.muted)
            Link(destination: URL(string: "tel:988")!) {
                Label("Call or text 988", systemImage: "phone.fill").frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
            Text("Or text HOME to 741741 to reach the Crisis Text Line.").font(.footnote).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 2: Chat view**

Create `ios/ReframedThoughts/Features/Chat/ChatView.swift`:

```swift
import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(AppState.self) private var app
    let session: Session
    @State private var recorder = AudioRecorder()
    @State private var player = AudioPlayer()
    @State private var vm: ChatViewModel?

    var body: some View {
        Group { if let vm { content(vm) } else { ProgressView().tint(.forest) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sand.ignoresSafeArea())
            .navigationTitle("Work through it")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if vm == nil {
                    let m = ChatViewModel(session: session, api: app.api, recorder: recorder.asRecording, onUnauthenticated: { app.signOut() })
                    m.onReplyReady = { player.play($0) }
                    vm = m
                }
            }
            .onDisappear { player.stop() }
    }

    @ViewBuilder private func content(_ vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You said").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                            Text(vm.session.transcript ?? "").italic().foregroundStyle(Color.muted)
                            Text(vm.session.reframedText ?? "").font(.display(20, weight: .medium)).padding(.top, 4)
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                        if vm.showsCrisis { CrisisCard() }
                        ForEach(vm.turns) { t in
                            if let u = t.userText { bubble(u, mine: true) }
                            if let a = t.agentText { agentBubble(a, audio: t.audioUrl) } else if !t.status.isTerminal { Text(t.status.chatLabel).font(.footnote).foregroundStyle(Color.muted) }
                        }
                        if vm.isClosed { Text("Done for now. Come back any time.").font(.footnote).foregroundStyle(Color.muted).frame(maxWidth: .infinity) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(Theme.spacing)
                }
                .onChange(of: vm.turns) { withAnimation { proxy.scrollTo("bottom") } }
            }
            controls(vm)
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(text).foregroundStyle(mine ? Color.onClay : Color.bark).padding(12)
            .background(mine ? Color.clay : Color.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
    private func agentBubble(_ text: String, audio: URL?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            bubble(text, mine: false)
            if let audio { Button { player.isPlaying ? player.stop() : player.play(audio) } label: { Image(systemName: player.isPlaying ? "stop.circle" : "play.circle").font(.title2) }.tint(.forest) }
        }
    }

    @ViewBuilder private func controls(_ vm: ChatViewModel) -> some View {
        VStack(spacing: 8) {
            switch vm.phase {
            case .idle where vm.isClosed: EmptyView()
            case .idle:
                Button { Task { await vm.record() } } label: { Image(systemName: "mic.fill") }.buttonStyle(RecordButtonStyle())
                Text("Tap to reply").font(.footnote).foregroundStyle(Color.muted)
            case .recording:
                Button { Task { await vm.stopAndSend() } } label: { Image(systemName: "stop.fill") }.buttonStyle(RecordButtonStyle(active: true))
                Text(String(format: "%.0f s · tap when you're done", recorder.duration)).font(.footnote).foregroundStyle(Color.muted)
            case .sending: ProgressView().tint(.forest); Text(SessionStatus.uploaded.chatLabel).font(.footnote).foregroundStyle(Color.muted)
            case .processing(let s): ProgressView().tint(.forest); Text(s.chatLabel).font(.footnote).foregroundStyle(Color.muted)
            case .failed(let msg):
                Text(msg).multilineTextAlignment(.center).font(.footnote)
                Button("Try again") { vm.dismissError() }.buttonStyle(SecondaryButtonStyle())
            case .permissionDenied:
                Text("Microphone access is off. Enable it in Settings to reply.").font(.footnote).multilineTextAlignment(.center)
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity)
        .background(Color.sand)
    }
}
```

- [ ] **Step 3: Hook playback**

In `ios/ReframedThoughts/Features/Record/PlaybackView.swift`:
- Add `@State private var showChat = false`.
- Change the "Reframed" caption to `Text(session.crisis ? "A note for you" : "Reframed")`.
- After the reframed-text card add `if session.crisis { CrisisCard() }`.
- After the transcript block add:

```swift
                if !session.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Worked through").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                        ForEach(session.turns) { t in
                            if let u = t.userText { Text(u).italic().foregroundStyle(Color.muted) }
                            if let a = t.agentText { Text(a) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                }
                Button(session.turns.isEmpty ? "Work through this" : "Continue") { showChat = true }.buttonStyle(SecondaryButtonStyle())
```

- Add `.navigationDestination(isPresented: $showChat) { ChatView(session: session) }` to the `ScrollView`.

Both `RecordView` and `SessionDetailView` already wrap `PlaybackView` in a `NavigationStack`, so the destination resolves in both.

- [ ] **Step 4: Update ios/CLAUDE.md**

Under **Layout** change the Features line to `ReframedThoughts/Features/{Auth,Enroll,Record,Chat,History,Settings}/` and add: `` `Chat/` — `ChatView` + `ChatViewModel` (spoken follow-up turns via `sendTurn` / `watchTurn`), `CrisisCard` (988 / 741741, shown whenever `session.crisis` or any `turn.crisis`). `` Under **Conventions** add: `Turns reuse SessionStatus; label REFRAMING as "Thinking…" in chat (`SessionStatus.chatLabel`). The crisis card is never dismissable within a session.`

- [ ] **Step 5: Build and run the whole iOS suite**

Run: `cd ios && xcodegen generate && xcodebuild test -project ReframedThoughts.xcodeproj -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -quiet CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`
Expected: build succeeds, all tests PASS (ThemeTests confirms no new colour names were needed).

- [ ] **Step 6: Commit**

```bash
git add ios/ReframedThoughts
git commit -m "feat(ios): chat screen with spoken replies, crisis card, work-through entry from playback

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: "What Reframed remembers" in Settings

**Files:**
- Create: `ios/ReframedThoughts/Features/Settings/ProfileViewModel.swift`, `ios/ReframedThoughts/Features/Settings/ProfileView.swift`, `ios/ReframedThoughtsTests/ProfileViewModelTests.swift`
- Modify: `ios/ReframedThoughts/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `API.me` (now returns `User.profile`).
- Produces: `ProfileViewModel` with `State { loading, loaded(String?), failed(String) }`, `load()`.

- [ ] **Step 1: Write the failing tests**

Create `ios/ReframedThoughtsTests/ProfileViewModelTests.swift`:

```swift
import Testing
@testable import ReframedThoughts

@MainActor
struct ProfileViewModelTests {
    @Test func loadsProfile() async {
        let vm = ProfileViewModel(api: .stub(me: { User(id: "u", hasVoice: true, profile: "Tends to catastrophize.") }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .loaded("Tends to catastrophize."))
    }
    @Test func emptyProfileIsNil() async {
        let vm = ProfileViewModel(api: .stub(me: { User(id: "u", hasVoice: true) }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .loaded(nil))
    }
    @Test func failureShowsMessage() async {
        let vm = ProfileViewModel(api: .stub(me: { throw APIError.transport("offline") }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .failed("offline"))
    }
    @Test func unauthenticatedCallsBack() async {
        let called = Captured(false)
        let vm = ProfileViewModel(api: .stub(me: { throw APIError.unauthenticated }), onUnauthenticated: { called.value = true })
        await vm.load()
        #expect(called.value)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd ios && xcodebuild test … -only-testing:ReframedThoughtsTests/ProfileViewModelTests` (same flags as Task 11).
Expected: build FAILS, `ProfileViewModel` undefined.

- [ ] **Step 3: Implement**

Create `ios/ReframedThoughts/Features/Settings/ProfileViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor @Observable
final class ProfileViewModel {
    enum State: Equatable { case loading, loaded(String?), failed(String) }
    private(set) var state: State = .loading
    private let api: API
    private let onUnauthenticated: () -> Void
    init(api: API, onUnauthenticated: @escaping () -> Void) { self.api = api; self.onUnauthenticated = onUnauthenticated }

    func load() async {
        do { state = .loaded(try await api.me().profile) }
        catch APIError.unauthenticated { onUnauthenticated() }
        catch { state = .failed((error as? APIError)?.userMessage ?? error.localizedDescription) }
    }
}
```

Create `ios/ReframedThoughts/Features/Settings/ProfileView.swift`:

```swift
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var vm: ProfileViewModel?

    var body: some View {
        Group {
            switch vm?.state {
            case .none, .loading: ProgressView().tint(.forest)
            case .failed(let msg):
                VStack(spacing: Theme.spacing) { Text(msg); Button("Retry") { Task { await vm?.load() } }.buttonStyle(PrimaryButtonStyle()) }.padding(Theme.spacing)
            case .loaded(nil):
                ContentUnavailableView("Nothing yet", systemImage: "book.closed", description: Text("After your first reframe, Reframed keeps short notes here about what it has noticed and what has helped."))
            case .loaded(let notes?):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reframed's notes").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                        Text(notes).lineSpacing(4)
                        Text("Updated after every session. Deleting your account erases these notes.").font(.footnote).foregroundStyle(Color.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).card().padding(Theme.spacing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sand.ignoresSafeArea())
        .navigationTitle("What Reframed remembers")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm == nil { vm = ProfileViewModel(api: app.api, onUnauthenticated: { app.signOut() }) }; await vm?.load() }
    }
}
```

In `ios/ReframedThoughts/Features/Settings/SettingsView.swift` change the first section to:

```swift
                Section {
                    NavigationLink("What Reframed remembers about me") { ProfileView() }
                    NavigationLink("Re-record my voice") { RerecordVoiceView() }
                }
```

- [ ] **Step 4: Run the full iOS suite**

Run: `cd ios && xcodegen generate && xcodebuild test -project ReframedThoughts.xcodeproj -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -quiet CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/ReframedThoughts/Features/Settings ios/ReframedThoughtsTests/ProfileViewModelTests.swift
git commit -m "feat(ios): read-only 'What Reframed remembers' screen in Settings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: Deploy, migrate, end-to-end

**Files:** none new. Uses `backend/.env` (gitignored), wrangler, the RunPod pod.

- [ ] **Step 1: Apply the migration to Neon**

Run: `cd backend && npm run db:migrate`
Expected: `0001_therapist_agent` applied to `DATABASE_URL` (production branch). Confirm with `psql "$DATABASE_URL" -c '\d turns'` or the Neon console.

- [ ] **Step 2: Local end-to-end**

Run: `cd backend && npm run voice:start && npm run dev` (separate terminal), then `npm run smoke`.
Expected: exit 0; log shows the session COMPLETED, the turn COMPLETED with `audioUrl`, and a non-null profile.

- [ ] **Step 3: Simulator run**

Run: `cd ios && open ReframedThoughts.xcodeproj`, run with the `API_BASE_URL` env var enabled against the local backend. Walk through: record a thought → playback → "Work through this" → tap mic, speak, hear the reply in your voice → say "I think I'm done" → "Done for now" appears. Then Settings → "What Reframed remembers about me" shows notes. Record a thought containing "I want to end it all" → playback shows the crisis card with the 988 link and a caring note instead of an affirmation.

- [ ] **Step 4: Deploy**

Run: `cd backend && npx wrangler deploy`
Expected: Worker + container deployed. Then `SMOKE_URL=https://reframed-thoughts.joshuarcooper.workers.dev npm run smoke` exits 0.

- [ ] **Step 5: Stop the GPU pod and commit anything left**

Run: `cd backend && npm run voice:stop`. Run `git status`; if the smoke or deploy steps changed tracked files, commit them:

```bash
git add -A
git commit -m "chore: therapist agent deployed and verified end to end

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

Push with the `coopaloop13` token as recorded in memory.
