# Reframed Thoughts

Speak a negative thought; get it back as an affirmation in a clone of your own voice. A CBT-style therapist agent (`backend/src/agent/`) remembers each person across sessions and can continue in a spoken follow-up chat; crisis language is detected and routed to hotline resources. Design: `docs/superpowers/specs/2026-10-14-therapist-agent-design.md`.

- `backend/` — Node/TypeScript GraphQL API, Docker image on Cloudflare Containers. See `backend/CLAUDE.md`.
- `ios/` — SwiftUI app using Apollo iOS. See `ios/CLAUDE.md`.
- `docs/superpowers/specs/` — design specs. `docs/superpowers/plans/` — implementation plans.

## Rules
- Every change is TDD via the superpowers:test-driven-development skill: failing test first.
- Ponytail mode is on: smallest working change, reuse before writing, stdlib before deps.
- Keep this file, `backend/CLAUDE.md` and `ios/CLAUDE.md` current: any task that adds a module, convention, error code, env var, or product decision updates the relevant CLAUDE.md in the same commit.
- Secrets never go in the repo. Backend reads env vars (`backend/.env.example`); production uses `wrangler secret put`.

## Run locally
- Backend: `cd backend && cp .env.example .env` (fill in) `&& npm run dev` → Docker Compose on http://localhost:8080/graphql (Docker Desktop must be running). Compose also runs a CPU VoiceStudio (`backend/voicestudio/Dockerfile`) so no RunPod pod is needed locally; first synthesis downloads models.
- iOS: `cd ios && xcodegen generate && open ReframedThoughts.xcodeproj`. The scheme's `API_BASE_URL` env var (enabled by default, `http://localhost:8080`) selects the local backend; `DEV_JWT` (disabled by default) skips Sign in with Apple on the simulator.
