// apps/mac/TermCastTests/PerformanceTests.swift
import XCTest
@testable import TermCast

// Performance tests use XCTestCase.measure{} alongside Swift Testing in the same bundle.
final class PerformanceTests: XCTestCase {

    // MARK: - RingBuffer throughput

    func testRingBufferWrite1MBThroughput() {
        let buf = RingBuffer(capacity: 65_536)
        let chunk = [UInt8](repeating: 0x41, count: 1024)

        measure {
            for _ in 0..<1024 { buf.write(chunk) }
        }
    }

    func testRingBufferSnapshot64KB() {
        let buf = RingBuffer(capacity: 65_536)
        let data = [UInt8](repeating: 0x42, count: 65_536)
        buf.write(data)

        measure {
            _ = buf.snapshot()
        }
    }

    // MARK: - JWTManager throughput

    func testJWTSign1000Times() {
        let manager = JWTManager(secret: JWTManager.generateSecret())

        measure {
            for _ in 0..<1000 { _ = manager.sign() }
        }
    }

    func testJWTVerify1000Times() {
        let manager = JWTManager(secret: JWTManager.generateSecret())
        let token = manager.sign()

        measure {
            for _ in 0..<1000 { _ = manager.verify(token) }
        }
    }

    // MARK: - WSMessage JSON serialization

    func testWSMessageSerialize1000Times() {
        let id = UUID()
        let data = Data(repeating: 0x41, count: 512)
        let msg = WSMessage.output(sessionId: id, data: data)

        measure {
            for _ in 0..<1000 { _ = msg.json() }
        }
    }

    func testWSMessageDeserialize1000Times() {
        let id = UUID()
        let data = Data(repeating: 0x41, count: 512)
        let json = WSMessage.output(sessionId: id, data: data).json()

        measure {
            for _ in 0..<1000 { _ = WSMessage.from(json: json) }
        }
    }
}
