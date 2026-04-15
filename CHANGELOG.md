# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-04-15

### Changed

- **Now depends on [`a2a-client-swift`](https://github.com/tolgaki/a2a-client-swift)** (from `1.0.22`) instead of the intermediate `a2a-swift` package. The intermediate package was a rename experiment that didn't pan out; `a2a-client-swift` is the canonical Swift A2A client, and this package depends on it directly for wire types.
- All `import A2ACore` statements replaced with `import A2AClient`.
- `Server/A2AServer.swift` uses `@_exported import A2AClient` so consumers importing `A2AServer` get the wire types (Message, AgentCard, A2ATask, etc.) transitively with one import.
- No API changes to any `A2AServer` public types — this is a dependency-graph restructure only.

### Consumers

If you were on `1.1.0`:

```swift
// Before — still works but pulls an extra hop through a2a-swift
.package(url: "https://github.com/tolgaki/a2a-swift-server.git", from: "1.1.0"),

// After — same URL, new version pin
.package(url: "https://github.com/tolgaki/a2a-swift-server.git", from: "1.2.0"),
```

No source code changes required.

## [1.1.0] - 2026-04-15

Initial release. Depended on the (now-retired) `a2a-swift 1.2.0` for wire types. Superseded by 1.2.0 which depends directly on `a2a-client-swift`.

[1.2.0]: https://github.com/tolgaki/a2a-swift-server/releases/tag/1.2.0
[1.1.0]: https://github.com/tolgaki/a2a-swift-server/releases/tag/1.1.0
