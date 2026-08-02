import Foundation

// The modes the REMOTE app has turned on: whether it owns the whole screen,
// whether it wants mouse input, and whether it can read the encoding we'd
// send. None of these can be asked of the local terminal — SwiftTerm keeps the
// buffer switch and the mouse encoding private, and a snapshot resets its
// state anyway. hop's server tracks all three across the whole session and
// reports them with every snapshot, so they are seeded there and kept current
// by watching the stream for the same sequences the server watches.
//
// Pure, and tested, because the failures are silent in the worst way: get the
// mouse flags wrong and a drag falls through to keys, which at a claude prompt
// recalls previous PROMPTS — a scroll gesture that rewrites what you were
// typing.
struct RemoteModes {
    private(set) var altScreen = false
    private(set) var mouseReporting = false
    private(set) var mouseSgr = false
    private var tail = ""

    /// Both halves matter. Mouse tracking alone means the app wants mouse
    /// input; without SGR it expects the legacy encoding, which caps
    /// coordinates at 223 and which we don't send.
    var takesWheel: Bool { mouseReporting && mouseSgr }

    /// From a snapshot, which carries the server's view of the whole session —
    /// including modes set long before the replay window starts.
    mutating func seed(altScreen: Bool, mouseReporting: Bool, mouseSgr: Bool) {
        self.altScreen = altScreen
        self.mouseReporting = mouseReporting
        self.mouseSgr = mouseSgr
        tail = ""
    }

    /// From live output, so the modes follow the app: claude starting inside a
    /// shell session, or exiting and handing the screen back.
    mutating func note(_ chunk: String) {
        guard chunk.contains("[?") || !tail.isEmpty else { return }
        let text = tail + chunk
        for match in Self.modePattern.matches(
            in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let params = Range(match.range(at: 1), in: text),
                  let action = Range(match.range(at: 2), in: text) else { continue }
            let on = text[action] == "h"
            for param in text[params].split(separator: ";") {
                switch param {
                case "47", "1047", "1049": altScreen = on
                case "1000", "1002", "1003": mouseReporting = on
                case "1006": mouseSgr = on
                default: break
                }
            }
        }
        // Carry a tail only when the chunk actually ends mid-sequence — an ESC
        // with no terminator after it. Carrying one unconditionally would make
        // every later chunk fail the cheap prefilter and run the regex, on the
        // hot path that paints the screen.
        if let esc = text.lastIndex(of: "\u{1b}"),
           text.distance(from: esc, to: text.endIndex) < Self.maxPartial,
           !text[esc...].contains(where: { $0 == "h" || $0 == "l" }) {
            tail = String(text[esc...])
        } else {
            tail = ""
        }
    }

    private static let maxPartial = 24
    private static let modePattern = try! NSRegularExpression(
        pattern: "\u{1b}\\[\\?([0-9;]+)([hl])")
}

/// Where a drag's travel should go.
enum ScrollSink {
    /// The app owns the screen and takes wheel events: it scrolls itself.
    case wheel
    /// The app owns the screen but won't take wheel events — a pager. Coarse
    /// keys are all that's left.
    case pageKeys
    /// Nobody else owns the screen, so move our own viewport over the
    /// scrollback we've been keeping.
    case viewport
}

/// Decided by who owns the SCREEN, not by whether we happen to have scrollback
/// yet — the same rule as hop's web client.
///
/// The difference shows at a bare shell prompt. A fresh session has no
/// scrollback, and a "no scrollback → send keys" rule fires Page keys at a
/// shell that never asked for them, then silently switches to scrolling our
/// own buffer once enough output has piled up: the same gesture on the same
/// session doing two different things depending on how long you'd been
/// looking at it.
func scrollSink(altScreen: Bool, takesWheel: Bool) -> ScrollSink {
    guard altScreen else { return .viewport }
    return takesWheel ? .wheel : .pageKeys
}

