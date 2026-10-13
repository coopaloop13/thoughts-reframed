# ios

SwiftUI iPhone app for Reframed Thoughts. Swift 6, iOS 17+, Apollo iOS 2.x.

## Commands
- `xcodegen generate` — regenerate `ReframedThoughts.xcodeproj` from `project.yml` (the project file is gitignored; run this after cloning or editing project.yml).
- `xcodebuild test -project ReframedThoughts.xcodeproj -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -quiet CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` — unit tests (Swift Testing). Ad-hoc signing (`CODE_SIGN_IDENTITY=-`) is required so Keychain tests work on the simulator (unsigned builds get -34018) without needing a team; `OS=18.5` is needed when the newest installed runtime has no iPhone 16 (adjust to an installed runtime).
- `Tools/apollo-ios-cli generate` — regenerate GraphQL code into `ReframedThoughts/Generated/` from `../backend/schema.graphql` and `ReframedThoughts/GraphQL/*.graphql`. Run after `cd ../backend && npm run schema:export`. Install the CLI once: `swift package --package-path Tools resolve && tar -xzf Tools/.build/checkouts/apollo-ios/CLI/apollo-ios-cli.tar.gz -C Tools`, then verify with `Tools/apollo-ios-cli --version` (the `apollo-cli-install` plugin fails under the sandbox).
- After a backend schema change: `cd ../backend && npm run schema:export && cd ../ios && Tools/apollo-ios-cli generate && xcodegen generate`.
- Open in Xcode: `open ReframedThoughts.xcodeproj`. Set `DEVELOPMENT_TEAM` in project.yml for device builds.

## Layout
- `ReframedThoughts/App/` — `ReframedThoughtsApp`, `RootView` (routing), `AppState` (token + user), `AppConfig` (base URL).
- `ReframedThoughts/Network/` — `API` (struct of async closures; the only seam), `API+Live` (Apollo implementation), `ApolloClientFactory`, `TokenStore` (Keychain).
- `ReframedThoughts/Features/{Auth,Enroll,Record,History,Settings}/` — a View (and a ViewModel where there is logic) per feature.
- `ReframedThoughts/Services/` — `AudioRecorder`, `AudioPlayer`.
- `ReframedThoughts/GraphQL/*.graphql` — operations. `ReframedThoughts/Generated/` — codegen output (never edit).
- `ReframedThoughtsTests/` — Swift Testing; ViewModels are tested with `API.stub(...)`.

## Conventions
- TDD: failing test first for every ViewModel/model/service change.
- Views never import Apollo; they use `API` and plain models (`User`, `Session`).
- Any `UNAUTHENTICATED` error → `AppState.signOut()`.
- Dev loop: run the backend (`cd ../backend && npm run dev`), scheme env `API_BASE_URL=http://localhost:8080`. To skip Sign in with Apple on the simulator, enable the `DEV_JWT` scheme variable with a token minted by the backend (`node -e` using `signUserToken`, see backend/CLAUDE.md).
- Config: `API_BASE_URL` env var → else `APIBaseURL` from Info.plist (production Worker URL).
