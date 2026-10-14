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
- `ReframedThoughts/Features/{Auth,Enroll,Record,Chat,History,Settings}/` — a View (and a ViewModel where there is logic) per feature.
- `Chat/` — `ChatView` + `ChatViewModel` (spoken follow-up turns via `sendTurn` / `watchTurn`), `CrisisCard` (988 / 741741, shown whenever `session.crisis` or any `turn.crisis`).
- `ReframedThoughts/Services/` — `AudioRecorder`, `AudioPlayer`.
- `ReframedThoughts/GraphQL/*.graphql` — operations. `ReframedThoughts/Generated/` — codegen output (never edit).
- `ReframedThoughtsTests/` — Swift Testing; ViewModels are tested with `API.stub(...)`.

## Conventions
- TDD: failing test first for every ViewModel/model/service change.
- Views never import Apollo; they use `API` and plain models (`User`, `Session`).
- Voice enrollment takes are 8–20s (`EnrollVoiceViewModel.minimumSeconds`/`maximumSeconds`); the view counts down from 20 and the ViewModel auto-stops at 19.5s so the take is saved; keep `referenceText` readable in ~15s. VoiceStudio's OmniVoice engine ignores our transcript for references over 20s and auto-transcribes with a Whisper model that isn't installed, so a longer take enrolls fine but breaks every later synthesis.
- Theme: semantic colours live in `ReframedThoughts/Resources/Assets.xcassets` (Forest, OnForest, Clay, OnClay, Sand, Surface, Bark, Muted, Border; light+dark) and are exposed in `App/Theme.swift` as `Color.forest` etc., with `Font.display(_:)` (system serif) for titles/affirmations, `.card()`, and `PrimaryButtonStyle` / `SecondaryButtonStyle` / `RecordButtonStyle`. Never use raw hex or `.blue`-style colours in views; add a colourset and a `Theme.colorNames` entry instead (ThemeTests checks every name exists).
- Any `UNAUTHENTICATED` error → `AppState.signOut()`.
- Dev loop: run the backend (`cd ../backend && npm run dev`), scheme env `API_BASE_URL=http://localhost:8080`. To skip Sign in with Apple on the simulator, put a backend-minted token in `ios/Local.xcconfig` (`DEV_JWT = <token>`, copy from `Local.xcconfig.example`; gitignored). The scheme's `DEV_JWT` env var reads `$(DEV_JWT)` from it, so it survives `xcodegen generate`. Never edit scheme env vars in Xcode: regeneration discards them.
- Turns reuse `SessionStatus`; label REFRAMING as "Thinking…" in chat (`SessionStatus.chatLabel`). The crisis card is never dismissable within a session.
- Config: `API_BASE_URL` env var → else `APIBaseURL` from Info.plist (production Worker URL).
