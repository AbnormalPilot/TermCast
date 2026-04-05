import Foundation
import Security

struct PairingCredentials {
    let host: String
    let secret: Data
}

enum PairingStore {
    private static let service = "com.termcast.ios"
    private static let hostKey = "termcast-host"
    private static let secretKey = "termcast-secret"

    static func save(host: String, secret: Data) throws {
        try keychainSave(key: hostKey, data: Data(host.utf8))
        try keychainSave(key: secretKey, data: secret)
    }

    static func load() throws -> PairingCredentials {
        let hostData = try keychainLoad(key: hostKey)
        let secret = try keychainLoad(key: secretKey)
        guard let host = String(data: hostData, encoding: .utf8) else {
            throw PairingError.invalidData
        }
        return PairingCredentials(host: host, secret: secret)
    }

    static func clear() {
        keychainDelete(key: hostKey)
        keychainDelete(key: secretKey)
    }

    private static func keychainSave(key: String, data: Data) throws {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw PairingError.keychainError(status) }
    }

    private static func keychainLoad(key: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw PairingError.notFound
        }
        return data
    }

    private static func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum PairingError: Error {
    case notFound
    case invalidData
    case keychainError(OSStatus)
}
