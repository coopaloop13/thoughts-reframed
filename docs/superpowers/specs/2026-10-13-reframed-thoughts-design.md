# Reframed Thoughts — v1 design (architectural path)

## Context

Rebuild of `thoughts-reframed`. The user speaks a negative thought; the backend transcribes it, rewrites it as an affirmation, and reads it back in a clone of the user's own voice. The old build was REST on Hono/D1 with ElevenLabs, had a broken pipeline, client-only favourites, and no tests. This rebuild is a clean monorepo: a GraphQL backend in a Docker image on Cloudflare Containers, a SwiftUI iOS app using Apollo, and VoiceStudio replacing ElevenLabs. All code is written TDD (superpowers:test-driven-development).

Decisions already made with the user:

| Topic | Decision |
|---|---|
| v1 scope | Core loop only: sign in, enroll voice, record → transcribe → reframe → synthesize → play, session history. Favourites, meditations, paid tiers are later sub-projects. |
| Backend | Node 22 / TypeScript, GraphQL Yoga + Pothos, Vitest |
| Database | Postgres on Neon, Drizzle ORM, audio in R2 |
| Auth | Sign in with Apple → backend-issued JWT |
| Voice | VoiceStudio on a rented GPU host (RunPod pod, persistent volume), called over HTTPS |
| Transcription | VoiceStudio `/v1/audio/transcriptions` |
| Reframe | OpenAI chat completions |
| iOS GraphQL | Apollo iOS with codegen |
| Pipeline | Async; status streamed to the app via GraphQL subscriptions |
| Layout | Monorepo `backend/` + `ios/`, CLAUDE.md at root and in each |

Assumptions I'm making (say so if wrong): Neon free tier for Postgres; RunPod as the GPU host; one container instance for v1; iOS 17+; recordings uploaded as m4a/AAC; OpenAI model id lives in an env var.

## Architecture

```
iPhone (SwiftUI + Apollo)
   │ HTTPS POST /graphql (queries, mutations, multipart upload)
   │ WSS /graphql  (graphql-transport-ws subscriptions)
   ▼
Cloudflare Worker (thin proxy) ──► Container DO (singleton) ──► Node: Yoga + graphql-ws
                                                                  │
                                            ┌─────────────────────┼─────────────────────┐
                                            ▼                     ▼                     ▼
                                     Neon Postgres          R2 (S3 API)        VoiceStudio (RunPod GPU)
                                     (users, sessions)   (clips, mp3s)        /profiles, /v1/audio/*
                                                                                        │
                                                                                 OpenAI (reframe)
```

- Worker is ~10 lines: `getContainer(env.BACKEND).fetch(request)` (plain `fetch`, not `containerFetch`, so WebSocket upgrades pass through). Container `sleepAfter: "10m"`, `max_instances: 1`, instance type `basic`.
- Container has no Cloudflare bindings. It reaches Postgres via Neon's pooled connection string and R2 via S3-compatible API (`aws4fetch`). Secrets flow Worker secret → Container `envVars`.
- Single instance means in-process pub/sub (`createPubSub` from Yoga) is enough for subscriptions. `ponytail:` single container + in-process pubsub; move pubsub to a DO or Redis if `max_instances > 1`.

## GraphQL schema (v1)

```graphql
scalar DateTime
scalar File

type User { id: ID!  hasVoice: Boolean! }
type AuthPayload { token: String!  user: User! }

enum SessionStatus { UPLOADED TRANSCRIBING REFRAMING SYNTHESIZING COMPLETED FAILED }

type Session {
  id: ID!  status: SessionStatus!
  transcript: String  reframedText: String
  audioUrl: String          # presigned R2 GET, 1h, generated at resolve time, never stored
  error: String  createdAt: DateTime!
}

type Query {
  me: User!
  sessions(limit: Int = 20, before: DateTime): [Session!]!
  session(id: ID!): Session
}
type Mutation {
  signInWithApple(identityToken: String!): AuthPayload!
  enrollVoice(sample: File!, referenceText: String!): User!
  createSession(recording: File!): Session!     # stores clip, returns UPLOADED, kicks off pipeline
  deleteAccount: Boolean!                        # deletes VoiceStudio profile, R2 objects, rows
}
type Subscription { sessionUpdated(id: ID!): Session! }
```

Auth: `Authorization: Bearer <jwt>` on HTTP; `connectionParams.token` on WebSocket. Unauthenticated → GraphQL error `UNAUTHENTICATED`.

## Data model (Drizzle, Postgres)

- `users`: `id uuid pk`, `apple_sub text unique`, `voice_profile_id text null`, `voice_sample_key text null`, `created_at`
- `sessions`: `id uuid pk`, `user_id fk`, `status enum`, `recording_key text`, `transcript text null`, `reframed_text text null`, `audio_key text null`, `error text null`, `created_at`, `updated_at`

R2 keys: `voices/{userId}.m4a`, `recordings/{sessionId}.m4a`, `affirmations/{sessionId}.mp3`.

## Pipeline

`createSession` writes the row + R2 object, returns, then `void runPipeline(sessionId)` in-process. Each stage: update row → `pubsub.publish('session', id, session)`.

1. TRANSCRIBING → VoiceStudio `POST /v1/audio/transcriptions`
2. REFRAMING → OpenAI chat completion with the reframe prompt (one file, golden-file test)
3. SYNTHESIZING → VoiceStudio `POST /v1/audio/speech { model: default, voice: user.voice_profile_id, input, response_format: "mp3" }` → R2
4. COMPLETED (or FAILED with `error`)

