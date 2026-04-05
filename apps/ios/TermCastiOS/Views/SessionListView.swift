// apps/ios/TermCastiOS/Views/SessionListView.swift
import SwiftUI

struct SessionListView: View {
    @ObservedObject var sessionStore: SessionStore
    let wsClient: WSClient

    var body: some View {
        if sessionStore.sessions.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Active Sessions")
                    .font(.title3.bold())
                Text("Open a terminal on your Mac and\nit will appear here automatically.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        } else {
            TabView {
                ForEach(sessionStore.sessions) { session in
                    SessionTabView(session: session, wsClient: wsClient)
                        .tabItem {
                            Label(session.shell, systemImage: "terminal")
                        }
                        .tag(session.id)
                }
            }
        }
    }
}
