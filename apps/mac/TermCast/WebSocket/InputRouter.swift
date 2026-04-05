import Foundation

/// Routes WebSocket client input messages to the correct PTYSession.
struct InputRouter {
    private let registry: SessionRegistry

    init(registry: SessionRegistry) {
        self.registry = registry
    }

    func route(sessionId: SessionID, bytes: Data) async {
        await registry.session(id: sessionId)?.write(bytes: bytes)
    }
}