Durability: on boot, a sweeper re-runs any session in a non-terminal status with `updated_at` older than 2 minutes. `ponytail:` in-process runner + boot sweeper; move to a Cloudflare Queue consumer if jobs get lost in practice. The open WebSocket from the app keeps the container awake during the run anyway.

## Backend layout

```
backend/
  CLAUDE.md
  Dockerfile              node:22-slim multi-stage, runs dist/server.js on :8080
  wrangler.jsonc          worker + containers config (image: ./Dockerfile, max_instances 1)
  worker/index.ts         Container class + proxy fetch
  drizzle.config.ts
  src/
    server.ts             http server, yoga, graphql-ws (ws), boot sweeper
    schema/               pothos builder, user.ts, session.ts, auth.ts
    db/schema.ts, db/client.ts, drizzle/ (migrations)
    pipeline/run.ts, pipeline/reframe-prompt.ts
    clients/voicestudio.ts, clients/openai.ts, clients/r2.ts
    auth/apple.ts (verify Apple id token via JWKS with `jose`), auth/jwt.ts
  test/                   vitest; fetch mocked with msw; Postgres via @electric-sql/pglite
```

Dependencies: `graphql`, `graphql-yoga`, `@pothos/core`, `graphql-ws`, `ws`, `drizzle-orm`, `postgres`, `jose`, `aws4fetch`. Dev: `vitest`, `msw`, `@electric-sql/pglite`, `drizzle-kit`, `wrangler`, `@cloudflare/containers`.

## iOS layout

```
ios/
  CLAUDE.md
  ReframedThoughts.xcodeproj  (SwiftUI, iOS 17+, SPM: apollo-ios)
  apollo-codegen-config.json  schema from ../backend/schema.graphql
  ReframedThoughts/
    App/            ReframedThoughtsApp, AppConfig (LOCAL_DEV switch, like before)
    Network/        ApolloClientFactory (SplitNetworkTransport: HTTP + WebSocketTransport graphql-transport-ws), TokenStore (Keychain)
    Features/
      Auth/         SignInView (ASAuthorizationController) + SignInViewModel
      Enroll/       EnrollVoiceView (fixed paragraph, record, upload) + VM
      Record/       RecordView → ProcessingView (subscribes sessionUpdated) → PlaybackView
      History/      SessionsListView
    Services/       AudioRecorder (AVAudioRecorder, m4a), AudioPlayer (AVPlayer)
  ReframedThoughtsTests/   ViewModel tests using Apollo's MockNetworkTransport
```

Reuse from the old app (copy, then test): `AudioRecorderService` recording setup and `AppConfig` env switch from `/Users/joshcooper/Development/thoughts-reframed/thoughts-reframed/`. Everything else is rewritten.

## CLAUDE.md contents

- **Root**: what the product does, monorepo map, "every change is TDD via superpowers:test-driven-development", ponytail mode, how to run backend + iOS locally, where secrets come from.
- **backend/CLAUDE.md**: stack, `npm test` / `npm run dev` / `npm run db:migrate` / `wrangler deploy`, env var list, layout above, testing conventions (msw for HTTP, pglite for DB, no network in tests), pipeline status rules.
- **ios/CLAUDE.md**: Xcode scheme, `apollo-ios-cli generate`, when to regenerate (after any backend schema change, export with `npm run schema:export`), test command (`xcodebuild test -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16'`), Keychain/token rules.

## Ops (one-time, manual, documented in backend/CLAUDE.md)

1. RunPod GPU pod running `ghcr.io/debpalash/voicestudio:stable`, volume at `/app/omnivoice_data`, `OMNIVOICE_SERVER_MODE=1`, `OMNIVOICE_API_KEY`, HTTPS via RunPod proxy. VoiceStudio is AGPL; we run it unmodified behind our API.
2. Neon project + connection string. 3. R2 bucket + S3 access key. 4. Apple Services ID / Sign in with Apple capability. 5. `wrangler secret put` for all of the above + `OPENAI_API_KEY`.

## Build order (each becomes a task group in the implementation plan)

1. Scaffold: monorepo, three CLAUDE.md files, backend with `me`-less health query, Dockerfile, Worker proxy, `wrangler deploy` succeeds. Vitest green.
2. Auth: `signInWithApple`, JWT issue/verify, `me`, context on HTTP and WS.
3. Voice enrollment: R2 client, VoiceStudio client (`createProfile`, `deleteProfile`), `enrollVoice`, `deleteAccount`.
4. Sessions: `createSession` with file upload, pipeline stages, `sessionUpdated` subscription, boot sweeper, `sessions`/`session` queries.
5. iOS: Apollo client + codegen, sign-in, enrollment, record → processing (subscription) → playback, history list.
6. End-to-end against deployed backend with a real VoiceStudio pod.

## Verification

- Backend: `npm test` (unit + resolver tests over pglite with msw stubs for VoiceStudio/OpenAI/R2). A single `npm run smoke` script that signs in with a test JWT, enrolls a voice, creates a session, and waits on the subscription against a running local server with real VoiceStudio.
- iOS: `xcodebuild test` for ViewModel tests. Manual run on simulator against `LOCAL_DEV` backend, then against Cloudflare.
- Deploy: `wrangler deploy`, hit `/graphql` with `{ __typename }`, open a WS and confirm `connection_ack`.

