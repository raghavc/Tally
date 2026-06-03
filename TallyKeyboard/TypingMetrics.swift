import Foundation

class TypingMetrics {
    private var totalKeystrokes: Int = 0
    private var backspaceCount: Int = 0
    private var characterCount: Int = 0
    private var sessionStartTime: Date?

    func recordKeystroke() {
        if sessionStartTime == nil { sessionStartTime = Date() }
        totalKeystrokes += 1
        characterCount += 1
    }

    func recordBackspace() {
        if sessionStartTime == nil { sessionStartTime = Date() }
        totalKeystrokes += 1
        backspaceCount += 1
    }

    /// Words per minute (1 word = 5 characters)
    var wpm: Double? {
        guard let start = sessionStartTime, characterCount > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(start) / 60.0
        guard elapsed > 0.01 else { return nil } // need at least ~1 second
        return Double(characterCount) / 5.0 / elapsed
    }

    /// Ratio of backspaces to total keystrokes
    var backspaceRate: Double? {
        guard totalKeystrokes > 0 else { return nil }
        return Double(backspaceCount) / Double(totalKeystrokes)
    }

    func reset() {
        totalKeystrokes = 0
        backspaceCount = 0
        characterCount = 0
        sessionStartTime = nil
    }
}
