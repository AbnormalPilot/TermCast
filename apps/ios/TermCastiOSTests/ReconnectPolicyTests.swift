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
}
