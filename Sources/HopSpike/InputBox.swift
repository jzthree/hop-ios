import Foundation
import SwiftTerm

/// The agent's input box on the terminal screen, for typing over a selection
/// made inside it: hop puts the cursor right after the selection (a click
/// where the app reads the mouse — Claude and Codex both move their cursor
/// on one — else an arrow walk), waits for the cursor to land there,
/// deletes as many characters as were selected, then types. The same rules
/// as hop's web client (hay/apps/web/src/utils/inputBox.ts).
///
/// The box: `❯ ` (Claude) or `› ` (Codex) and the text, continuation rows
/// indented two spaces; Claude's sits between two ──── rules, Codex's ends at
/// a blank row. Their wrapping drops the space it breaks at, and a word too
/// long for a row is cut at the right edge.
struct BoxRows: Equatable { let start: Int; let end: Int }

/// Buffer rows; `endCol` is one past the last selected cell.
struct BoxSelection: Equatable { let startRow: Int; let startCol: Int; let endRow: Int; let endCol: Int }

enum InputBox {
    private static func trimmed(_ t: String) -> Substring {
        t.drop(while: { $0.isWhitespace })
    }
    static func isRule(_ t: String) -> Bool {
        let s = trimmed(t)
        return s.prefix(8).count == 8 && s.prefix(8).allSatisfy { $0 == "─" || $0 == "━" }
    }
    static func isPrompt(_ t: String) -> Bool {
        let s = trimmed(t)
        guard let first = s.first, "❯›>".contains(first) else { return false }
        let rest = s.dropFirst()
        return rest.isEmpty || rest.first!.isWhitespace
    }
    private static func indented(_ t: String) -> Bool {
        t.prefix(2).count == 2 && t.prefix(2).allSatisfy { $0.isWhitespace }
    }

    /// Rows [start, end] of the box holding the cursor row, or nil when the cursor is not in one.
    static func rows(line: (Int) -> String?, cursorRow: Int, maxRows: Int = 40) -> BoxRows? {
        var start = -1
        var r = cursorRow, k = 0
        while r >= 0 && k < maxRows {
            guard let t = line(r), !isRule(t) else { break }
            if isPrompt(t) { start = r; break }
            if !t.trimmingCharacters(in: .whitespaces).isEmpty && !indented(t) { break }
            r -= 1; k += 1
        }
        guard start >= 0 else { return nil }
        var end = start
        r = start + 1; k = 0
        while k < maxRows, let t = line(r) {
            if t.trimmingCharacters(in: .whitespaces).isEmpty || isRule(t) || !indented(t) { break }
            end = r; r += 1; k += 1
        }
        return cursorRow >= start && cursorRow <= end ? BoxRows(start: start, end: end) : nil
    }

    /// Where the typed text starts on a row: after `❯ ` on the first, after the indent on the rest.
    static func contentStart(_ text: String, firstRow: Bool) -> Int {
        let chars = Array(text)
        if firstRow {
            guard let i = chars.firstIndex(where: { "❯›>".contains($0) }) else { return 0 }
            return i + 2
        }
        return min(2, chars.count)
    }

    static func selectionInBox(_ s: BoxSelection, _ b: BoxRows) -> Bool {
        s.startRow >= b.start && s.endRow <= b.end && (s.endRow > s.startRow || s.endCol > s.startCol)
    }

    /// Characters of the box's text the selection covers; a row break is one
    /// (the newline, or the space the wrap dropped) unless the row is full.
    static func selectedCharCount(line: (Int) -> String?, sel: BoxSelection, box: BoxRows, cols: Int) -> Int {
        var n = 0
        for r in sel.startRow...sel.endRow {
            let t = line(r) ?? ""
            let len = t.count
            let lo = contentStart(t, firstRow: r == box.start)
            let from = max(r == sel.startRow ? sel.startCol : 0, lo)
            let to = min(r == sel.endRow ? sel.endCol : len, len)
            n += max(0, to - from)
            if r < sel.endRow { n += len >= cols - 1 ? 0 : 1 }
        }
        return n
    }

    /// Where the cursor goes so the selection ends right before it.
    static func targetAfter(line: (Int) -> String?, sel: BoxSelection, box: BoxRows) -> (row: Int, col: Int) {
        let t = line(sel.endRow) ?? ""
        let lo = contentStart(t, firstRow: sel.endRow == box.start)
        return (sel.endRow, max(lo, min(sel.endCol, t.count)))
    }

    /// Characters drawn two cells wide: the counts are by cell and the text by
    /// character, so a box holding one is left to ordinary typing.
    static func hasWideChars(_ t: String) -> Bool {
        t.unicodeScalars.contains { s in
            let v = s.value
            return (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
                || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v)
                || (0xFFE0...0xFFE6).contains(v) || (0x1F300...0x1FAFF).contains(v)
        }
    }

    /// SwiftTerm keeps the selection's position internal. Its stored
    /// `start`/`end` are read by reflection — the selected text alone cannot
    /// say WHICH occurrence was selected. Nil when SwiftTerm changes shape
    /// (then typing over a selection is just typing).
    static func selectionBounds(of view: AnyObject) -> (start: Position, end: Position)? {
        var mirror: Mirror? = Mirror(reflecting: view)
        while let m = mirror {
            if let raw = m.children.first(where: { $0.label == "selection" })?.value {
                var target: Any = raw
                let om = Mirror(reflecting: raw)
                if om.displayStyle == .optional {
                    guard let inner = om.children.first?.value else { return nil }
                    target = inner
                }
                var start: Position?, end: Position?
                for c in Mirror(reflecting: target).children {
                    if c.label == "start" { start = c.value as? Position }
                    if c.label == "end" { end = c.value as? Position }
                }
                guard let a = start, let b = end else { return nil }
                let ordered = (a.row, a.col) <= (b.row, b.col) ? (a, b) : (b, a)
                return (ordered.0, ordered.1)
            }
            mirror = m.superclassMirror
        }
        return nil
    }
}
