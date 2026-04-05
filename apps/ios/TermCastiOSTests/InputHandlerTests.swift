// apps/ios/TermCastiOSTests/InputHandlerTests.swift
import Testing
import Foundation
@testable import TermCastiOS

@Suite("InputHandler")
struct InputHandlerTests {
    @Test("plain text passes through as UTF-8")
    func plainTextPassthrough() {
        let bytes = InputHandler.encode(text: "hello")
        #expect(bytes == Data("hello".utf8))
    }

    @Test("Ctrl+C produces ETX (0x03)")
    func ctrlC() {
        let bytes = InputHandler.encode(ctrl: "c")
        #expect(bytes == Data([0x03]))
    }

    @Test("Ctrl+A produces 0x01")
    func ctrlA() {
        let bytes = InputHandler.encode(ctrl: "a")
        #expect(bytes == Data([0x01]))
    }

    @Test("escape produces 0x1b")
    func escape() {
        let bytes = InputHandler.encode(special: .escape)
        #expect(bytes == Data([0x1b]))
    }

    @Test("tab produces 0x09")
    func tab() {
        let bytes = InputHandler.encode(special: .tab)
        #expect(bytes == Data([0x09]))
    }

    @Test("arrow up produces ESC[A")
    func arrowUp() {
        let bytes = InputHandler.encode(special: .arrowUp)
        #expect(bytes == Data([0x1b, 0x5b, 0x41]))
    }

    @Test("arrow down produces ESC[B")
    func arrowDown() {
        let bytes = InputHandler.encode(special: .arrowDown)
        #expect(bytes == Data([0x1b, 0x5b, 0x42]))
    }

    @Test("arrow right produces ESC[C")
    func arrowRight() {
        let bytes = InputHandler.encode(special: .arrowRight)
        #expect(bytes == Data([0x1b, 0x5b, 0x43]))
    }

    @Test("arrow left produces ESC[D")
    func arrowLeft() {
        let bytes = InputHandler.encode(special: .arrowLeft)
        #expect(bytes == Data([0x1b, 0x5b, 0x44]))
    }

    @Test("invalid ctrl character returns empty data")
    func ctrlInvalidCharacter() {
        let bytes = InputHandler.encode(ctrl: "1")
        #expect(bytes == Data())
    }

    // MARK: - MC/DC: encodeCtrl guard — ascii >= 97 && ascii <= 122

    @Test("MC/DC: ctrl 'z' (ascii=122, upper boundary — both conditions true)")
    func mcdc_ctrlZ_upperBoundary() {
        #expect(InputHandler.encode(ctrl: "z") == Data([0x1a]))
    }

    @Test("MC/DC: ctrl backtick (ascii=96, one below lower — first condition false)")
    func mcdc_backtickBelow97_failsFirstCondition() {
        #expect(InputHandler.encode(ctrl: "`") == Data())
    }

    @Test("MC/DC: ctrl brace (ascii=123, one above upper — second condition false)")
    func mcdc_braceAbove122_failsSecondCondition() {
        #expect(InputHandler.encode(ctrl: "{") == Data())
    }

    @Test("MC/DC: ctrl uppercase 'C' — lowercased to 'c' → 0x03")
    func mcdc_ctrlUppercaseC() {
        #expect(InputHandler.encode(ctrl: "C") == Data([0x03]))
    }
}
