import Foundation
import NIOCore
import NIOWebSocket

/// Fans out session output to all connected WebSocket clients.
actor SessionBroadcaster {
    private var channels: [ObjectIdentifier: any Channel] = [:]

    func add(channel: any Channel) {
        channels[ObjectIdentifier(channel)] = channel
    }

    func remove(channel: any Channel) {
        channels.removeValue(forKey: ObjectIdentifier(channel))
    }

    func broadcast(message: WSMessage) {
        let json = message.json()
        for channel in channels.values {
            var buffer = channel.allocator.buffer(capacity: json.utf8.count)
            buffer.writeString(json)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(NIOAny(frame), promise: nil)
        }
    }

    func broadcastSessionOpened(_ session: Session) {
        broadcast(message: .sessionOpened(session))
    }

    func broadcastSessionClosed(_ id: SessionID) {
        broadcast(message: .sessionClosed(id))
    }

    func broadcastOutput(sessionId: SessionID, data: Data) {
        broadcast(message: .output(sessionId: sessionId, data: data))
    }

    var clientCount: Int { channels.count }
}
