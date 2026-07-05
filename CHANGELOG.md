# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-05

Initial release.

### Added
- `LocalIndex`: async, actor-isolated public API for local semantic search — `add`, `update`, `remove`, `search`.
- SwiftData-backed persistence for documents and chunks, including per-document `spotlightVisible` state.
- Sentence-aware chunking with configurable, documented defaults.
- `NLEmbedding.sentenceEmbedding(for:)`-based embedding, with automatic language detection.
- Accelerate (vDSP)-based cosine similarity ranking over fetched candidates.
- Core Spotlight integration (`SpotlightSync`): indexed documents are searchable system-wide unless `spotlightVisible` is `false`.
- `SearchLocalIndexIntent`: a bundled `AppIntent` making the index queryable via Siri and Shortcuts, respecting the same privacy boundary as Spotlight.
- `Examples/NotesApp`: a demo app showing in-app search, a Spotlight result, and a Siri invocation backed by the same index.
