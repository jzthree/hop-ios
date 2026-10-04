import Foundation

// Agents print URLs constantly — PR links, preview servers, docs — and on a
// phone they're just untouchable glyphs. Pulling them off the screen turns
// them back into things you can tap. Pure so it can be unit-tested.

// Explicit ASCII charset rather than "not whitespace": rejoined wrapped rows
// can butt a URL up against a TUI border, and \S would swallow the box-drawing
// characters into the link.
private let urlChars = #"[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%\-]"#
private let urlPattern = try! NSRegularExpression(
    pattern: #"(?:https?://\#(urlChars)+)|(?:\b(?:localhost|127\.0\.0\.1):\d+(?:/\#(urlChars)*)?)"#,
    options: [.caseInsensitive])

/// Links visible in `text`, newest first — the bottom of a terminal is the
/// part you just watched scroll by, so that's what you're reaching for.
/// Duplicates collapse to their newest appearance.
func extractLinks(from text: String) -> [String] {
    let ns = text as NSString
    var found: [String] = []
    urlPattern.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let m else { return }
        var s = trimTrailingPunctuation(ns.substring(with: m.range))
        guard s.count > "http://".count else { return }   // a bare scheme is not a link
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        found.append(s)
    }
    var seen = Set<String>()
    return found.reversed().filter { seen.insert($0).inserted }
}

/// Terminals wrap without inserting a newline, so a long URL arrives as two
/// rows. Joining wrapped rows before extraction is the difference between one
/// working link and two broken halves.
func screenText(rows: [(text: String, wrapped: Bool)]) -> String {
    var out: [String] = []
    for row in rows {
        if row.wrapped, !out.isEmpty { out[out.count - 1] += row.text }
        else { out.append(row.text) }
    }
    return out.joined(separator: "\n")
}

/// Sentence punctuation and brackets sit next to URLs in prose ("see
/// https://x/y."), and closing brackets belong to the URL only if it opened
/// one ("…/foo(bar)" is real, "(https://x)" is not).
private func trimTrailingPunctuation(_ s: String) -> String {
    var out = s
    while let last = out.last {
        if ".,;:!?'\"".contains(last) {
            out.removeLast()
        } else if ")]}>".contains(last) {
            let opens: Character = last == ")" ? "(" : last == "]" ? "[" : last == "}" ? "{" : "<"
            if out.filter({ $0 == opens }).count >= out.filter({ $0 == last }).count { break }
            out.removeLast()
        } else {
            break
        }
    }
    return out
}

/// Walks rows looking for `needle`, in either direction, and returns the
/// matching row. Takes a line accessor rather than an array so it can search
/// thousands of scrollback rows without materialising them — and so the
/// stepping logic, which is what actually breaks, is testable.
///
/// `direction` is -1 for older (up the scrollback) and +1 for newer.
func findMatchRow(from start: Int, direction: Int, needle: String,
                  limit: Int = 5000, line: (Int) -> String?) -> Int? {
    let q = needle.lowercased()
    guard !q.isEmpty, direction != 0 else { return nil }
    var row = start
    var probed = 0
    while probed < limit {
        row += direction
        probed += 1
        if row < 0 { return nil }
        guard let text = line(row) else {
            // Past the live edge going forward; a gap going back.
            if direction > 0 { return nil }
            continue
        }
        if text.lowercased().contains(q) { return row }
    }
    return nil
}

/// Normalise a raw regex hit the way extractLinks does — shared so a tapped
/// link and a menu link are the same string for the same pixels.
func normalizeLink(_ raw: String) -> String? {
    var s = trimTrailingPunctuation(raw)
    guard s.count > "http://".count else { return nil }
    if !s.lowercased().hasPrefix("http") { s = "http://" + s }
    return s
}

