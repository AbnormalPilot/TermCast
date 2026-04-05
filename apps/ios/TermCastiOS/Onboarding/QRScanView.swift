// apps/ios/TermCastiOS/Onboarding/QRScanView.swift
import SwiftUI
import AVFoundation

struct PairingPayload: Decodable {
    let host: String
    let secret: String   // hex-encoded
}

struct QRScanView: View {
    let onPaired: (String, Data) -> Void
    @State private var cameraError: String?

    var body: some View {
        ZStack {
            if let error = cameraError {
                VStack(spacing: 16) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            } else {
                CameraPreview(onCode: { code in
                    guard let data = code.data(using: .utf8),
                          let payload = try? JSONDecoder().decode(PairingPayload.self, from: data),
                          let secret = Data(hexEncoded: payload.secret) else { return }
                    onPaired(payload.host, secret)
                }, onError: { error in
                    cameraError = error
                })
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text("Scan the QR code shown on your Mac")
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Camera preview using AVFoundation

private struct CameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void
    var onError: ((String) -> Void)?

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.onCode = onCode
        view.onError = onError
        return view
    }

    func updateUIView(_ uiView: CameraView, context: Context) {}
}

private final class CameraView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        if session == nil { setupCamera() }
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.onError?("Camera unavailable. Check permissions in Settings.") }
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        self.previewLayer = layer
        self.session = session

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        session?.stopRunning()
        onCode?(value)
    }
}

// MARK: - Data hex decoding

extension Data {
    init?(hexEncoded hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var idx = chars.startIndex
        while idx < chars.endIndex {
            let nextIdx = chars.index(idx, offsetBy: 2)
            guard let byte = UInt8(String(chars[idx..<nextIdx]), radix: 16) else { return nil }
            bytes.append(byte)
            idx = nextIdx
        }
        self.init(bytes)
    }
}
