# Contributing

Thanks for considering a contribution to `local-first-rag-apple`.

## Building and testing

Standard SwiftPM:

```sh
swift build
swift test
```

Requires a full Xcode installation (not just the standalone Command Line
Tools) — `SwiftData`'s `@Model` macro, `XCTest`, and `Testing` all ship as
part of Xcode's toolchain rather than the CLT-only SDK. If `swift build`
fails with errors like *"plugin for module 'SwiftDataMacros' not found"* or
*"no such module 'XCTest'"*, point the toolchain at Xcode explicitly rather
than changing your global `xcode-select`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The `Examples/NotesApp` package builds and runs independently:

```sh
cd Examples/NotesApp
swift run
```

## Test suite layout

- `ChunkingTests`, `EmbeddingTests`, `SearchTests` — pure unit tests (fixture vectors, real `NLEmbedding` output) with no SwiftData dependency.
- `LocalIndexTests` — `add`/`update`/`remove`/`search` semantics, ranking, and a persistence-reopen test, using a temp directory per test.
- `SpotlightSyncTests` — the `spotlightVisible` privacy boundary against a recording test double (`RecordingSearchableIndexClient`), not the real system Spotlight index. See "Why not test against the real Core Spotlight index?" below.
- `SearchIntentTests` — `SearchLocalIndexIntent`'s search logic, called directly rather than through `@Dependency`. See "Testing App Intents" below.

## Why not test against the real Core Spotlight index?

Two things were verified empirically while building this package, from a plain `swift test` process (no app bundle, no code signing identity):

1. `CSSearchableIndex.default().indexSearchableItems(...)` reports success.
2. A real `CSSearchQuery` round-trip against the same index afterward returns nothing.

In other words, Core Spotlight silently accepts the call but doesn't make the item queryable without a properly identified, installed app. That makes a live round-trip test both slow (eventual consistency) and not actually meaningful outside a real app context. Instead, `SpotlightSyncTests` verifies the actual privacy boundary directly: whether `LocalIndex.add`/`update`/`remove` ever calls `indexSearchableItems` for an excluded document. That's a precise, deterministic check of the real mechanism the boundary depends on, and it runs in milliseconds in CI.

## Testing App Intents

`SearchLocalIndexIntent` uses AppIntents' `@Dependency`/`AppDependencyManager`
mechanism to reach a host app's `LocalIndex`. That resolution only works
inside the real intent-perform flow (an app actually running, invoked by
Siri/Shortcuts or a UI test) or within `AppIntentsTesting` — calling
`intent.perform()` directly from a plain unit test traps with *"AppDependency
... was not initialized prior to access."* `SearchIntentTests` therefore
tests the intent's logic through a separate method (`performSearch`) that
takes the index as a plain parameter, which is real, fast, and CI-friendly,
but doesn't exercise the real dependency-injection or Siri-invocation path.

Full system-level verification — a real app process, the real
`@Dependency` resolution, and the real App Intents stack Siri and Shortcuts
use — requires Apple's **`AppIntentsTesting`** framework
(`import AppIntentsTesting`, WWDC26 session 295), via
`Examples/NotesApp/AppIntentsTestingReference/SearchIntentSystemTests.swift`.
This needs:

- **A real device or simulator with a live app process** — `AppIntentsTesting` tests run in a UI Testing bundle, out-of-process, against your app actually running. It is not "headless" in the sense of requiring zero Apple runtime, but it *is* fully automatable in CI once available (no UI taps or screen automation — `xcodebuild test` against a booted simulator is enough).
- **Xcode 27+ / the iOS or macOS 27 SDK.** `AppIntentsTesting` shipped alongside the "27" OS generation announced at WWDC26. As of this package's initial development (July 2026), that's a developer beta not installed in the environment this package was built and tested in — so the reference file above is written faithfully against Apple's published documentation and examples, but has not been compiled or run. If you have Xcode 27+ available, wiring it into a real Xcode project (see `Examples/NotesApp/README.md`) and confirming it compiles/passes is a genuinely useful contribution.
- **A real Xcode app project**, not a plain SwiftPM package — `AppIntentsTesting` needs a UI Testing target with "target application" linkage to a real, installed app, which SwiftPM doesn't model.

CI (`.github/workflows/ci.yml`) runs the core package's `swift build`/`swift test` — which needs neither of the above — as the required job. There is deliberately no CI job for the `AppIntentsTesting` suite yet, since it can't run anywhere in this repository as currently structured (no checked-in `.xcodeproj`).

## Code style

- No `try!`, `as!`, or force-unwraps in the public API surface.
- Async, actor-isolated APIs throughout `LocalIndex` — avoid introducing blocking or completion-handler-based entry points.
- No network calls, no telemetry, anywhere in the package.
