# Reframed Thoughts

Speak a negative thought; get it back as an affirmation in a clone of your own voice.

- `backend/` — Node/TypeScript GraphQL API, Docker image on Cloudflare Containers. See `backend/CLAUDE.md`.
- `ios/` — SwiftUI app using Apollo iOS. See `ios/CLAUDE.md`.
- `docs/superpowers/specs/` — design specs. `docs/superpowers/plans/` — implementation plans.

## Rules
- Every change is TDD via the superpowers:test-driven-development skill: failing test first.
- Ponytail mode is on: smallest working change, reuse before writing, stdlib before deps.
- Secrets never go in the repo. Backend reads env vars (`backend/.env.example`); production uses `wrangler secret put`.

## Run locally
- Backend: `cd backend && cp .env.example .env` (fill in) `&& npm run dev` → http://localhost:8080/graphql
- iOS: `cd ios && xcodegen generate && open ReframedThoughts.xcodeproj`. The scheme's `API_BASE_URL` env var (enabled by default, `http://localhost:8080`) selects the local backend; `DEV_JWT` (disabled by default) skips Sign in with Apple on the simulator.
