import SwiftUI

struct OfflineView: View {
    let onRetry: () -> Void
    /// When non-nil, an "Unpair — Scan QR again" button is shown below Retry.
    /// Pass a closure only when the connection failed before ever authenticating.
    var onUnpair: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Mac Offline")
                .font(.title2.bold())

            Text("TermCast could not reach your Mac.\nMake sure both devices are on Tailscale.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Retry") { onRetry() }
                .buttonStyle(.borderedProminent)

            if let onUnpair {
                Button("Unpair — Scan QR again") { onUnpair() }
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding()
    }
}
