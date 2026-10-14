# backend

GraphQL API for Reframed Thoughts. Node 22, ESM, TypeScript.

## Commands
- `npm test` — vitest, no network (msw errors on unhandled requests), Postgres via pglite in memory.
- `npm run dev` — builds the Docker image and runs it on :8080 via docker compose (Docker Desktop must be running). `npm run dev:down` stops it, `npm run dev:logs` tails it. No hot reload: re-run `npm run dev` after code changes. `npm run typecheck`, `npm run typecheck:worker`.
- `npm run build` then `npm start` (runs `dist/src/server.js`).
- `npm run smoke` — end-to-end against real services; needs `.env` plus `test/fixtures/sample.m4a`; exits 0 only on COMPLETED with audio.
- `dev` reads `.env` through compose `env_file`; `smoke` loads it via tsx `--env-file`.
- `npm run db:generate` — drizzle-kit generate migrations from `src/db/schema.ts`. `npm run db:migrate` — apply to `DATABASE_URL`.
- `npm run schema:export` — writes `schema.graphql` (iOS Apollo codegen reads it). Run after any schema change.
- `npm run voice:start` / `voice:stop` / `voice:status` — bring the RunPod VoiceStudio GPU pod up or down (it bills ~$0.59/hr while running; everything else scales to zero on its own). Needs `RUNPOD_API_KEY` and `RUNPOD_POD_ID` in `.env`.
- Locally, `docker compose up` also builds `voicestudio/Dockerfile` (VoiceStudio v0.5.6, CPU only, data in the `voicestudio-data` volume, admin port on 127.0.0.1:3900). Leave `VOICESTUDIO_URL` empty in `.env` to use it. Containers can't use the Apple GPU, so synthesis is slow.
- `npm run voice:local` — the fast alternative: VoiceStudio natively on this Mac (Apple GPU via MPS). One-time: clone `debpalash/VoiceStudio` v0.5.6 to `~/Development/VoiceStudio` and `uv sync --locked`; then set `VOICESTUDIO_URL=http://host.docker.internal:3900`.
- `npx wrangler deploy` — builds the Dockerfile, pushes the image, deploys the Worker proxy.

## Layout
- `src/server.ts` boot: env → db → clients → yoga + graphql-ws → sweeper → listen.
- `src/app.ts` `createApp(deps)` returns the Yoga instance. `Deps` is the only seam; tests pass fakes.
- `src/schema/` Pothos types and resolvers. `src/pipeline/` transcribe → reframe → synthesize. `src/clients/` r2, voicestudio, openai. `src/auth/` Apple token verify, our JWT. `src/db/` drizzle schema + `drizzle/` migrations.
- `src/agent/` therapist agent: `llm.ts` provider seam, `agent.ts` (reframe / chatTurn / updateProfile), `context.ts` (profile + recent sessions), `prompts.ts`, `crisis.ts` keyword floor. `src/pipeline/turn.ts` chat turns, `src/pipeline/profile.ts` profile refresh.
- `worker/index.ts` Cloudflare Worker: `getContainer(env.BACKEND).fetch(request)`.

## Conventions
- Stack: graphql-yoga 5, @pothos/core 4, graphql-ws 6 (`import ... from 'graphql-ws/use/ws'`), drizzle-orm, jose, aws4fetch.
- Session status order: UPLOADED → TRANSCRIBING → REFRAMING → SYNTHESIZING → COMPLETED | FAILED. Every transition writes the row then publishes `session` on pubsub.
- Errors to clients use `GraphQLError` with `extensions.code` ∈ UNAUTHENTICATED, INVALID_APPLE_TOKEN, VOICE_NOT_ENROLLED, NOT_FOUND, SESSION_NOT_READY, TURN_IN_PROGRESS.
- Turns reuse SessionStatus; REFRAMING means "agent is thinking". A turn FAILS with EMPTY_TRANSCRIPT on silence.
- Env vars: see `.env.example`. Production secrets: `wrangler secret put <NAME>`; the Worker passes them to the container as `envVars`.

## External services (one-time setup)
1. VoiceStudio on a RunPod GPU pod: image `ghcr.io/debpalash/voicestudio:stable`, volume mounted at `/app/omnivoice_data`, env `OMNIVOICE_SERVER_MODE=1`, `OMNIVOICE_API_KEY=<random>`, expose port 3900 via RunPod HTTPS proxy → `VOICESTUDIO_URL`.
2. Neon Postgres project → pooled connection string → `DATABASE_URL`.
3. R2 bucket + S3 API token → `R2_*`.
4. Apple Developer: enable Sign in with Apple on the app's bundle id → `APPLE_BUNDLE_ID`.
5. OpenAI API key → `OPENAI_API_KEY`, `OPENAI_MODEL`.