/// The wheel events for `rows` of finger travel, aimed at the middle of the
/// screen — an app that routes scrolling by pane would otherwise get every
/// notch at the edge. Built by hand rather than through SwiftTerm's encoder,
/// which reads our own terminal's mouse state; the app's is the one that
/// matters. Same shape as hop's web client sends.
func wheelSequence(rows: Int, cols: Int, screenRows: Int, cap: Int = 40) -> String {
    guard rows != 0 else { return "" }
    let code = rows > 0 ? 64 : 65               // dragging down looks backwards
    let col = max(1, cols / 2), row = max(1, screenRows / 2)
    return String(repeating: "\u{1b}[<\(code);\(col);\(row)M",
                  count: min(abs(rows), cap))
}

/// One SGR mouse CLICK — press and release at a cell. The phone finally
/// answers the clickable things a mouse-aware app draws ("jump to bottom
/// (click)" in claude, unreachable from a phone until now). Sent only when
/// the app asked for mouse reporting, so plain shells never see it.
func clickSequence(col: Int, row: Int) -> String {
    let c = max(1, col), r = max(1, row)
    return "\u{1b}[<0;\(c);\(r)M\u{1b}[<0;\(c);\(r)m"
}

/// The height of one DRAWN row.
///
/// Not `viewHeight / terminal.rows`: the local terminal is resized to whatever
/// size the room elected, which is often a desktop peer's — hop runs one PTY
/// at one size for everyone. A 50-row desktop leaves this phone drawing 23
/// rows of that grid, and dividing by 50 makes every row of finger travel
/// count as two. Scrolling then runs at twice the speed of the finger for as
/// long as the desktop holds the size, which on a shared session is most of
/// the time.
///
/// `drawnRows` comes from SwiftTerm's own sizeChanged, which reports what the
/// view fits; it is 0 only before the first layout, when the terminal's own
/// row count is the best guess available.
func drawnCellHeight(viewHeight: CGFloat, drawnRows: Int, terminalRows: Int) -> CGFloat {
    let rows = drawnRows > 0 ? drawnRows : terminalRows
    return max(1, viewHeight / CGFloat(max(1, rows)))
}

/// How far down to nudge a grid that cannot fill the viewport, so the unused
/// space is split evenly instead of all landing under the content.
///
/// `capacityRows` is what the view FITS at the current font (SwiftTerm's own
/// sizeChanged); `gridRows` is what the PTY actually is. They differ only
/// while we are honouring someone else's grid — a desk's 80x24 auto-scaled
/// onto a tall phone fits its width and covers about half its height. Zero
/// when they agree, so the normal case pays nothing, and zero for slack small
/// enough to be rounding rather than letterboxing.
func letterboxOffset(viewHeight: CGFloat, gridRows: Int, capacityRows: Int,
                     minimum: CGFloat = 8) -> CGFloat {
    guard viewHeight > 1, gridRows > 0, capacityRows > 0,
          gridRows < capacityRows else { return 0 }
    let content = viewHeight * CGFloat(gridRows) / CGFloat(capacityRows)
    let slack = viewHeight - content
    // PROPORTIONAL, not a flat floor: one row short of a fifty-row fit is
    // 16pt on an 800pt screen, and nudging the terminal 8pt for that would
    // jitter on every refit. Letterboxing is for a grid of a genuinely
    // different shape, which is tens of percent, never one row.
    guard slack > max(minimum, viewHeight * 0.08) else { return 0 }
    return (slack / 2).rounded(.down)
}

/// The font size that makes `gridCols` columns fit in `viewWidth` points.
///
/// Observer mode's core: when a peer holds a 90-column grid, the phone can
/// shrink its glyphs until the whole width fits instead of panning. Monospace
/// advance scales linearly with point size, so the target cell width
/// (viewWidth / gridCols) maps straight back to a point size. Clamped to a
/// floor because a 2pt terminal is a texture, not text — below the floor,
/// fitting is a lie and panning is honest.
func fitFontSize(base: CGFloat, baseCellWidth: CGFloat, viewWidth: CGFloat,
                 gridCols: Int, floor: CGFloat = 4) -> CGFloat {
    guard base > 0, baseCellWidth > 0, viewWidth > 0, gridCols > 0 else { return base }
    let target = base * (viewWidth / CGFloat(gridCols)) / baseCellWidth
    return min(base, max(floor, target))
}

