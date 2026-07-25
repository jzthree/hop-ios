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