/// The URL under a character offset in a screen JOINED WITHOUT SEPARATORS —
/// every row padded to the grid width, rows concatenated. Wrapped URLs then
/// connect naturally (a wrapped row is full to its last column) with exact
/// offset math (offset = row * cols + col), and no wrap flags are needed;
/// unwrapped rows end in spaces, which the URL charset already excludes.
/// The tap must land INSIDE the match — a row that merely contains a link
/// somewhere is not a tap on it.
func linkHit(atOffset offset: Int, in joined: String) -> String? {
    let ns = joined as NSString
    guard offset >= 0, offset < ns.length else { return nil }
    var hit: String?
    urlPattern.enumerateMatches(in: joined,
                                range: NSRange(location: 0, length: ns.length)) { m, _, stop in
        guard let m, NSLocationInRange(offset, m.range) else { return }
        hit = normalizeLink(ns.substring(with: m.range))
        stop.pointee = true
    }
    return hit
}

private let urlCharSet: Set<Character> = Set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:/?#[]@!$&()*+,;=%-")
func isUrlChar(_ c: Character) -> Bool { urlCharSet.contains(c) }

/// The URL under a tap at (row, col) on a screen given as rows each padded
/// to the grid width. Joins wrapped rows — INCLUDING an app's indented
/// continuation. Claude renders under bullets, so a URL that wraps at the
/// right edge comes back on the next row behind two or four spaces of
/// indent; those spaces terminated the URL match, so tapping the first half
/// opened a truncated link and tapping the second half (no scheme) found
/// nothing (Jian: "tapping a multiline url seems to break"). A row is treated
/// as a continuation when the previous row ran full to its last column with a
/// URL character AND this row, past leading whitespace, resumes with one —
/// the leading whitespace is then dropped so the halves connect. Everything
/// else keeps its padding, which is what stops unrelated rows fusing. The tap
/// is mapped through the same dropping so it lands on the exact cell.
/// The vertical rules a TUI draws its boxes with. A long URL inside one is
/// cut by the border, not by the grid edge.
private let borderChars: Set<Character> = ["│", "┃", "║", "|", "▏", "▕", "┆", "┊"]

/// How many trailing characters of a padded row are layout rather than text,
/// when the row's content RUNS INTO the layout edge — nil when it doesn't.
///
/// Two ways a row can be cut off: it fills the grid to the last column, or
/// its text butts straight up against a box's right rule (`…/path│`). The
/// second is the one that made long URLs unrecognisable: the row ends in a
/// border, never a URL character, so the old "is the last character part of a
/// URL?" test said no and the halves never joined. A URL that merely ENDS
/// inside a box has spaces before the rule, so requiring the URL character to
/// sit immediately before it keeps unrelated lines apart.
private func layoutTailLength(_ raw: String) -> Int? {
    let padding = raw.reversed().prefix(while: { $0 == " " }).count
    let content = raw.dropLast(padding)
    guard let last = content.last else { return nil }
    if padding == 0 { return isUrlChar(last) ? 0 : nil }
    guard borderChars.contains(last) else { return nil }
    let beforeRule = content.dropLast()
    let gap = beforeRule.reversed().prefix(while: { $0 == " " }).count
    guard gap == 0, let urlEnd = beforeRule.last, isUrlChar(urlEnd) else { return nil }
    return padding + 1        // the padding and the rule itself
}

/// Characters of layout to drop from the START of a continuation row: the
/// indent, an optional opening rule, and the space after it.
private func continuationLeadLength(_ raw: String) -> Int? {
    var i = raw.startIndex
    while i < raw.endIndex, raw[i] == " " { i = raw.index(after: i) }
    if i < raw.endIndex, borderChars.contains(raw[i]) {
        i = raw.index(after: i)
        while i < raw.endIndex, raw[i] == " " { i = raw.index(after: i) }
    }
    guard i < raw.endIndex, isUrlChar(raw[i]) else { return nil }
    let lead = raw.distance(from: raw.startIndex, to: i)
    return lead > 0 ? lead : nil
}

