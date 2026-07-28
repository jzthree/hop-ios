import SwiftUI

/// One run of same-styled characters in a screen row, as hop's /preview
/// reports it: text, optional foreground/background hex, optional faint flag.
/// The daemon has already resolved every palette index to #rrggbb — the whole
/// reason tiles can be colored without this app growing an ANSI parser.
struct ColorRun: Equatable {
    let t: String
    let f: String?
    let b: String?
    let o: Bool
    /// Inverse video — a cursor, a selected menu row, a status bar. The web
    /// renderer swaps ink and paper for these; so do we.
    let i: Bool
}

enum TileInk {
    /// Decode the endpoint's `color` field. Tolerant of everything missing:
    /// sessions without a persistent server-side terminal report an empty
    /// list, and a daemon predating the field omits it entirely — both mean
    /// "render the plain text".
    static func decode(_ any: Any?) -> [[ColorRun]] {
        guard let rows = any as? [[[String: Any]]] else { return [] }
        return rows.map { row in
            row.compactMap { run in
                guard let t = run["t"] as? String else { return nil }
                return ColorRun(t: t, f: run["f"] as? String, b: run["b"] as? String,
                                o: (run["o"] as? Int ?? 0) == 1,
                                i: (run["i"] as? Int ?? 0) == 1)
            }
        }
    }

    static func color(hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7,
              let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(hex: v)
    }

    /// The tile's default ink — what colourless text renders as.
    static let base = Color(hex: 0xe6edf3).opacity(0.85)

    /// The visible window of a screen as styled text. `range` comes from
    /// TileTypography, so the coloured render shows exactly the rows the
    /// plain fallback would. Rows the colour report doesn't cover (or covers
    /// as empty) fall back to the plain line in base ink.
    static func attributed(rows: [[ColorRun]], lines: [String],
                           range: Range<Int>) -> AttributedString {
        var out = AttributedString()
        for i in range {
            if i > range.lowerBound { out += AttributedString("\n") }
            let runs = i < rows.count ? rows[i] : []
            if runs.isEmpty {
                var plain = AttributedString(i < lines.count ? lines[i] : "")
                plain.foregroundColor = base
                out += plain
                continue
            }
            for run in runs { out += styled(run) }
        }
        return out
    }

    private static func styled(_ run: ColorRun) -> AttributedString {
        var piece = AttributedString(run.t)
        if run.i {
            // Inverse: ink becomes paper and paper becomes ink, same
            // fallbacks the web renderer uses.
            piece.foregroundColor = color(hex: run.b) ?? Color.hopSurface
            piece.backgroundColor = color(hex: run.f) ?? base
        } else {
            let fg = color(hex: run.f) ?? base
            piece.foregroundColor = run.o ? fg.opacity(0.55) : fg
            if let bg = color(hex: run.b) { piece.backgroundColor = bg }
        }
        return piece
    }

    /// The list row's three meaningful lines, in colour — the same rows
    /// meaningfulTail picks, trimmed at run granularity so snippets don't
    /// carry the terminal's leading indentation into a text row. Nil when
    /// the session has no colour report; the caller falls back to plain.
    static func snippet(_ screen: ScreenPreview, lines wanted: Int) -> AttributedString? {
        guard !screen.colorRows.isEmpty else { return nil }
        let indices = AppModel.meaningfulTailIndices(of: screen.text, lines: wanted)
        guard !indices.isEmpty else { return nil }
        let plain = screen.text.split(separator: "\n",
                                      omittingEmptySubsequences: false).map(String.init)
        var out = AttributedString()
        for (n, idx) in indices.enumerated() {
            if n > 0 { out += AttributedString("\n") }
            let runs = idx < screen.colorRows.count ? trimmed(screen.colorRows[idx]) : []
            if runs.isEmpty {
                var p = AttributedString(idx < plain.count
                    ? plain[idx].trimmingCharacters(in: .whitespaces) : "")
                p.foregroundColor = base
                out += p
            } else {
                for run in runs { out += styled(run) }
            }
        }
        return out
    }

    /// Strip leading/trailing whitespace from a row of runs, preserving the
    /// styling of what remains. Runs that are nothing but space disappear;
    /// a run that starts or ends the visible text is cut, not dropped.
    static func trimmed(_ runs: [ColorRun]) -> [ColorRun] {
        var out = runs
        while let first = out.first {
            let cut = String(first.t.drop(while: { $0 == " " }))
            if cut.isEmpty { out.removeFirst(); continue }
            if cut.count != first.t.count {
                out[0] = ColorRun(t: cut, f: first.f, b: first.b, o: first.o, i: first.i)
            }
            break
        }
        while let last = out.last {
            let cut = String(String(last.t.reversed()).drop(while: { $0 == " " }).reversed())
            if cut.isEmpty { out.removeLast(); continue }
            if cut.count != last.t.count {
                out[out.count - 1] = ColorRun(t: cut, f: last.f, b: last.b, o: last.o, i: last.i)
            }
            break
        }
        return out
    }
}
