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

    @Test("Initial count is zero")
    func initialCountIsZero() {
        let buf = RingBuffer(capacity: 4)
        #expect(buf.count == 0)
    }

    @Test("Write and read back")
    func writeAndReadBack() {
        let buf = RingBuffer(capacity: 8)
        buf.write([1, 2, 3])
        #expect(buf.snapshot() == [1, 2, 3])
        #expect(buf.count == 3)
    }

    @Test("Write single byte increments count")
    func writeSingleByte() {
        let buf = RingBuffer(capacity: 4)
        buf.write([0xFF])
        #expect(buf.count == 1)
        #expect(buf.snapshot() == [0xFF])
    }

    @Test("Write empty slice is a no-op")
    func writeEmptySlice() {
        let buf = RingBuffer(capacity: 4)
        buf.write([])
        #expect(buf.count == 0)
        #expect(buf.snapshot() == [])
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

    // MARK: - MC/DC: write() — count == capacity decision

    @Test("MC/DC: write when buffer is exactly 1 short of capacity (no eviction)")
    func mcdc_noEvictionWhenOneBelowCapacity() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3])                  // count=3, capacity=4 → count < capacity
        #expect(buf.count == 3)
        #expect(buf.snapshot() == [1, 2, 3])  // nothing evicted
    }

    @Test("MC/DC: write exactly fills capacity (boundary — no eviction on fill)")
    func mcdc_fillToCapacityExact() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])               // count hits 4 == capacity on last byte
        #expect(buf.count == 4)
        #expect(buf.snapshot() == [1, 2, 3, 4])
    }

    @Test("MC/DC: one byte over capacity triggers exactly one eviction")
    func mcdc_oneByteOverCapacityEvictsOldest() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        buf.write([5])                         // count == capacity → evict head
        #expect(buf.count == 4)
        #expect(buf.snapshot() == [2, 3, 4, 5])
    }

    @Test("Snapshot is oldest-first across wrap boundary")
    func snapshotAcrossWrapBoundary() {
        let buf = RingBuffer(capacity: 4)
        buf.write([10, 20, 30, 40])
        buf.write([50, 60])                    // wraps: evicts 10, 20
        #expect(buf.snapshot() == [30, 40, 50, 60])
    }

    @Test("Overflow by large chunk keeps capacity bytes")
    func overflowByLargeChunk() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4, 5, 6, 7, 8])  // 8 bytes into cap-4
        #expect(buf.count == 4)
        #expect(buf.snapshot() == [5, 6, 7, 8])
    }
}
