import Foundation

/// Turns a growing, streamed reply into whole sentences for text-to-speech.
public struct SpeechChunker: Sendable {
    private var consumed = 0
    private static let terminators: Set<Character> = [".", "!", "?", "。", "！", "？"]

    public init() {}

    public mutating func take(from fullText: String, final: Bool) -> [String] {
        let chars = Array(fullText)
        if consumed > chars.count { consumed = 0 }
        var out: [String] = []
        var start = consumed
        var i = consumed
        while i < chars.count {
            let ch = chars[i]
            let atEnd = i + 1 == chars.count
            let ends = ch == "\n"
                || (Self.terminators.contains(ch) && (atEnd ? final : chars[i + 1].isWhitespace))
            if ends {
                append(String(chars[start...i]), to: &out)
                start = i + 1
            }
            i += 1
        }
        if final, start < chars.count {
            append(String(chars[start...]), to: &out)
            start = chars.count
        }
        consumed = start
        return out
    }

    private func append(_ raw: String, to out: inout [String]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !SpeechText.clean(trimmed).isEmpty { out.append(trimmed) }
    }
}

public enum SpeechText {
    /// Removes markdown symbols that a speech voice would read aloud.
    public static func clean(_ text: String) -> String {
        var s = text
        for token in ["**", "__", "`", "#", "*"] { s = s.replacingOccurrences(of: token, with: "") }
        s = s.replacingOccurrences(of: " - ", with: " ")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
