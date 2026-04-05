import Foundation

final class PingPong {
    private let onSendPing: () -> Void
    private let onTimeout: () -> Void
    private var timer: Timer?
    private var pongReceived = true

    init(onSendPing: @escaping () -> Void, onTimeout: @escaping () -> Void) {
        self.onSendPing = onSendPing
        self.onTimeout = onTimeout
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.pongReceived { self.onTimeout(); return }
            self.pongReceived = false
            self.onSendPing()
        }
    }

    func didReceivePong() { pongReceived = true }

    func stop() { timer?.invalidate(); timer = nil }
}
