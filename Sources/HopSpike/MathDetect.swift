import Foundation

// Find LaTeX in terminal text — a port of hop web's utils/mathDetect.ts, so
// a formula the desktop renders on hover is the formula a tap renders here.
//
// Agents write math the way papers do: `$…$`, `$$…$$`, `\(…\)`, `\[…\]` —
// and often bare, `\frac{a}{b}` in the middle of a sentence. Delimited forms
// are taken at face value (a `$` pair around something that looks like math,
// never around prices). Bare LaTeX is a run of math-like tokens containing
// at least one command, with balanced braces, trimmed of prose punctuation.
// Offsets are UTF-16 (NSString), like NSRegularExpression's. Keep in step
// with the web detector; its tests are mirrored in testMathDetect.

struct MathSpan: Equatable {
    /// UTF-16 offsets into the text; `end` exclusive. Covers the delimiters.
    let start: Int
    let end: Int
    /// The LaTeX to render, delimiters stripped.
    let tex: String
    /// Display (block) math vs inline.
    let display: Bool
}

private let mathCommands: Set<String> = [
    "frac", "dfrac", "tfrac", "sqrt", "sum", "prod", "int", "iint", "oint", "lim", "log", "ln", "exp", "sin", "cos", "tan",
    "cdot", "times", "div", "pm", "mp", "leq", "geq", "le", "ge", "neq", "ne", "approx", "equiv", "sim", "simeq", "propto",
    "infty", "partial", "nabla", "hat", "bar", "vec", "tilde", "dot", "ddot", "overline", "underline", "mathbb", "mathcal",
    "mathbf", "mathrm", "mathit", "boldsymbol", "left", "right", "binom", "over", "to", "rightarrow", "leftarrow",
    "Rightarrow", "Leftarrow", "mapsto", "in", "notin", "subset", "subseteq", "cup", "cap", "forall", "exists", "ldots",
    "cdots", "vdots", "ddots", "prime", "circ", "degree", "angle", "perp", "parallel", "langle", "rangle", "lfloor",
    "rfloor", "lceil", "rceil", "text", "operatorname", "max", "min", "argmax", "argmin", "sup", "inf", "det", "tr",
    "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta", "iota", "kappa",
    "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
    "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega",
]

