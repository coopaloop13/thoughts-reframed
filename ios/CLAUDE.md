# ios

SwiftUI iPhone app for Reframed Thoughts. Swift 6, iOS 17+, Apollo iOS 2.x.

## Commands
- `xcodegen generate` — regenerate `ReframedThoughts.xcodeproj` from `project.yml` (the project file is gitignored; run this after cloning or editing project.yml).
- `xcodebuild test -project ReframedThoughts.xcodeproj -scheme ReframedThoughts -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -quiet CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` — unit tests (Swift Testing). Ad-hoc signing (`CODE_SIGN_IDENTITY=-`) is required so Keychain tests work on the simulator (unsigned builds get -34018) without needing a team; `OS=18.5` is needed when the newest installed runtime has no iPhone 16 (adjust to an installed runtime). CI (`.github/workflows/ci.yml`) runs the same command on `macos-26` with `name=iPhone 17` and no OS pin.
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

## UI standards
Audited against the project `apple-design` and `swiftui-pro` skills (run `/apple-design audit` and `/swiftui-pro audit` before any PR that touches a View). Findings from the 2026-10-15 audit are issues #8–#15.
- Text: Dynamic Type only. Fonts come from text styles (`.body`, `.title2`, `Font.display(.title2)`), never `.system(size:)`; a number that must be big uses `@ScaledMetric`. Serif (`Font.display`) is reserved for words spoken in the person's voice (reframes, chat replies); everything else is system sans. `.caption` is the smallest style; no `.caption2`.
- Buttons: every image button has a text title (`Button("Start recording", systemImage: "mic.fill")`), hidden visually with `.labelStyle(.iconOnly)` when needed. Tap targets are at least 44×44 pt. Tab symbols are the `.fill` variants.
- Colour: only Theme tokens, in both appearances, with contrast ≥4.5:1 for text ≤17 pt (compute it from the colourset hex). One colour means one thing; error text is plain Bark, never red or Clay. Nothing is conveyed by colour alone.
- Bars: no `UITabBarAppearance` / `UINavigationBarAppearance` or other UIKit appearance proxies; style bars with SwiftUI modifiers or leave them to the system.
- Copy: sentence case for buttons and headings; action labels start with a verb and keep their name through the flow; no possessive pronouns ("History", not "My history"); errors say what to do next and never show raw server text. The AI and the voice clone are disclosed in plain words wherever they act (sign-in, enrollment, chat).
- Layout: content stacks cap at `.frame(maxWidth: 600)`; `ignoresSafeArea()` only on backgrounds; no fixed heights that assume a tall phone (iPhone Duo's outer display is short).
- Code: `.task` (not `.onAppear`) to create view models; `FormatStyle` for numbers and dates, never `String(format:)`; shape-style overloads (`.background(color, in: .circle)`) not view arguments; `confirmationDialog` attached to its triggering button; no `import UIKit` alongside SwiftUI.

## Conventions
- TDD: failing test first for every ViewModel/model/service change.
- Views never import Apollo; they use `API` and plain models (`User`, `Session`).
- Voice enrollment takes are 8–20s (`EnrollVoiceViewModel.minimumSeconds`/`maximumSeconds`); the view counts down from 20 and the ViewModel auto-stops at 19.5s so the take is saved; keep `referenceText` readable in ~15s. VoiceStudio's OmniVoice engine ignores our transcript for references over 20s and auto-transcribes with a Whisper model that isn't installed, so a longer take enrolls fine but breaks every later synthesis.
- Theme: semantic colours live in `ReframedThoughts/Resources/Assets.xcassets` (Forest, OnForest, Clay, OnClay, Sand, Surface, Bark, Muted, Border; light+dark) and are exposed in `App/Theme.swift` as `Color.forest` etc., with `Font.display(_:)` (system serif, takes a `Font.TextStyle`; the `CGFloat` overload is only for `@ScaledMetric` countdowns) for spoken words only (#13 removes the remaining title/row uses), `.card()`, and `PrimaryButtonStyle` / `SecondaryButtonStyle` / `RecordButtonStyle`. Never use raw hex or `.blue`-style colours in views; add a colourset and a `Theme.colorNames` entry instead (ThemeTests checks every name exists).
- Any `UNAUTHENTICATED` error → `AppState.signOut()`.
- Dev loop: run the backend (`cd ../backend && npm run dev`), scheme env `API_BASE_URL=http://localhost:8080`. To skip Sign in with Apple on the simulator, put a backend-minted token in `ios/Local.xcconfig` (`DEV_JWT = <token>`, copy from `Local.xcconfig.example`; gitignored). The scheme's `DEV_JWT` env var reads `$(DEV_JWT)` from it, so it survives `xcodegen generate`. Never edit scheme env vars in Xcode: regeneration discards them.
- Turns reuse `SessionStatus`; label REFRAMING as "Thinking…" in chat (`SessionStatus.chatLabel`). The crisis card is never dismissable within a session.
- Config: `API_BASE_URL` env var → else `APIBaseURL` from Info.plist (production Worker URL).
