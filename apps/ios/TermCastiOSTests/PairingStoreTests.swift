import Testing
import Foundation
@testable import TermCastiOS

@Suite("PairingStore", .serialized)
struct PairingStoreTests {
    init() { PairingStore.clear() }

    @Test("Save and load credentials")
    func saveAndLoad() throws {
        try PairingStore.save(host: "macbook.ts.net", secret: Data([0xAB, 0xCD]))
        let creds = try PairingStore.load()
        #expect(creds.host == "macbook.ts.net")
        #expect(creds.secret == Data([0xAB, 0xCD]))
    }

    @Test("Load throws when empty")
    func loadThrowsWhenEmpty() {
        #expect(throws: (any Error).self) {
            try PairingStore.load()
        }
    }

    @Test("Clear removes credentials")
    func clearRemovesCredentials() throws {
        try PairingStore.save(host: "host", secret: Data([1, 2]))
        PairingStore.clear()
        #expect(throws: (any Error).self) {
            try PairingStore.load()
        }
    }
}
