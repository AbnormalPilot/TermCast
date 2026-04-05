import Testing
import Foundation
@testable import TermCast

@Suite("JWTManager")
struct JWTManagerTests {
    let manager: JWTManager

    init() {
        let secret = JWTManager.generateSecret()
        manager = JWTManager(secret: secret)
    }

    @Test("Generated secret is 32 bytes")
    func generatedSecretIs32Bytes() {
        let secret = JWTManager.generateSecret()
        #expect(secret.count == 32)
    }

    @Test("Sign and verify round-trip")
    func signAndVerify() {
        let token = manager.sign()
        #expect(manager.verify(token))
    }

    @Test("Token has three dot-separated parts")
    func tokenHasThreeParts() {
        let token = manager.sign()
        #expect(token.split(separator: ".").count == 3)
    }

    @Test("Tampered token fails verification")
    func tamperedTokenFails() {
        let token = manager.sign()
        let tampered = token + "x"
        #expect(!manager.verify(tampered))
    }

    @Test("Wrong secret fails verification")
    func wrongSecretFails() {
        let token = manager.sign()
        let other = JWTManager(secret: JWTManager.generateSecret())
        #expect(!other.verify(token))
    }

    @Test("Expired token fails verification")
    func expiredTokenFails() {
        let token = manager.sign(expiry: Date().addingTimeInterval(-1))
        #expect(!manager.verify(token))
    }
}
