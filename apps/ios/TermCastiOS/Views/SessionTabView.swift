// apps/ios/TermCastiOS/Views/SessionTabView.swift
import SwiftUI

struct SessionTabView: View {
    let session: Session
    let wsClient: WSClient
    @State private var pendingOutput: Data?
    @State private var isEnded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TerminalView(
                sessionId: session.id,
                pendingOutput: $pendingOutput,
                onInput: { bytes in
                    wsClient.send(.input(sessionId: session.id, bytes: bytes))
                },
                onResize: { cols, rows in
                    wsClient.send(.resize(sessionId: session.id, cols: cols, rows: rows))
                }
            )
            .ignoresSafeArea()

            if isEnded {
                VStack {
                    HStack {
                        Spacer()
                        Text("Session ended")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding()
                    }
                    Spacer()
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .termcastOutput(session.id))
        ) { notif in
            if let data = notif.userInfo?["data"] as? Data {
                pendingOutput = data
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .termcastSessionEnded(session.id))
        ) { _ in
            isEnded = true
        }
        .navigationTitle("\(session.termApp) — \(session.shell)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static func termcastOutput(_ id: SessionID) -> Notification.Name {
        Notification.Name("termcast.output.\(id.uuidString)")
    }
    static func termcastSessionEnded(_ id: SessionID) -> Notification.Name {
        Notification.Name("termcast.sessionEnded.\(id.uuidString)")
    }
}
