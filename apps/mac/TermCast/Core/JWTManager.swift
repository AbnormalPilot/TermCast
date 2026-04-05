import CryptoKit
import Foundation
import Security

private struct JWTHeader: Encodable {
    let alg = "HS256"
    let typ = "JWT"
}

private struct JWTPayload: Codable {
    let sub: String
    let iat: Int
    let exp: Int
}

final class JWTManager: Sendable {
    private let key: SymmetricKey

    init(secret: Data) {
        self.key = SymmetricKey(data: secret)
    }

    // MARK: - Secret generation

    static func generateSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: - Sign

    func sign(subject: String = "termcast-client",
              expiry: Date = Date().addingTimeInterval(30 * 24 * 3600)) -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = base64url(encode(JWTHeader()))
        let payload = base64url(encode(JWTPayload(sub: subject, iat: now,
                                                   exp: Int(expiry.timeIntervalSince1970))))
        let message = "\(header).\(payload)"
        let sig = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return "\(message).\(base64url(Data(sig)))"
    }

    // MARK: - Verify

    func verify(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return false }

        // 1. Verify signature
        let message = "\(parts[0]).\(parts[1])"
        let expected = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        guard let actual = Data(base64URLDecoded: parts[2]) else { return false }
        guard Data(expected) == actual else { return false }

        // 2. Verify expiry
        guard let payloadData = Data(base64URLDecoded: parts[1]),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData) else {
            return false
        }
        return Date().timeIntervalSince1970 < Double(payload.exp)
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Data base64url extension

extension Data {
    init?(base64URLDecoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
