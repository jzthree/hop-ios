import SwiftTerm
import UIKit

// The terminal's colours, ported EXACTLY from hop's web client so an agent
// session looks the same on the phone as on the desktop. Until now this app
// used SwiftTerm's stock palette, which matched neither hop nor iTerm.
//
// The web client's own comment on the dark set is worth keeping: it was
// Tailwind pastels once (red #f87171, green #4ade80 …) — "pretty, but visibly
// washed out next to a normal terminal, which is what made Claude Code look
// duller in hop than in iTerm". These are the VS Code Dark+ terminal colours:
// saturated like a real terminal, still readable on #0d1117.
struct TerminalTheme {
    let background: UIColor
    let foreground: UIColor
    let cursor: UIColor
    let selection: UIColor
    /// 16 ANSI colours in xterm order: black…white, then the bright half.
    let ansi: [SwiftTerm.Color]

    static let dark = TerminalTheme(
        background: hex("0d1117"), foreground: hex("e6edf3"),
        cursor: hex("60a5fa"), selection: hex("264f78"),
        ansi: [
            "0d1117", "cd3131", "0dbc79", "e5e510", "2472c8", "bc3fbc", "11a8cd", "e5e5e5",
            "6b7280", "f14c4c", "23d18b", "f5f543", "3b8eea", "d670d6", "29b8db", "ffffff"
        ].map(term))

    // iTerm2's "Light Background" profile, matching the web's light mode.
    static let light = TerminalTheme(
        background: hex("ffffff"), foreground: hex("000000"),
        cursor: hex("000000"), selection: hex("b5d5ff"),
        ansi: [
            "000000", "c91b00", "00a600", "c7c400", "0225c7", "c930c7", "00a6b2", "c7c7c7",
            "676767", "ff6d67", "5ff967", "fefb67", "6871ff", "ff76ff", "5ffdff", "feffff"
        ].map(term))

    /// The background as six lowercase hex digits — what hop wants for the
    /// headless OSC 10/11 answers it gives on our behalf.
    var backgroundHex: String { Self.hexString(background) }

    var foregroundHex: String { Self.hexString(foreground) }

    private static func hexString(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func hex(_ s: String) -> UIColor {
        let v = UInt32(s, radix: 16) ?? 0
        return UIColor(red: CGFloat((v >> 16) & 0xff) / 255,
                       green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// SwiftTerm stores 16 bits per channel, so an 8-bit value is scaled by
    /// 257 (0xff → 0xffff) rather than shifted, or every colour lands slightly
    /// dark.
    private static func term(_ s: String) -> SwiftTerm.Color {
        let v = UInt32(s, radix: 16) ?? 0
        let c = { (shift: UInt32) in UInt16(((v >> shift) & 0xff) * 257) }
        return SwiftTerm.Color(red: c(16), green: c(8), blue: c(0))
    }
}
