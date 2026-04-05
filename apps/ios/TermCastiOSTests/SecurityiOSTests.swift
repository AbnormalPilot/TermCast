// apps/ios/TermCastiOSTests/SecurityiOSTests.swift
import Testing
import Foundation
@testable import TermCastiOS

@Suite("Security — iOS", .serialized)
struct SecurityiOSTests {

    @Test("PairingStore: clear removes all credential data")
    func pairingStoreClearRemovesAll() throws {
        try PairingStore.save(host: "attacker.ts.net", secret: Data([0xFF, 0xFE]))
        PairingStore.clear()
        #expect(throws: (any Error).self) {
            try PairingStore.load()
        }
    }

    @Test("PairingStore: secret survives round-trip without transformation")
    func pairingStoreRoundTrip() throws {
        let secret = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try PairingStore.save(host: "host.ts.net", secret: secret)
        let loaded = try PairingStore.load()
        #expect(loaded.secret == secret)
        PairingStore.clear()
    }

    @Test("InputHandler: null byte passes through encodeText")
    func inputHandlerNullBytePassthrough() {
        let data = InputHandler.encode(text: "\u{0000}")
        #expect(data == Data([0x00]))
    }

    @Test("InputHandler: ctrl key below 'a' returns empty Data (no injection)")
    func inputHandlerCtrlBelowAReturnsEmpty() {
        #expect(InputHandler.encode(ctrl: "\u{0000}") == Data())
        #expect(InputHandler.encode(ctrl: "1") == Data())
        #expect(InputHandler.encode(ctrl: "!") == Data())
    }

    @Test("WSMessage: from(json:) silently ignores extra unknown fields")
    func wsMessageIgnoresExtraFields() throws {
        let json = #"{"type":"ping","__proto__":"injection","constructor":"attack"}"#
        let msg = try #require(WSMessage.from(json: json))
        #expect(msg.type == .ping)
    }

    @Test("InputHandler: very long text string encodes without crash")
    func inputHandlerLargeTextInput() {
        let large = String(repeating: "A", count: 65536)
        let data = InputHandler.encode(text: large)
        #expect(data.count == 65536)
    }

    @Test("WSMessage from(json:) returns nil for JSON with null type field")
    func wsMessageNullTypeFieldReturnsNil() {
        let json = #"{"type":null}"#
        #expect(WSMessage.from(json: json) == nil)
    }
}
