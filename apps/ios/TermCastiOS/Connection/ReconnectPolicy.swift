import Foundation

final class ReconnectPolicy {
    private var attempt: Int = 0
    private let base: Double = 1.0
    private let cap: Double = 60.0

    func nextDelay() -> TimeInterval {
        let delay = min(base * pow(2.0, Double(attempt)), cap)
        attempt += 1
        return delay
    }

    func reset() {
        attempt = 0
    }
}
