// apps/ios/TermCastiOS/Terminal/TerminalView.swift
import SwiftUI
import SwiftTerm

struct TerminalView: UIViewRepresentable {
    let sessionId: SessionID
    @Binding var pendingOutput: Data?
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let termView = SwiftTerm.TerminalView(frame: .zero)
        termView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        context.coordinator.termView = termView
        termView.inputAccessoryView = context.coordinator.toolbar
        return termView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        if let data = pendingOutput {
            data.withUnsafeBytes { ptr in
                let bytes = Array(ptr.bindMemory(to: UInt8.self))
                uiView.feed(byteArray: ArraySlice(bytes))
            }
            DispatchQueue.main.async { self.pendingOutput = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    final class Coordinator: NSObject {
        let onInput: (Data) -> Void
        let onResize: (Int, Int) -> Void
        weak var termView: SwiftTerm.TerminalView?
        lazy var toolbar = KeyboardToolbarView(coordinator: self)

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func send(_ bytes: Data) {
            onInput(bytes)
        }
    }
}
