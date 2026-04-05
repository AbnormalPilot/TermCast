import Foundation
import NIOCore
import NIOWebSocket

final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let registry: SessionRegistry
    private let broadcaster: SessionBroadcaster
    private var pingTask: Task<Void, Never>?
    private var pongReceived = true

    init(registry: SessionRegistry, broadcaster: SessionBroadcaster) {
        self.registry = registry
        self.broadcaster = broadcaster
    }

    func channelActive(context: ChannelHandlerContext) {
        Task { [weak self, registry, broadcaster] in
            guard let self else { return }
            let sessions = await registry.allSessions()
            let msg = WSMessage.sessions(sessions)
            self.sendText(msg.json(), context: context)
            await broadcaster.add(channel: context.channel)
            self.startPingLoop(context: context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.opcode == .text else { return }
        var buf = frame.data
        guard let text = buf.readString(length: buf.readableBytes),
              let msg = WSMessage.from(json: text) else { return }
        handle(message: msg, context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        pingTask?.cancel()
        Task { await broadcaster.remove(channel: context.channel) }
    }

    private func handle(message: WSMessage, context: ChannelHandlerContext) {
        switch message.type {
        case .attach:
            guard let idStr = message.sessionId, let id = UUID(uuidString: idStr) else { return }
            Task { [registry] in
                guard let pty = await registry.session(id: id) else { return }
                let snapshot = await pty.bufferSnapshot()
                if !snapshot.isEmpty {
                    let replay = WSMessage.output(sessionId: id, data: snapshot)
                    self.sendText(replay.json(), context: context)
                }
            }
        case .input:
            guard let idStr = message.sessionId,
                  let id = UUID(uuidString: idStr),
                  let b64 = message.data,
                  let bytes = Data(base64Encoded: b64) else { return }
            Task { [registry] in await registry.session(id: id)?.write(bytes: bytes) }
        case .resize:
            guard let idStr = message.sessionId,
                  let id = UUID(uuidString: idStr),
                  let _ = message.cols, let _ = message.rows else { return }
            Task { [registry] in
                guard let pty = await registry.session(id: id) else { return }
                kill(Int32(pty.session.pid), SIGWINCH)
            }
        case .pong:
            pongReceived = true
        default:
            break
        }
    }

    private func startPingLoop(context: ChannelHandlerContext) {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                if !self.pongReceived {
                    context.close(promise: nil); return
                }
                self.pongReceived = false
                self.sendText(WSMessage.ping().json(), context: context)
            }
        }
    }

    func sendText(_ text: String, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        context.writeAndFlush(NIOAny(frame), promise: nil)
    }
}
