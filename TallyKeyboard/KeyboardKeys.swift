import UIKit
import CoreText

enum KeyType: Equatable {
    case letter(String)
    case shift
    case delete
    case numbers
    case symbols
    case space
    case `return`
    case globe
    case emoji
    case period
    case comma
}

struct KeyboardLayout {
    // Bottom row mirrors the authentic iOS US layout: mode-switch, emoji, a wide
    // space bar, period, and return. (No globe — iOS provides keyboard switching in
    // its own bottom bar, so a key here would be redundant.)
    static let letterRows: [[KeyType]] = [
        [.letter("Q"), .letter("W"), .letter("E"), .letter("R"), .letter("T"),
         .letter("Y"), .letter("U"), .letter("I"), .letter("O"), .letter("P")],
        [.letter("A"), .letter("S"), .letter("D"), .letter("F"), .letter("G"),
         .letter("H"), .letter("J"), .letter("K"), .letter("L")],
        [.shift, .letter("Z"), .letter("X"), .letter("C"), .letter("V"),
         .letter("B"), .letter("N"), .letter("M"), .delete],
        [.numbers, .emoji, .space, .period, .return]
    ]

    static let numberRows: [[KeyType]] = [
        [.letter("1"), .letter("2"), .letter("3"), .letter("4"), .letter("5"),
         .letter("6"), .letter("7"), .letter("8"), .letter("9"), .letter("0")],
        [.letter("-"), .letter("/"), .letter(":"), .letter(";"), .letter("("),
         .letter(")"), .letter("$"), .letter("&"), .letter("@"), .letter("\"")],
        [.symbols, .letter("."), .letter(","), .letter("?"), .letter("!"),
         .letter("'"), .delete],
        [.letter("ABC"), .emoji, .space, .period, .return]
    ]

    static let symbolRows: [[KeyType]] = [
        [.letter("["), .letter("]"), .letter("{"), .letter("}"), .letter("#"),
         .letter("%"), .letter("^"), .letter("*"), .letter("+"), .letter("=")],
        [.letter("_"), .letter("\\"), .letter("|"), .letter("~"), .letter("<"),
         .letter(">"), .letter("€"), .letter("£"), .letter("¥"), .letter("•")],
        [.numbers, .letter("."), .letter(","), .letter("?"), .letter("!"),
         .letter("'"), .delete],
        [.letter("ABC"), .emoji, .space, .period, .return]
    ]

    /// The full emoji catalog the device can render. See `EmojiCatalog`.
    static var emojis: [String] { EmojiCatalog.all }
}

/// The emoji catalog, grouped into the standard iOS categories.
///
/// Categories and their order come from Unicode's `emoji-test.txt` (bundled as
/// `emoji-categories.txt`, with Smileys + People merged and skin-tone duplicates
/// removed, matching iOS). Each entry is then validated against the device's color
/// font at runtime, so only emoji this OS can actually draw are shown.
enum EmojiCatalog {

    struct Category {
        let name: String
        let symbol: String      // SF Symbol for the category tab
        let emojis: [String]
    }

    /// Computed once, lazily, then cached for the keyboard's lifetime.
    static let categories: [Category] = load()

    /// Flat list (used for warming the cache on a background thread).
    static let all: [String] = categories.flatMap { $0.emojis }

    private static let tabSymbols: [String: String] = [
        "Smileys & People": "face.smiling",
        "Animals & Nature": "pawprint.fill",
        "Food & Drink": "fork.knife",
        "Travel & Places": "airplane",
        "Activities": "soccerball",
        "Objects": "lightbulb.fill",
        "Symbols": "number",
        "Flags": "flag.fill",
    ]

    private static func load() -> [Category] {
        guard let url = Bundle.main.url(forResource: "emoji-categories", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return [Category(name: "Smileys & People", symbol: "face.smiling", emojis: fallback)]
        }

        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 24, nil)
        let emojiFontName = CTFontCopyPostScriptName(font) as String

        // A string is a renderable emoji iff CoreText shapes it into a SINGLE glyph that
        // stays in the emoji font (no fallback) and isn't `.notdef`. Shaping correctly
        // handles surrogate pairs, variation selectors, ZWJ sequences, and flag pairs.
        func renders(_ s: String) -> Bool {
            let attr = NSAttributedString(string: s, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attr)
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1 else { return false }
            let run = runs[0]
            guard CTRunGetGlyphCount(run) == 1 else { return false }
            if let runFont = (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.font] {
                if (CTFontCopyPostScriptName(runFont as! CTFont) as String) != emojiFontName { return false }
            }
            var glyph = CGGlyph(0)
            CTRunGetGlyphs(run, CFRangeMake(0, 1), &glyph)
            return glyph != 0
        }

        var cats: [Category] = []
        var name: String?
        var items: [String] = []
        func flush() {
            if let n = name, !items.isEmpty {
                cats.append(Category(name: n, symbol: tabSymbols[n] ?? "face.smiling", emojis: items))
            }
        }
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("#") {
                flush()
                name = String(line.dropFirst())
                items = []
            } else if renders(line) {
                items.append(line)
            }
        }
        flush()
        return cats.isEmpty
            ? [Category(name: "Smileys & People", symbol: "face.smiling", emojis: fallback)]
            : cats
    }

    /// Used only if the bundled list is missing.
    private static let fallback: [String] = [
        "😀","😂","😍","🥰","😎","😭","😡","👍","🙏","🔥","❤️","🎉","✨","💯","✅","❌"
    ]
}
