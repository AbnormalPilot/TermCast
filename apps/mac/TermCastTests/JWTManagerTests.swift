import Testing
import Foundation
@testable import TermCast

@Suite("JWTManager", .serialized)
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

    @Test("generateSecret produces unique values")
    func generateSecretIsUnique() {
        let s1 = JWTManager.generateSecret()
        let s2 = JWTManager.generateSecret()
        #expect(s1 != s2)
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
        let token = manager.sign(expiry: Date().addingTimeInterval(-10))
        #expect(!manager.verify(token))
    }

    @Test("Token from different manager fails verification")
    func differentManagerFails() {
        let other = JWTManager(secret: JWTManager.generateSecret())
        let token = other.sign()
        #expect(!manager.verify(token))
    }

    @Test("Empty string fails verification")
    func emptyStringFails() {
        #expect(!manager.verify(""))
    }

    // MARK: - MC/DC: verify() — guard 1: parts.count == 3

    @Test("MC/DC: token with only 1 part (parts.count guard)")
    func mcdc_onePartToken() {
        #expect(!manager.verify("onlyonepart"))
    }

    @Test("MC/DC: token with only 2 parts (parts.count guard)")
    func mcdc_twoPartToken() {
        #expect(!manager.verify("header.payload"))
    }

    @Test("MC/DC: token with 4 parts (parts.count guard — upper bound)")
    func mcdc_fourPartToken() {
        let real = manager.sign()
        let parts = real.split(separator: ".")
        #expect(!manager.verify("\(parts[0]).\(parts[1]).\(parts[2]).extra"))
    }

    // MARK: - MC/DC: verify() — guard 2: sig data decode

    @Test("MC/DC: non-base64url signature (sig decode guard)")
    func mcdc_nonBase64Signature() {
        let real = manager.sign()
        let parts = real.split(separator: ".", omittingEmptySubsequences: false)
        #expect(!manager.verify("\(parts[0]).\(parts[1]).not valid base64!!!"))
    }

    // MARK: - MC/DC: verify() — guard 3: HMAC validity

    @Test("MC/DC: valid sig but flipped payload bit (HMAC guard)")
    func mcdc_flippedPayloadBit() {
        let real = manager.sign()
        var parts = real.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        parts[1] = String(parts[1].dropFirst()) + "A"
        #expect(!manager.verify(parts.joined(separator: ".")))
    }

    @Test("MC/DC: valid format but different-key signed token (HMAC guard — cross-key)")
    func mcdc_crossKeyFails() {
        let secret = JWTManager.generateSecret()
        let mgr = JWTManager(secret: secret)
        let token = mgr.sign()
        #expect(mgr.verify(token))
        #expect(!manager.verify(token))
    }

    // MARK: - MC/DC: verify() — guard 4: payload data decode

    @Test("MC/DC: non-base64url payload (payload decode guard)")
    func mcdc_nonBase64Payload() {
        let real = manager.sign()
        let parts = real.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let fakePayload = "!!!invalid!!!"
        #expect(!manager.verify("\(parts[0]).\(fakePayload).\(parts[2])"))
    }

    // MARK: - MC/DC: verify() — guard 5: expiry

    @Test("MC/DC: token expired exactly 1 second ago (expiry guard)")
    func mcdc_expiredByOneSecond() {
        let token = manager.sign(expiry: Date().addingTimeInterval(-1))
        #expect(!manager.verify(token))
    }

    @Test("MC/DC: token expires in 1 second — still valid (expiry guard boundary)")
    func mcdc_expiresInOneSec() {
        let token = manager.sign(expiry: Date().addingTimeInterval(1))
        #expect(manager.verify(token))
    }
}
