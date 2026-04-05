import Foundation

/// Thread-unsafe 64KB circular byte buffer.
/// Callers must synchronise access (e.g. within an actor).
final class RingBuffer {
    private var storage: [UInt8]
    private let capacity: Int
    private var head: Int = 0   // index of oldest valid byte
    private var tail: Int = 0   // index of next write position
    private(set) var count: Int = 0

    init(capacity: Int = 65_536) {
        self.capacity = capacity
        self.storage = [UInt8](repeating: 0, count: capacity)
    }

    func write(_ bytes: [UInt8]) {
        for byte in bytes {
            storage[tail] = byte
            tail = (tail + 1) % capacity
            if count == capacity {
                head = (head + 1) % capacity  // evict oldest
            } else {
                count += 1
            }
        }
    }

    /// Returns a contiguous copy of all buffered bytes, oldest first.
    func snapshot() -> [UInt8] {
        guard count > 0 else { return [] }
        var result = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = storage[(head + i) % capacity]
        }
        return result
    }

    func reset() {
        head = 0; tail = 0; count = 0
    }
}
