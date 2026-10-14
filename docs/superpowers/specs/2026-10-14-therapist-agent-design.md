# Therapist agent — design (architectural path)

## Context

Today the backend reframes a thought with one stateless OpenAI chat completion (`backend/src/clients/openai.ts`, prompt in `backend/src/pipeline/reframe-prompt.ts`), called from `backend/src/pipeline/run.ts:28`. The only history is the `sessions` list. The user wants their own AI agent that behaves like a therapist: it remembers the person across sessions, helps them work through a negative thought in a short conversation, and over time nudges them toward seeing the positive.

Decisions made with the user:

| Topic | Decision |
|---|---|
| Agent type | Our own agent logic on a hosted LLM API; no training or self-hosting |
| Interaction | Keep speak → affirmation-in-own-voice loop, make it history-aware; add optional "work through this" follow-up chat after playback |
| Memory | Agent-maintained per-user profile (rewritten after each session) + last few sessions verbatim |
| LLM | Provider-agnostic `LLM` seam; ship the OpenAI adapter now |
| Safety | Detect crisis language; agent stops reframing and responds with care; app shows hotline resources; session flagged |
| Framework | CBT: name the thought, spot the distortion, examine evidence, build a balanced alternative |
| Chat delivery | Agent replies synthesized in the user's own cloned voice (text shown too) |
| Architecture | A: prompted agent with fixed calls (reframe, chatTurn, updateProfile), deterministic context from Postgres |

Assumptions: OpenAI JSON mode (`response_format: {type: 'json_object'}`) is available on the configured model; hotline is US 988 for now; a chat turn is user-speaks → agent-speaks, one exchange per turn.

## Section 1 — Data model

`backend/src/db/schema.ts`, new migration via `npm run db:generate`.

- `users` + `profile text null`, `profile_updated_at timestamptz null`. The agent's running summary of the person.
- `sessions` + `crisis boolean not null default false`.
- new `turns` table, one row per exchange in the follow-up chat, same shape as `sessions` so the pipeline logic is reused:
  `id uuid pk`, `session_id uuid fk → sessions cascade`, `status session_status default 'UPLOADED'`, `recording_key text not null`, `user_text text null`, `agent_text text null`, `audio_key text null`, `crisis boolean default false`, `closing boolean default false`, `error text null`, `created_at`, `updated_at`.

R2 keys: `turns/{turnId}.m4a` (recording), `turns/{turnId}.mp3` (reply audio).

## Section 2 — GraphQL additions

```graphql
type User { id: ID!  hasVoice: Boolean!  profile: String }        # read-only "what the agent remembers"
type Session { ...existing  crisis: Boolean!  turns: [Turn!]! }
type Turn {
  id: ID!  status: SessionStatus!                                    # reuse enum; REFRAMING = agent thinking
  userText: String  agentText: String  audioUrl: String
  crisis: Boolean!  closing: Boolean!  error: String  createdAt: DateTime!
}
type Mutation { sendTurn(sessionId: ID!, recording: File!): Turn! } # session must be COMPLETED and owned
type Subscription { turnUpdated(id: ID!): Turn! }
```

## Section 3 — Agent module `backend/src/agent/`

