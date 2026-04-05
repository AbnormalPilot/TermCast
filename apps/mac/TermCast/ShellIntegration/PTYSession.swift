import Foundation

/// Represents one live terminal session.
/// - Output: reads from named pipe (set up by shell hook's `tee` redirect)
/// - Input: writes to TTY slave device (user-owned, writable by same user)
actor PTYSession {
    let session: Session
    nonisolated(unsafe) private let ringBuffer: RingBuffer
    private var outputTask: Task<Void, Never>?
    private var ttyWriteFD: Int32 = -1

    // Callbacks — set before calling start()
    var onOutput: (@Sendable (Data) -> Void)?
    var onClose: (@Sendable () -> Void)?

    init(session: Session) {
        self.session = session
        self.ringBuffer = RingBuffer()
    }

    // MARK: - Lifecycle

    func start() {
        openTTYForInput()
        startOutputReader()
    }

    func stop() {
        outputTask?.cancel()
        if ttyWriteFD >= 0 { Darwin.close(ttyWriteFD); ttyWriteFD = -1 }
    }

    // MARK: - Input injection

    func write(bytes: Data) {
        guard ttyWriteFD >= 0 else { return }
        bytes.withUnsafeBytes { ptr in
            _ = Darwin.write(ttyWriteFD, ptr.baseAddress!, bytes.count)
        }
    }

    // MARK: - Ring buffer snapshot (for reconnecting clients)

    func bufferSnapshot() -> Data {
        Data(ringBuffer.snapshot())
    }

    // MARK: - Private

    private func openTTYForInput() {
        // The TTY device is owned by the current user — open for write only
        let fd = Darwin.open(session.tty, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        if fd >= 0 { ttyWriteFD = fd }
    }

    private func startOutputReader() {
        let pipePath = session.outPipe
        let buffer = ringBuffer
        let outputCb = onOutput
        let closeCb = onClose

        outputTask = Task.detached(priority: .utility) {
            // Open the named pipe — blocks until shell has it open too
            let fd = Darwin.open(pipePath, O_RDONLY)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd); try? FileManager.default.removeItem(atPath: pipePath) }

            var chunk = [UInt8](repeating: 0, count: 4096)
            while !Task.isCancelled {
                let n = Darwin.read(fd, &chunk, chunk.count)
                if n <= 0 { break }
                let bytes = Array(chunk[0..<n])
                buffer.write(bytes)
                let data = Data(bytes)
                outputCb?(data)
            }
            closeCb?()
        }
    }
}
