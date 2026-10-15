# Reframed Thoughts

Speak a negative thought; get it back as an affirmation in a clone of your own voice. A CBT-style therapist agent (`backend/src/agent/`) remembers each person across sessions and can continue in a spoken follow-up chat; crisis language is detected and routed to hotline resources. Design: `docs/superpowers/specs/2026-10-14-therapist-agent-design.md`.

- `backend/` — Node/TypeScript GraphQL API, Docker image on Cloudflare Containers. See `backend/CLAUDE.md`.
- `ios/` — SwiftUI app using Apollo iOS. See `ios/CLAUDE.md`.
- `docs/superpowers/specs/` — design specs. `docs/superpowers/plans/` — implementation plans.

## Rules
- Every change is TDD via the superpowers:test-driven-development skill: failing test first.
- Ponytail mode is on: smallest working change, reuse before writing, stdlib before deps.
- SOLID: one reason to change per module; extend via the existing seams (`Deps` in backend, `API` in iOS) rather than editing them; depend on those seams, not on concrete clients. No speculative interfaces (ponytail still wins).
- ACID: every multi-row or read-then-write database change runs in one transaction (`db.transaction`), invariants live in schema constraints, and a failed step leaves no partial rows. Side effects (R2, VoiceStudio, pubsub) happen only after the transaction commits.
- Keep this file, `backend/CLAUDE.md` and `ios/CLAUDE.md` current: any task that adds a module, convention, error code, env var, or product decision updates the relevant CLAUDE.md in the same commit.
- iOS UI follows the standards in `ios/CLAUDE.md` › UI standards (Dynamic Type, labelled buttons, token colours, disclosure copy). Run `/apple-design audit` and `/swiftui-pro audit` on any PR that touches a View.
- Secrets never go in the repo. Backend reads env vars (`backend/.env.example`); production uses `wrangler secret put`.

## Run locally
- Backend: `cd backend && cp .env.example .env` (fill in) `&& npm run dev` → Docker Compose on http://localhost:8080/graphql (Docker Desktop must be running). Compose also runs a CPU VoiceStudio (`backend/voicestudio/Dockerfile`) so no RunPod pod is needed locally; first synthesis downloads models.
- iOS: `cd ios && xcodegen generate && open ReframedThoughts.xcodeproj`. The scheme's `API_BASE_URL` env var (enabled by default, `http://localhost:8080`) selects the local backend; `DEV_JWT` (disabled by default) skips Sign in with Apple on the simulator.

## Branches and CI
- `main` is production, `staging` is the release candidate, `dev` (default branch) is integration. Work happens on feature branches off `dev`.
- Promotion is PR-only and strictly ordered: feature → `dev` → `staging` → `main`. The only exception is `hotfix/*`, which may PR into `main` and must then also PR into `staging` so `dev` picks it up on the next promotion.
- `.github/workflows/ci.yml` runs on every PR into and push to those three branches: `backend` (typecheck, worker typecheck, vitest), `ios` (xcodegen + xcodebuild test on macos-26), `promotion-guard` (fails PRs that skip a step). All three are required checks in the repo ruleset; no direct pushes, no force-push. The ruleset's admin bypass is for emergencies only.
