import Foundation
import Network
import CommonCrypto

enum WSClientState: Equatable {
    case disconnected, connecting, connected, offline, authFailed
}

final class WSClient: ObservableObject {
    @Published private(set) var state: WSClientState = .disconnected
    var onMessage: ((WSMessage) -> Void)?
    var onStateChange: ((WSClientState) -> Void)?

    private var connection: NWConnection?
    private let policy = ReconnectPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var pingPong: PingPong?
    /// Tracks whether the current connect() call has ever reached .ready.
    /// Reset to false on each connect(); set to true on first .ready state.
    /// Used to distinguish auth failures (never connected) from network drops.
    private var didEverConnect = false

    func connect(host: String, secret: Data) {
        reconnectTask?.cancel()
        pingPong?.stop()
        connection?.stateUpdateHandler = nil   // teardown old connection
        connection?.cancel()
        connection = nil
        didEverConnect = false
        let token = buildJWT(secret: secret)
        guard let url = URL(string: "wss://\(host)") else { return }
        let endpoint = NWEndpoint.url(url)
        let params = NWParameters.tls
        if let wsOpts = params.defaultProtocolStack.applicationProtocols.first
            as? NWProtocolWebSocket.Options {
            wsOpts.setAdditionalHeaders([("Authorization", "Bearer \(token)")])
        } else {
            let wsOpts = NWProtocolWebSocket.Options()
            wsOpts.setAdditionalHeaders([("Authorization", "Bearer \(token)")])
            params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)
        }

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        setState(.connecting)

        conn.stateUpdateHandler = { [weak self] newState in
            self?.handleStateUpdate(newState, host: host, secret: secret)
        }
        conn.start(queue: .main)
        receiveLoop(conn)
    }

    func disconnect() {
        reconnectTask?.cancel()
        pingPong?.stop()
        connection?.stateUpdateHandler = nil   // prevent spurious .cancelled → .authFailed
        connection?.cancel()
        connection = nil
        setState(.disconnected)
        policy.reset()
        didEverConnect = false
    }

    func send(_ message: WSMessage) {
        guard let conn = connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        guard let data = message.json().data(using: .utf8) else { return }
        conn.send(content: data, contentContext: context, completion: .idempotent)
    }

    private func handleStateUpdate(_ newState: NWConnection.State, host: String, secret: Data) {
        switch newState {
        case .ready:
            didEverConnect = true
            setState(.connected)
            policy.reset()
            pingPong = PingPong(
                onSendPing: { /* client does not initiate pings */ },
                onTimeout: { [weak self] in self?.scheduleReconnect(host: host, secret: secret) }
            )
            pingPong?.start()
        case .failed, .cancelled:
            // If the connection failed before ever reaching .ready with these credentials,
            // surface .authFailed so the UI can show "Unpair".
            // If a working connection dropped, use .offline + reconnect.
            if !didEverConnect {
                setState(.authFailed)
            } else {
                setState(.offline)
                scheduleReconnect(host: host, secret: secret)
            }
        default:
            break
        }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if error != nil { return }
            if let data, let text = String(data: data, encoding: .utf8),
               let msg = WSMessage.from(json: text) {
                DispatchQueue.main.async {
                    if msg.type == .ping { self?.pingPong?.didReceivePong() }
                    self?.onMessage?(msg)
                }
            }
            self?.receiveLoop(conn)
        }
    }

    private func scheduleReconnect(host: String, secret: Data) {
        let delay = policy.nextDelay()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.connect(host: host, secret: secret)
        }
    }

    private func setState(_ newState: WSClientState) {
        state = newState
        onStateChange?(newState)
    }

    private func buildJWT(secret: Data) -> String {
        let header = base64url(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 30 * 24 * 3600
        let payloadStr = "{\"sub\":\"termcast-client\",\"iat\":\(now),\"exp\":\(exp)}"
        let payload = base64url(Data(payloadStr.utf8))
        let msg = "\(header).\(payload)"
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        msg.withCString { msgPtr in
            secret.withUnsafeBytes { keyPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyPtr.baseAddress, secret.count,
                       msgPtr, strlen(msgPtr), &digest)
            }
        }
        return "\(msg).\(base64url(Data(digest)))"
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