/// The URL under a tap at (row, col) on a screen given as rows each padded to
/// the grid width. Joins a URL the LAYOUT broke — a terminal wrap at the grid
/// edge, and an app's own break inside a bordered box or under a bullet
/// (Claude indents; Codex rules its panes). A row is a continuation only when
/// the row above ran INTO the layout edge, so ordinary neighbouring lines
/// never fuse; the layout on both sides is dropped so the halves connect, and
/// the tap is mapped through the same dropping to land on the exact cell.
/// One screen, rows padded to the grid width, joined so that a URL the
/// LAYOUT broke reads as one string — a terminal wrap at the grid edge, and
/// an app's own break inside a bordered box or under a bullet. Returns the
/// joined text and, when asked, where a tap landed in it.
///
/// Tapping a link and listing links must agree, so both go through here.
private func joinLayoutRows(_ rows: [String],
                            tapRow: Int? = nil, tapCol: Int = 0) -> (text: String, tapOffset: Int?) {
    let tails = rows.map(layoutTailLength)
    var text = ""
    var running = 0
    var tapOffset: Int?
    for (r, raw) in rows.enumerated() {
        var skipped = 0
        if r > 0, tails[r - 1] != nil, let lead = continuationLeadLength(raw) {
            skipped = lead
        }
        // Drop this row's own trailing layout only when it continues below.
        let tail = (r + 1 < rows.count && tails[r] != nil) ? tails[r]! : 0
        let body = raw.dropFirst(skipped).dropLast(min(tail, max(0, raw.count - skipped)))
        if r == tapRow {
            let c = tapCol - skipped
            tapOffset = (c >= 0 && c < body.count) ? running + c : nil
        }
        text += body
        running += body.count
    }
    return (text, tapOffset)
}

/// The URL under a tap at (row, col) on a screen given as rows each padded to
/// the grid width. A row is a continuation only when the row above ran INTO
/// the layout edge, so ordinary neighbouring lines never fuse; the layout on
/// both sides is dropped so the halves connect, and the tap is mapped through
/// the same dropping to land on the exact cell.
func linkHit(rows: [String], row tapRow: Int, col tapCol: Int) -> String? {
    guard tapRow >= 0, tapRow < rows.count, tapCol >= 0 else { return nil }
    let joined = joinLayoutRows(rows, tapRow: tapRow, tapCol: tapCol)
    guard let off = joined.tapOffset else { return nil }
    return linkHit(atOffset: off, in: joined.text)
}

/// Every link on a screen of padded rows, newest first — the list behind
/// "Open link…". It joins exactly the way tapping does, so a URL you can tap
/// is a URL the list offers; they disagreed while the list used the terminal's
/// wrap flag alone, which an app's own line breaking never sets.
func linksIn(rows: [String]) -> [String] {
    extractLinks(from: joinLayoutRows(rows).text)
}

/// A URL that was COPIED while broken across rows, put back together — or nil
/// when the text is not simply one URL.
///
/// Selecting a long link and copying it yields what the screen held: the
/// break, the indent, and any box rules the app drew around it, so the paste
/// is a dead link (Jian: "copy paste will not work out of the box because of
/// the extra spaces"). Strip each line's surrounding layout, concatenate, and
/// accept the result ONLY if the whole thing is exactly one URL — so an
/// ordinary multi-line copy is returned untouched by the caller.
func rejoinWrappedURL(_ text: String) -> String? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > 1 else { return nil }
    var joined = ""
    for line in lines {
        var body = Substring(line)
        while let f = body.first, f == " " || f == "\t" { body = body.dropFirst() }
        if let f = body.first, borderChars.contains(f) {
            body = body.dropFirst()
            while let f = body.first, f == " " || f == "\t" { body = body.dropFirst() }
        }
        while let l = body.last, l == " " || l == "\t" { body = body.dropLast() }
        if let l = body.last, borderChars.contains(l) {
            body = body.dropLast()
            while let l = body.last, l == " " || l == "\t" { body = body.dropLast() }
        }
        if body.isEmpty { return nil }      // a blank row means this is prose
        joined += body
    }
    let ns = joined as NSString
    guard let m = urlPattern.firstMatch(in: joined, range: NSRange(location: 0, length: ns.length)),
          m.range.location == 0, m.range.length == ns.length else { return nil }
    return normalizeLink(joined)
}
