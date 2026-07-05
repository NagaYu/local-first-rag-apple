# local-first-rag-apple

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20visionOS%201-lightgrey)](#platform-support)
[![Swift](https://img.shields.io/badge/swift-6.0-orange)](Package.swift)

On-device semantic search for Apple platforms — but the point of this package isn't just in-app search. **The semantic index you build to power search inside your app should also power system Spotlight and Siri/Shortcuts, not just your own UI.** Most on-device RAG setups stop at "search works inside my app." This package's whole reason for existing is that the other two surfaces are sitting right there, unused, once you've already built the first one.

```swift
let index = try LocalIndex(name: "my-notes")

try await index.add(
    id: "note-1",
    text: "Long note content here...",
    spotlightVisible: true   // opt out per document for sensitive content — see Privacy below
)

let results = try await index.search("what did I write about the trip to Kyoto?", topK: 5)
```

From that one `add()` call: the text is chunked, embedded (`NLEmbedding.sentenceEmbedding`, on-device, no model download), persisted in SwiftData, indexed into system Spotlight via Core Spotlight (unless opted out), and made queryable by Siri/Shortcuts through a bundled `AppIntent` — four things from one API surface.

## The privacy boundary — read this before you ship

Not everything you index for in-app search should be visible system-wide. A private journal entry shouldn't turn up in a colleague's screen-share of your Spotlight search, or answer a "Hey Siri" query from whoever's holding your phone.

`spotlightVisible` (default `true`, overridable per document) is the one control this package exposes, and it's a single boundary, not two:

- `spotlightVisible: false` → the document is still chunked, embedded, and fully searchable via `LocalIndex.search()` in your own app.
- It is **never** handed to `CSSearchableIndex` — so it can't appear in system Spotlight.
- It is **also** excluded from results returned by the bundled `SearchLocalIndexIntent` — so it can't be surfaced via Siri or Shortcuts either.

"Excluded from system integration" means both surfaces at once, on purpose — a developer (and a user reasoning about their own privacy) shouldn't have to track two separate flags that happen to usually agree. This is verified by tests that check the actual boundary, not just that the flag exists: [`SpotlightSyncTests.testSpotlightVisibleFalseNeverReachesSearchableIndex`](Tests/LocalFirstRAGTests/SpotlightSyncTests.swift) confirms an excluded document's item is never passed to `CSSearchableIndex.indexSearchableItems`, and [`SearchIntentTests.testPerformSearchExcludesDocumentsMarkedSpotlightVisibleFalse`](Tests/LocalFirstRAGTests/SearchIntentTests.swift) confirms the same for the Siri/Shortcuts path — while both also confirm the excluded document remains fully searchable in-app.

## Why `NLEmbedding`, committed

This package builds directly against `NLEmbedding.sentenceEmbedding(for:)` — not an abstract, swappable "embedding backend." That's a deliberate choice:

- It ships with the OS (iOS 14+, macOS 11+ for sentence embeddings) — no bundled model file, no separate download step your app has to manage.
- It works across a broad device/OS range with no hardware-eligibility gate — unlike Apple Intelligence / Foundation Models features, which require A17 Pro+ or Apple silicon M1+ and are unavailable on a large share of devices still in active use.
- Apple's own documentation explicitly recommends it for this exact use case (semantic similarity / text retrieval — the `NLContextualEmbedding` reference page even says *"For semantic similarity tasks, consider using `NLEmbedding`."*).

Two newer, "maybe better" alternatives were checked during development and deliberately **not** adopted:

- **`NLContextualEmbedding`** (iOS 17+): a transformer-based model, but Apple's own docs steer similarity-search use cases away from it — it produces per-token vectors meant for building custom classifiers, not one comparable vector per sentence.
- **`SpotlightSearchTool`** (WWDC26, `FoundationModels`): lets an on-device LLM query your Spotlight index directly ("RAG in two lines of Swift"). Genuinely interesting, but it requires Apple Intelligence hardware eligibility — exactly the gating this package exists to avoid. Worth watching as that framework matures, but not a fit for a package that wants to run everywhere `NLEmbedding` already does.

One practical consequence of `NLEmbedding.sentenceEmbedding` being a per-language model: a `LocalIndex` is scoped to a single primary language, resolved once (explicitly at `init`, or auto-detected from the first document added) and persisted, since embeddings from different language models aren't comparable vector spaces. See the doc comments on `LocalIndex.init` for details.

## Platform support

| Framework this package depends on | iOS / iPadOS | macOS | Mac Catalyst | visionOS | watchOS / tvOS |
|---|---|---|---|---|---|
| SwiftData (`@Model`) | 17.0 | 14.0 | 17.0 | 1.0 | 10.0 / 17.0 |
| `NLEmbedding.sentenceEmbedding(for:)` | 14.0 | 11.0 | 14.0 | 1.0 | 7.0 / 14.0 |
| Core Spotlight (`CSSearchableItem`/`CSSearchableIndex`) | 9.0 | 10.11 | 13.1 | 1.0 | **not available** |
| App Intents (`AppIntent`/`AppShortcutsProvider`) | 16.0 | 13.0 | 16.0 | since launch | 9.0 / 16.0 |

This package's actual floor is **iOS 17 / macOS 14 / visionOS 1 / Mac Catalyst 17** — set by SwiftData, the highest of the four. Core Spotlight isn't available on watchOS or tvOS at all, and since Spotlight indexing is a required (not optional) part of this package's design, watchOS/tvOS aren't supported targets here, regardless of the other three frameworks' broader reach.

## Scale assumption

There's no SwiftData-native vector index, so search ranks fetched candidates by cosine similarity using Accelerate (vDSP) — a brute-force scan, not an approximate nearest-neighbor index. That's the right tradeoff at the scale this package targets: **thousands, not millions, of chunks** — a personal notes/journal app, not a server-side search engine. If you're indexing more than that, you likely want a different architecture entirely (see Prior art below).

## Example app

[`Examples/NotesApp`](Examples/NotesApp) demonstrates all three surfaces backed by one `LocalIndex`: in-app search, the `spotlightVisible` toggle when adding a note, and the `SearchLocalIndexIntent`/`AppShortcutsProvider` wiring for Siri. It's a plain `swift run`-able SwiftPM executable — see its README for exactly what that does and doesn't demonstrate live (full system Spotlight/Siri registration needs a signed `.app` bundle, which a bare SwiftPM executable isn't) and how to wrap it in a real Xcode project to verify those paths, including the `AppIntentsTesting` system-level test suite.

## Prior art

- [`local-first-rag`](https://github.com/NagaYu/local-first-rag) — this project's browser-based sibling by the same author, which established the on-device RAG design being adapted here. That version is intentionally backend-agnostic (bring your own embedding model) so it works across browsers and non-Apple contexts. This version trades that flexibility for deep, opinionated integration with Apple's own frameworks — a decisive, non-swappable stack instead of a generic one, because the payoff (Spotlight, Siri) only exists if you commit to Apple's frameworks specifically.
- Core Spotlight and App Intents are mature, first-party Apple frameworks this package wires semantic search into — not reimplementations of anything they already do well.
- General-purpose vector databases (Pinecone, Weaviate, pgvector, etc.) solve a different, larger-scale, server-side problem. Not relevant here: this package targets personal-scale, on-device, ecosystem-integrated search, not a production retrieval backend.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), particularly for what the `AppIntentsTesting`-based system test suite needs to actually run.
