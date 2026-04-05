// apps/ios/TermCastiOS/Sessions/SessionStore.swift
import Foundation

enum SessionState {
    case active
    case ended   // session closed, history preserved for scroll
}

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var states: [SessionID: SessionState] = [:]

    // MARK: - Updates from WebSocket messages

    func apply(_ message: WSMessage) {
        switch message.type {
        case .sessions:
            sessions = message.sessions ?? []
            for s in sessions { states[s.id] = .active }

        case .sessionOpened:
            if let session = message.session {
                if !sessions.contains(where: { $0.id == session.id }) {
                    sessions.append(session)
                }
                states[session.id] = .active
            }

        case .sessionClosed:
            if let idStr = message.sessionId, let id = UUID(uuidString: idStr) {
                states[id] = .ended
                // Don't remove — keep tab open for scroll history
            }

        default: break
        }
    }

    func state(for id: SessionID) -> SessionState {
        states[id] ?? .ended
    }
}
