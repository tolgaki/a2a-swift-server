# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-04-15

Initial release. The server runtime was moved out of `a2a-swift 1.1.0` into its own package so that client-only consumers (iOS apps importing `A2AClient`) no longer pull Hummingbird + SwiftNIO + ~20 transitive packages through their SPM graph.

### Added

- `A2AServer` target, lifted unchanged from `a2a-swift 1.1.0`.
- Depends on `a2a-swift 1.2.0` for `A2ACore` wire types.
- Depends on `hummingbird 2.5+` for the HTTP server runtime.
- Interop tests (`A2AInteropTests`) that boot the server in-process and run the client against it over both REST and JSON-RPC — 17 tests, all green.
- 5 server example executables: `EchoAgent`, `CustomHandler`, `StreamingAgent`, `PushNotificationsAgent`, `MultiAgent`.

### Migration from `a2a-swift 1.1.0`

Consumers who were importing `A2AServer` from `a2a-swift`:

```swift
// Before
.package(url: "https://github.com/tolgaki/a2a-swift.git", from: "1.1.0"),
.target(name: "MyServer", dependencies: [
    .product(name: "A2AServer", package: "a2a-swift")
])

// After
.package(url: "https://github.com/tolgaki/a2a-swift-server.git", from: "1.1.0"),
.target(name: "MyServer", dependencies: [
    .product(name: "A2AServer", package: "a2a-swift-server")
])
```

All other API surfaces (`A2AHandler`, `A2AServer` actor, stores, authenticators) are unchanged. `a2a-swift-server` transitively re-exports `A2ACore` so `import A2AServer` still gives you the wire types.

[1.1.0]: https://github.com/tolgaki/a2a-swift-server/releases/tag/1.1.0
