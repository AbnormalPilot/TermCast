import Testing
@testable import TermCastiOS

@Suite("ReconnectPolicy")
struct ReconnectPolicyTests {
    @Test("First attempt is 1 second")
    func firstAttemptIsOneSecond() {
        let policy = ReconnectPolicy()
        #expect(abs(policy.nextDelay() - 1.0) < 0.01)
    }

    @Test("Doubles each attempt")
    func doublesEachAttempt() {
        let policy = ReconnectPolicy()
        #expect(abs(policy.nextDelay() - 1.0) < 0.01)
        #expect(abs(policy.nextDelay() - 2.0) < 0.01)
        #expect(abs(policy.nextDelay() - 4.0) < 0.01)
        #expect(abs(policy.nextDelay() - 8.0) < 0.01)
    }

    @Test("Caps at 60 seconds")
    func capsAt60Seconds() {
        let policy = ReconnectPolicy()
        var last = 0.0
        for _ in 0..<20 { last = policy.nextDelay() }
        #expect(last <= 60.0)
    }

    @Test("Reset restarts from 1 second")
    func resetRestartsBacking() {
        let policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        #expect(abs(policy.nextDelay() - 1.0) < 0.01)
    }

    // MARK: - MC/DC: nextDelay() cap boundary

    @Test("MC/DC: attempt 5 produces 32s (below cap, not capped)")
    func mcdc_justBelowCap() {
        let policy = ReconnectPolicy()
        for _ in 0..<5 { _ = policy.nextDelay() }
        let delay = policy.nextDelay()
        #expect(abs(delay - 32.0) < 0.01)  // 1 * 2^5 = 32 < 60
    }

    @Test("MC/DC: attempt 6 produces cap exactly (64 > 60 → capped at 60)")
    func mcdc_exactlyAtCap() {
        let policy = ReconnectPolicy()
        for _ in 0..<6 { _ = policy.nextDelay() }
        let delay = policy.nextDelay()
        #expect(abs(delay - 60.0) < 0.01)  // 1 * 2^6 = 64 > 60 → capped
    }

    @Test("After reset, delay sequence restarts identically")
    func afterResetDelayRestarts() {
        let policy = ReconnectPolicy()
        let d1 = policy.nextDelay()
        let d2 = policy.nextDelay()
        policy.reset()
        #expect(abs(policy.nextDelay() - d1) < 0.01)
        #expect(abs(policy.nextDelay() - d2) < 0.01)
    }
}
