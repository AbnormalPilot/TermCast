// apps/ios/TermCastiOS/App/TermCastiOSApp.swift
import SwiftUI

@main
struct TermCastiOSApp: App {
    @StateObject private var wsClient = WSClient()
    @StateObject private var sessionStore = SessionStore()
    @State private var isOnboarding = !PairingStore.hasCredentials()
    @State private var isOffline = false

    var body: some Scene {
        WindowGroup {
            contentView
                .onChange(of: wsClient.state) { newState in
                    switch newState {
                    case .offline: isOffline = true
                    case .connected: isOffline = false
                    default: break
                    }
                }
                .task { connect() }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if isOnboarding {
            QRScanView { host, secret in
                try? PairingStore.save(host: host, secret: secret)
                isOnboarding = false
                connect()
            }
        } else if isOffline {
            OfflineView {
                isOffline = false
                connect()
            }
        } else {
            SessionListView(sessionStore: sessionStore, wsClient: wsClient)
        }
    }

    private func connect() {
        guard let creds = try? PairingStore.load() else {
            isOnboarding = true
            return
        }
        wsClient.onMessage = { [weak sessionStore] msg in
            guard let sessionStore else { return }
            Task { @MainActor in
                sessionStore.apply(msg)
            }
            dispatchToTerminals(msg)
        }
        wsClient.connect(host: creds.host, secret: creds.secret)
    }

    private func dispatchToTerminals(_ msg: WSMessage) {
        switch msg.type {
        case .output:
            guard let idStr = msg.sessionId, let id = UUID(uuidString: idStr),
                  let b64 = msg.data, let data = Data(base64Encoded: b64) else { return }
            NotificationCenter.default.post(
                name: .termcastOutput(id),
                object: nil,
                userInfo: ["data": data]
            )
        case .sessionClosed:
            guard let idStr = msg.sessionId, let id = UUID(uuidString: idStr) else { return }
            NotificationCenter.default.post(name: .termcastSessionEnded(id), object: nil)
        case .ping:
            wsClient.send(.pong())
        default: break
        }
    }
}

// MARK: - PairingStore convenience

extension PairingStore {
    static func hasCredentials() -> Bool {
        (try? load()) != nil
    }
}
