// apps/ios/TermCastiOS/Terminal/InputHandler.swift
import Foundation

enum SpecialKey {
    case escape, tab, arrowUp, arrowDown, arrowLeft, arrowRight
}

enum InputHandler {
    /// Encode plain text input
    static func encode(text: String) -> Data {
        Data(text.utf8)
    }

    /// Encode Ctrl+letter (a–z) → control character (0x01–0x1a)
    static func encode(ctrl letter: Character) -> Data {
        let lower = letter.lowercased().first ?? letter
        guard let ascii = lower.asciiValue, ascii >= 97 && ascii <= 122 else { return Data() }
        return Data([ascii - 96])  // 'a'=0x61 → 0x01, 'c'=0x63 → 0x03
    }

    /// Encode special keys as ANSI escape sequences
    static func encode(special key: SpecialKey) -> Data {
        switch key {
        case .escape:     return Data([0x1b])
        case .tab:        return Data([0x09])
        case .arrowUp:    return Data([0x1b, 0x5b, 0x41])  // ESC[A
        case .arrowDown:  return Data([0x1b, 0x5b, 0x42])  // ESC[B
        case .arrowRight: return Data([0x1b, 0x5b, 0x43])  // ESC[C
        case .arrowLeft:  return Data([0x1b, 0x5b, 0x44])  // ESC[D
        }
    }
}
