// apps/ios/TermCastiOS/Views/OfflineView.swift
import SwiftUI

struct OfflineView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Mac Offline")
                .font(.title2.bold())
            Text("TermCast can't reach your Mac.\nMake sure it's running and connected to Tailscale.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
