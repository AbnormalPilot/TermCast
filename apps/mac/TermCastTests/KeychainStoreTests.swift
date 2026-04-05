import Testing
import Foundation
@testable import TermCast

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    private let testKey = "test-keychain-\(UUID().uuidString)"

    init() {
        // Ensure clean slate — delete is non-throwing
        KeychainStore.delete(key: testKey)
    }

    @Test("Save and load round-trip")
    func saveAndLoad() throws {
        let data = Data([0xAB, 0xCD, 0xEF])
        try KeychainStore.save(key: testKey, data: data)
        let loaded = try KeychainStore.load(key: testKey)
        #expect(loaded == data)
        KeychainStore.delete(key: testKey)
    }

    @Test("Load missing key throws")
    func loadMissingKeyThrows() {
        #expect(throws: (any Error).self) {
            try KeychainStore.load(key: "nonexistent-\(UUID().uuidString)")
        }
    }

    @Test("Overwrite existing key")
    func overwriteExistingKey() throws {
        try KeychainStore.save(key: testKey, data: Data([0x01]))
        try KeychainStore.save(key: testKey, data: Data([0x02]))
        let loaded = try KeychainStore.load(key: testKey)
        #expect(loaded == Data([0x02]))
        KeychainStore.delete(key: testKey)
    }

    @Test("Delete removes key")
    func deleteRemovesKey() throws {
        try KeychainStore.save(key: testKey, data: Data([0x01]))
        KeychainStore.delete(key: testKey)
        #expect(throws: (any Error).self) {
            try KeychainStore.load(key: testKey)
        }
    }

    @Test("Save and load empty data")
    func saveAndLoadEmptyData() throws {
        try KeychainStore.save(key: testKey, data: Data())
        let loaded = try KeychainStore.load(key: testKey)
        #expect(loaded == Data())
        KeychainStore.delete(key: testKey)
    }

    @Test("Save 32-byte secret (JWT use-case)")
    func save32ByteSecret() throws {
        let secret = JWTManager.generateSecret()
        try KeychainStore.save(key: testKey, data: secret)
        let loaded = try KeychainStore.load(key: testKey)
        #expect(loaded == secret)
        KeychainStore.delete(key: testKey)
    }
}
