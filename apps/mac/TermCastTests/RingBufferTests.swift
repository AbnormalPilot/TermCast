import Testing
@testable import TermCast

@Suite("RingBuffer")
struct RingBufferTests {
    @Test("Empty buffer returns empty snapshot")
    func emptyBufferReturnsEmptySnapshot() {
        let buf = RingBuffer(capacity: 8)
        #expect(buf.snapshot() == [])
        #expect(buf.count == 0)
    }

    @Test("Write and read back")
    func writeAndReadBack() {
        let buf = RingBuffer(capacity: 8)
        buf.write([1, 2, 3])
        #expect(buf.snapshot() == [1, 2, 3])
        #expect(buf.count == 3)
    }

    @Test("Does not exceed capacity — evicts oldest bytes")
    func doesNotExceedCapacity() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4, 5, 6])  // 6 bytes into capacity-4 buffer
        #expect(buf.count == 4)
        #expect(buf.snapshot() == [3, 4, 5, 6])  // oldest two overwritten
    }

    @Test("Wrap-around evicts one oldest byte")
    func wrapAround() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        buf.write([5])             // wraps: evicts 1
        #expect(buf.snapshot() == [2, 3, 4, 5])
    }

    @Test("Reset clears the buffer")
    func reset() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        buf.reset()
        #expect(buf.count == 0)
        #expect(buf.snapshot() == [])
    }

    @Test("Full 64KB capacity round-trip")
    func fullCapacityRoundTrip() {
        let capacity = 65_536
        let buf = RingBuffer(capacity: capacity)
        let input = (0..<capacity).map { UInt8($0 % 256) }
        buf.write(input)
        #expect(buf.snapshot() == input)
        #expect(buf.count == capacity)
    }
}
