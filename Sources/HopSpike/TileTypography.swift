import CoreGraphics
import Foundation

// How a session tile chooses its type size — and what to give up when the
// screen is too wide to fit legibly.
//
// The first tile build scaled the WHOLE screen to the tile: cols × charWidth
// == tile width, whatever point size that takes. At 90 columns in a half-width
// tile that is ~3pt — a texture, not text, and Jian's first reaction was
// exactly that ("really small font"). But a thumbnail you can't read is only
// half-useless: the SHAPE still identifies the session. The trade here keeps
// both halves: scale down until the floor, and once the floor binds, stop
// shrinking and show LESS screen instead — the last rows, where the live
// activity is, with the right edge clipping naturally. Reading beats
// completeness; the tap is still the full screen.
enum TileTypography {
    /// Monospaced advance ≈ 0.6 × point size (same ratio the terminal's own
    /// fit math uses); line height ≈ 1.19 × point size.
    static let charAdvance: CGFloat = 0.6
    static let lineHeight: CGFloat = 1.19

    /// The smallest type worth rendering as text. Below this, glyphs merge at
    /// normal phone-holding distance and the tile degrades to noise.
    static let floorPt: CGFloat = 7

    /// Returns the text to render and the point size to render it at.
    /// When the whole grid fits at ≥ floorPt, that's the answer. When it
    /// doesn't, hold the floor and window the screen: trailing blank rows go
    /// first, then history from the top until what remains fits the tile's
    /// height. Columns need no slicing — layout clips the right edge.
    static func window(text: String, cols: Int,
                       width: CGFloat, height: CGFloat) -> (text: String, pt: CGFloat) {
        let fitPt = width / CGFloat(max(20, cols)) / charAdvance
        guard fitPt < floorPt else { return (text, fitPt) }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        while let last = lines.last,
              last.unicodeScalars.allSatisfy({ CharacterSet.whitespaces.contains($0) }) {
            lines.removeLast()
        }
        let rowsThatFit = max(3, Int(height / (floorPt * lineHeight)))
        if lines.count > rowsThatFit {
            lines.removeFirst(lines.count - rowsThatFit)
        }
        return (lines.joined(separator: "\n"), floorPt)
    }
}
