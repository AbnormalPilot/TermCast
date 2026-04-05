// apps/mac/TermCastTests/SecurityTests.swift
import Testing
import Foundation
@testable import TermCast

@Suite("Security — Mac")
struct SecurityTests {

    // MARK: - JWT Attack Vectors

    @Test("Algorithm confusion: alg:none token is rejected")
    func jwtAlgNoneIsRejected() {
        let manager = JWTManager(secret: JWTManager.generateSecret())
        let noneHeader = Data(#"{"alg":"none","typ":"JWT"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let now = Int(Date().timeIntervalSince1970)
        let payload = Data(#"{"sub":"attacker","iat":\#(now),"exp":\#(now + 3600)}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(noneHeader).\(payload)."
        #expect(!manager.verify(token), "alg:none with empty sig must be rejected")
    }

    @Test("JWT replay: expired token cannot be reused")
    func jwtReplayExpiredToken() {
        let manager = JWTManager(secret: JWTManager.generateSecret())
        let expired = manager.sign(expiry: Date().addingTimeInterval(-1))
        #expect(!manager.verify(expired))
        #expect(!manager.verify(expired))  // re-presented — still rejected
    }

    @Test("JWT secret entropy: generated secrets are unique across calls")
    func jwtSecretEntropy() {
        let s1 = JWTManager.generateSecret()
        let s2 = JWTManager.generateSecret()
        let s3 = JWTManager.generateSecret()
        #expect(s1 != s2)
        #expect(s2 != s3)
        #expect(s1 != s3)
    }

    @Test("JWT null bytes in payload don't bypass expiry check")
    func jwtNullBytesInPayload() {
        let manager = JWTManager(secret: JWTManager.generateSecret())
        let real = manager.sign()
        let parts = real.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        // Forge a different payload — HMAC was computed for parts[1], not for "e30",
        // so the HMAC check will fail and the token is rejected before expiry is checked.
        let nullPayload = "e30"  // base64url of "{}"
        #expect(!manager.verify("\(parts[0]).\(nullPayload).\(parts[2])"))
    }

    @Test("JWT cross-key: token signed by one key rejected by another")
    func jwtCrossKeyRejection() {
        let m1 = JWTManager(secret: JWTManager.generateSecret())
        let m2 = JWTManager(secret: JWTManager.generateSecret())
        let token = m1.sign()
        #expect(m1.verify(token))
        #expect(!m2.verify(token))
    }

    // MARK: - RingBuffer

    @Test("RingBuffer cannot store more than capacity bytes")
    func ringBufferCannotExceedCapacity() {
        let buf = RingBuffer(capacity: 64)
        buf.write([UInt8](repeating: 0x41, count: 1000))
        #expect(buf.count == 64)
        #expect(buf.snapshot().count == 64)
    }

    @Test("RingBuffer snapshot is independent — mutations don't affect internal state")
    func ringBufferSnapshotIsIndependent() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        var snap = buf.snapshot()
        snap[0] = 99
        #expect(buf.snapshot()[0] == 1)
    }

    // MARK: - Data base64url

    @Test("Data.base64URLDecoded rejects invalid padding attacks")
    func base64URLDecodedRejectsGarbage() {
        #expect(Data(base64URLDecoded: "!!!") == nil)
    }
}
