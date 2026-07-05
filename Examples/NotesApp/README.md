# NotesApp (example)

A minimal notes app demonstrating `LocalFirstRAG`'s three surfaces from one index: in-app semantic search, system Spotlight, and Siri/Shortcuts.

## What this is

This example is a plain SwiftPM executable (`swift run`), not an Xcode `.app` project — deliberately, so it's runnable with just `swift run` and no project-file setup. That scope choice has a real consequence: **full system Spotlight searchability and Siri invocation require an actual installed, signed `.app` bundle**, which a bare SwiftPM executable isn't. This was verified directly while building this package: `CSSearchableIndex.indexSearchableItems` reports success even from an unsigned command-line process, but a real `CSSearchQuery` round-trip against it returns nothing — Spotlight only serves query results for content indexed by a properly identified app.

So, what you get by running this example directly:

- ✅ In-app semantic search (`ContentView`), backed by a real `LocalIndex`
- ✅ Adding notes with the `spotlightVisible` toggle (`AddNoteView`) — you can confirm in code/logs that excluded notes are never handed to Core Spotlight (see `LocalFirstRAG`'s own `SpotlightSyncTests` for the automated version of this check)
- ✅ `SearchLocalIndexIntent` registered via `AppDependencyManager` and `NotesAppShortcuts: AppShortcutsProvider` — the real wiring code, compiling and running
- ❌ Not demonstrated live here: the note actually showing up in system Spotlight search, or "Hey Siri, search my notes in NotesApp" actually working — both need the steps below

## Running it

```sh
cd Examples/NotesApp
swift run
```

Seeds two example notes on first launch: a Kyoto trip note (`spotlightVisible: true`) and a private journal entry (`spotlightVisible: false`) — search for "Kyoto" or "difficult week" to see both, then check that only the Kyoto note would reach Spotlight/Siri.

## Turning this into a full Xcode app (for real Spotlight/Siri verification)

1. Create a new Xcode project: **File → New → Project → App** (SwiftUI, Swift).
2. Add `LocalFirstRAG` as a local Swift package dependency pointing at the repository root (`../..`).
3. Add the four files in `Sources/NotesApp/` to the app target.
4. Build and run on a device or simulator. Add a note, then:
   - Pull down system Spotlight and search for its content — it should appear (unless you left "Include in Spotlight & Siri" unchecked).
   - Ask Siri (or use the Shortcuts app) to "search my notes in NotesApp."
5. To run the `AppIntentsTesting`-based system tests in `AppIntentsTestingReference/SearchIntentSystemTests.swift`:
   - Add a UI Testing target to the project, using the same code signing team as the app (see the package root's `CONTRIBUTING.md`).
   - Add that file to the UI Testing target and update the bundle identifier inside it.
   - This requires **Xcode 27+** (the `AppIntentsTesting` module ships with the iOS/macOS 27 SDK, WWDC26) — a developer beta as of this writing, not installed in the environment this package was built in, so this file is written against Apple's documentation but not empirically compiled or run.
