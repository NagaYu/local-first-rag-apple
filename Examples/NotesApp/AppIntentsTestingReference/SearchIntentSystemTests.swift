// Reference implementation for system-level verification of
// `SearchLocalIndexIntent` via Apple's `AppIntentsTesting` framework
// (WWDC26 session 295, "Validate your App Intents adoption with
// AppIntentsTesting").
//
// This is not wired into the SwiftPM build: `AppIntentsTesting` ships with
// iOS/macOS 27.0+ and Xcode 27, which — as of this package's initial
// development (July 2026) — is a developer beta not installed in the
// environment this package was built in. I could not compile or run this
// file, so treat it as written faithfully against Apple's published
// documentation and examples, not as empirically verified.
//
// It also cannot live in `Tests/LocalFirstRAGTests` (a plain SwiftPM test
// target): `AppIntentsTesting` runs your intents inside a live, installed
// app process via a UI Testing bundle that talks to it out-of-process
// through the real system App Intents stack — a bare `swift test` binary
// has no such process to attach to. That's also why `SearchLocalIndexIntent`
// itself needs a real app to host it (see `NotesAppApp.swift`); a library
// alone can define an `AppIntent`, but the system only discovers and can
// invoke it once it's registered by an installed app.
//
// To actually run this suite:
//   1. Install Xcode 27+ (currently in beta) and wrap `Sources/NotesApp` in
//      a real Xcode App project (see this directory's README for why the
//      runnable example here is a plain SwiftPM executable instead).
//   2. Add a UI Testing target to that project, using the same code signing
//      team as the app, per CONTRIBUTING.md in the package root.
//   3. Add this file to that UI Testing target and update the bundle
//      identifier below to match your app target's.
//
// #if canImport(AppIntentsTesting) keeps this file inert (compiles to
// nothing) everywhere else, so it can sit in the repository without
// breaking any other build.

#if canImport(AppIntentsTesting)
import AppIntentsTesting
import XCTest

final class SearchIntentSystemTests: XCTestCase {
    let app = XCUIApplication()
    var definitions: IntentDefinitions!

    override func setUp() async throws {
        app.launch()
        // Update to match the real app target's bundle identifier once this
        // is wired into an actual Xcode project.
        definitions = IntentDefinitions(bundleIdentifier: "com.localfirstrag.NotesApp")
    }

    /// The app seeds a Kyoto-trip note with `spotlightVisible: true` on
    /// first launch (see `NotesAppApp.seedExampleNotesIfEmpty`). This drives
    /// `SearchLocalIndexIntent` through the real, out-of-process App Intents
    /// stack — the same path Siri and Shortcuts use — rather than calling
    /// `perform()` directly in-process.
    func testSearchLocalIndexIntentFindsTheSeededKyotoNote() async throws {
        let intent = definitions.intents["SearchLocalIndexIntent"]
        let instance = intent.makeIntent(query: "what did I write about the trip to Kyoto?")
        let result = try await instance.run()

        let values: [String] = try result.value
        XCTAssertTrue(values.contains { $0.contains("Kyoto") })
    }

    /// The app also seeds a `spotlightVisible: false` journal entry on first
    /// launch. This is the privacy-boundary test's system-level counterpart
    /// to `SearchIntentTests.testPerformSearchExcludesDocumentsMarkedSpotlightVisibleFalse`
    /// in `Tests/LocalFirstRAGTests` — that test verifies the intent's logic
    /// directly; this one verifies the same boundary holds when Siri/Shortcuts
    /// actually invokes the intent through the real system.
    func testSearchLocalIndexIntentNeverSurfacesTheExcludedJournalEntry() async throws {
        let intent = definitions.intents["SearchLocalIndexIntent"]
        let instance = intent.makeIntent(query: "difficult week")
        let result = try await instance.run()

        let values: [String] = try result.value
        XCTAssertFalse(values.contains { $0.contains("journal") })
    }
}
#endif
