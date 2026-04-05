# Regression Test Manifest

Each row maps a previously-fixed bug to the test(s) that would have caught it.

| Bug | Fix | Regression test |
|-----|-----|-----------------|
| JWT alg:none bypass — empty signature accepted | Phase 1 | `SecurityTests.jwtAlgNoneIsRejected` |
| JWT cross-key token accepted | Phase 1 | `JWTManagerTests.mcdc_garbageJSONPayload`, `SecurityTests.jwtCrossKeyRejection` |
| `@Observable` requires iOS 17 — used on iOS 16 target | Phase 2 | `SessionStoreTests` (entire suite — ObservableObject pattern) |
| Double-feed of terminal output (async nil-clear race) | Phase 2 | Cypress: `multiple sequential termWrites do not crash` |
| Off-main-thread NotificationCenter posts | Phase 2 | `SessionViewModelTest.outputFlow emits bytes for correct session` |
| In-place mutation of `@Published` collections | Phase 2 | `SessionStoreTests.apply(.sessions) replaces previous list — immutable assignment` |
| `LocalProcessTerminalView` is macOS-only (used on iOS) | Phase 2 | Build succeeds = regression covered |
| `WSMessageEnvelope.Companion.parse()` — data classes have no Companion | Phase 3 | `WSMessageTest.parseWSMessage returns null for malformed JSON` |
| `XtermBridge.onResize/onReady` self-call StackOverflow | Phase 3 | `XtermBridgeTest.onResize calls callback`, `XtermBridgeTest.onReady calls ready callback` |
| Keychain concurrent access race | Phase 2 | `KeychainStoreTests` (`.serialized` suite), `SecurityiOSTests` (`.serialized` suite) |
| RingBuffer snapshot not isolated — caller mutation affected internal state | Phase 1 | `SecurityTests.ringBufferSnapshotIsIndependent` |
| JWT secret not random — same value across calls | Phase 1 | `JWTManagerTests.generateSecretIsUnique`, `SecurityTests.jwtSecretEntropy` |