- `llm.ts` — the seam: `type LLM = (req: { system: string; messages: { role: 'user' | 'assistant'; content: string }[]; json?: boolean }) => Promise<string>`.
- `backend/src/clients/openai.ts` — becomes `createOpenAILLM({ apiKey, model }): LLM`, same fetch, adds `response_format` when `json`. Reframe prompt moves out of it.
- `context.ts` — `loadContext(db, userId)`: `{ profile, recent }` where `recent` is the last 5 sessions (transcript, affirmation, turns' user/agent text, date). `renderContext(ctx)` → one text block for the prompt.
- `prompts.ts` — `THERAPIST_SYSTEM` (persona, CBT method, tone rules from today's prompt, safety rules) plus per-call instructions for reframe / chat / profile, each stating the exact JSON shape.
- `crisis.ts` — small keyword floor (`/suicid|kill myself|end my life|self.?harm|…/i`). Final flag = keyword hit OR model flag. Safety code is not simplified away.
- `agent.ts` — `createAgent(llm): Agent`:
  - `reframe(ctx, transcript) → { affirmation, crisis }`. In crisis the "affirmation" is a short caring message, not a reframe.
  - `chatTurn(ctx, priorTurns, userText) → { reply, crisis, closing }`. `closing` true when the agent has wrapped up (balanced thought agreed, or user signals done).
  - `updateProfile(ctx, sessionText) → string`. Rewrites the profile, ≤ 200 words: themes, distortions noticed, what helped, progress, things to be gentle about.
  - Parses and validates JSON; throws on bad shape (pipeline marks FAILED; sweeper retries).
- `Deps.reframe` is replaced by `Deps.agent: Agent`. Test helper stubs it.

## Section 4 — Pipelines

- `run.ts` reframe step: load context → `agent.reframe` → store `reframedText` + `crisis`. After COMPLETED, fire-and-forget `agent.updateProfile` and write `users.profile`.
- `turn.ts` — `runTurn(deps, turnId)`: TRANSCRIBING (VoiceStudio) → REFRAMING (`agent.chatTurn` with the session's transcript/affirmation + prior completed turns) → SYNTHESIZING (user's clone) → COMPLETED; publishes `turn` on pubsub. After COMPLETED, fire-and-forget profile update. `transition` is duplicated in `turn.ts` (10 lines) rather than made generic over two Drizzle tables. Sweeper covers turns too.
- ponytail: profile updates are last-writer-wins; turns in one session are sequential so this is fine. Add a per-user lock if concurrent sessions appear.

## Section 5 — iOS

- `PlaybackView`: add "Work through this" → `ChatView(session)`.
- `ChatView` + `ChatViewModel`: shows the original thought/affirmation, then turns as bubbles; hold-to-talk mic reuses `AudioRecorder`; `sendTurn` → subscribe `turnUpdated` → auto-play reply when COMPLETED. When a turn has `closing`, show "Done for now". Disable mic while a turn is in flight.
- `CrisisCard`: shown on PlaybackView/ChatView when `session.crisis` or any `turn.crisis`: supportive copy, "Call 988" (`tel:988`), "Text HOME to 741741". Not dismissable within that session.
- `SessionDetailView`: lists turns under the affirmation.
- `SettingsView`: "What Reframed remembers about me" → read-only profile text (empty state if none).
- `API`: `sendTurn`, `watchTurn`; `Session` gains `crisis`, `turns`. Regenerate Apollo after `npm run schema:export`.

## Section 6 — Testing

- Backend (vitest, no network): `agent.test.ts` with a stub `LLM` asserting system prompt, rendered context, JSON parsing, crisis OR-ing, bad-JSON throw; `context.test.ts` over pglite; `turn.test.ts` pipeline statuses + sweeper; `schema/turn.test.ts` for `sendTurn` guards (owned, COMPLETED, voice enrolled) and `turnUpdated`; `openai.test.ts` updated for `LLM` shape + json mode; `crisis.test.ts`.
- iOS: `ChatViewModelTests` with `API.stub`.
- `npm run smoke`: after COMPLETED, send one turn from `test/fixtures/sample.m4a` and wait for its COMPLETED.

## Build order (task groups for the implementation plan)

1. `LLM` seam + OpenAI adapter + prompts + agent functions (pure, stubbed LLM).
2. Schema/migration: profile, crisis, turns. Context loader.
3. Reframe pipeline uses agent + crisis + profile update.
4. Turns: `sendTurn`, `runTurn`, `turnUpdated`, sweeper, smoke.
5. iOS: chat flow, crisis card, settings profile, detail view.
6. Deploy + e2e on device.