private func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
private let commandRE = rx(#"\\([a-zA-Z]+)"#)
private let tokenRE = rx(#"\S+"#)
private let mathTokenRE = rx(#"^[\\A-Za-z0-9_^{}()\[\]|+\-*/=<>.,:;!'`&~]+$"#)
private let delimitedREs: [(NSRegularExpression, Bool)] = [
    (rx(#"\$\$([\s\S]+?)\$\$"#), true),
    (rx(#"\\\[([\s\S]+?)\\\]"#), true),
    (rx(#"\\\(([\s\S]+?)\\\)"#), false),
]
// Inline dollars: no space just inside either `$`, no `$` within, and the
// inside has to read as math (so "$5 and $10" stays money).
private let inlineRE = rx(#"\$(?!\s)([^$\n]{1,200}?)(?<!\s)\$(?![\d$])"#)
private let functionWords: Set<String> = ["sin", "cos", "tan", "log", "ln", "exp", "max", "min", "lim", "det", "tr", "mod", "dx", "dy", "dt"]

private func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
    re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
}
private func test(_ pattern: String, _ s: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }

/// True when the text carries at least one recognisable LaTeX command.
private func hasMathCommand(_ s: String) -> Bool {
    let ns = s as NSString
    for m in commandRE.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        if mathCommands.contains(ns.substring(with: m.range(at: 1))) { return true }
        // Any command followed by a brace group is math enough (\foo{x}).
        let after = m.range.location + m.range.length
        if after < ns.length, ns.character(at: after) == 0x7B { return true }
    }
    return false
}

/// Looks like math rather than prose or a price: a command, or structure.
private func looksLikeMath(_ inner: String) -> Bool {
    let s = inner.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return false }
    if hasMathCommand(s) { return true }
    // A bare number is a price; a lone variable (`$x$`) is math.
    if test(#"^[\d.,\s]+$"#, s) { return false }
    if test(#"^[A-Za-z]{1,2}$"#, s) { return true }
    return test(#"[\^_{}]"#, s) || (test(#"[=<>+\-*/|]"#, s) && test(#"[A-Za-z]"#, s))
}

private func braceBalance(_ s: String) -> Int {
    var depth = 0
    var escape = false
    for u in s.utf16 {
        if escape { escape = false; continue }
        if u == 0x5C { escape = true }           // \ escapes the next char
        else if u == 0x7B { depth += 1 }
        else if u == 0x7D { depth -= 1 }
    }
    return depth
}

private func overlaps(_ spans: [MathSpan], _ start: Int, _ end: Int) -> Bool {
    spans.contains { start < $0.end && end > $0.start }
}

// A plain word is prose ("so", "is") unless it is a single letter or a
// function name; words with math punctuation stuck to them are math.
private func isMathToken(_ tok: String) -> Bool {
    if !matches(mathTokenRE, tok) { return false }
    if tok.contains("\\") { return true }
    let bare = tok.replacingOccurrences(of: #"[.,;:!?)]+$"#, with: "", options: .regularExpression)
    if test(#"^[A-Za-z]+$"#, bare) { return bare.count == 1 || functionWords.contains(bare) }
    if test(#"[A-Za-z]{4,}"#, tok) && !test(#"[\\^_{}=+\-*/]"#, tok) { return false }
    return true
}

private func trimSpan(_ ns: NSString, _ start: Int, _ end: Int) -> (Int, Int) {
    let punct: Set<unichar> = Set(" \t\n,;:.!?".utf16)
    var s = start, e = end
    while s < e, punct.contains(ns.character(at: s)) { s += 1 }
    while e > s, punct.contains(ns.character(at: e - 1)) { e -= 1 }
    // A trailing ")" never opened inside the span is prose punctuation.
    while e > s, ns.character(at: e - 1) == 0x29 {
        let body = ns.substring(with: NSRange(location: s, length: e - s)).utf16
        if body.filter({ $0 == 0x28 }).count < body.filter({ $0 == 0x29 }).count { e -= 1 } else { break }
    }
    return (s, e)
}

private func findBareRuns(_ text: String, _ out: inout [MathSpan]) {
    let ns = text as NSString
    let tokens = tokenRE.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
        (s: $0.range.location, e: $0.range.location + $0.range.length, t: ns.substring(with: $0.range))
    }
    var i = 0
    while i < tokens.count {
        let tok = tokens[i]
        if !hasMathCommand(tok.t) || overlaps(out, tok.s, tok.e) { i += 1; continue }
        var a = i
        while a > 0, isMathToken(tokens[a - 1].t), !overlaps(out, tokens[a - 1].s, tokens[a - 1].e),
              tokens[a].s - tokens[a - 1].e <= 1 { a -= 1 }
        var b = i
        while b + 1 < tokens.count, isMathToken(tokens[b + 1].t), !overlaps(out, tokens[b + 1].s, tokens[b + 1].e),
              tokens[b + 1].s - tokens[b].e <= 1 { b += 1 }
        // Shrink from the right until braces balance.
        while b >= a, braceBalance(ns.substring(with: NSRange(location: tokens[a].s, length: tokens[b].e - tokens[a].s))) != 0 { b -= 1 }
        if b < a { i += 1; continue }
        let (s, e) = trimSpan(ns, tokens[a].s, tokens[b].e)
        if e > s {
            let tex = ns.substring(with: NSRange(location: s, length: e - s))
            if hasMathCommand(tex), braceBalance(tex) == 0 {
                out.append(MathSpan(start: s, end: e, tex: tex, display: false))
            }
        }
        i = b + 1
    }
}

/// Every math span in `text`, delimited forms first, then bare runs. Sorted, non-overlapping.
func findMathSpans(_ text: String) -> [MathSpan] {
    let ns = text as NSString
    let all = NSRange(location: 0, length: ns.length)
    var out: [MathSpan] = []
    func claim(_ start: Int, _ end: Int, _ tex: String, _ display: Bool) {
        if overlaps(out, start, end) { return }
        let t = tex.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || (t as NSString).length > 600 { return }
        out.append(MathSpan(start: start, end: end, tex: t, display: display))
    }
    for (re, display) in delimitedREs {
        for m in re.matches(in: text, range: all) {
            let inner = ns.substring(with: m.range(at: 1))
            if looksLikeMath(inner) || display { claim(m.range.location, m.range.location + m.range.length, inner, display) }
        }
    }
    for m in inlineRE.matches(in: text, range: all) {
        let inner = ns.substring(with: m.range(at: 1))
        if looksLikeMath(inner) { claim(m.range.location, m.range.location + m.range.length, inner, false) }
    }
    findBareRuns(text, &out)
    return out.sorted { $0.start < $1.start }
}

/// The formula under a tap at (row, col) on a screen of rows. Rows the
/// terminal soft-wrapped (`wrapped[r]`: row r continues row r-1) are joined
/// without a break, the rest with a newline — so a `$$ … $$` block is
/// followed across the rows it spans, exactly as the desktop does.
func mathHit(rows: [String], wrapped: [Bool], row tapRow: Int, col tapCol: Int) -> MathSpan? {
    guard tapRow >= 0, tapRow < rows.count, tapCol >= 0 else { return nil }
    var text = ""
    var offset: Int?
    for (r, raw) in rows.enumerated() {
        if r > 0, !(r < wrapped.count && wrapped[r]) { text += "\n" }
        // A soft-wrapped row runs to the edge; keep its trailing spaces
        // only when the next row continues it.
        let continues = r + 1 < rows.count && r + 1 < wrapped.count && wrapped[r + 1]
        let line = continues ? raw : raw.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        if r == tapRow {
            let chars = Array(line)
            guard tapCol < chars.count else { return nil }   // tapped past the end of the text
            offset = (text as NSString).length + (String(chars.prefix(tapCol)) as NSString).length
        }
        text += line
    }
    guard let at = offset else { return nil }
    return findMathSpans(text).first { at >= $0.start && at < $0.end }
}
