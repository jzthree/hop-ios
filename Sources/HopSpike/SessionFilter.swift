import Foundation
import SwiftUI

// Pure list-shaping, extracted from the view so it can be unit-tested:
// which sessions a scope shows, and how a filter query matches.
enum SessionScope: String, CaseIterable {
    case user = "You", agent = "Agents", all = "All"
}

/// How the wall arranges itself. Folder = the user's own server-side filing.
enum GroupMode: String, CaseIterable {
    case recent, project, folder
    var label: String {
        switch self {
        case .recent: return "Recent"
        case .project: return "By project"
        case .folder: return "By folder"
        }
    }
    var icon: String {
        switch self {
        case .recent: return "clock"
        case .project: return "externaldrive"
        case .folder: return "folder"
        }
    }
}

/// Badge hue per running app, so a wall of tiles scans by colour before it
/// scans by name: claude keeps hop's purple; editors, runtimes and remotes
/// each get a tone; anything unrecognised stays neutral instead of wearing
/// claude's colour dishonestly.
func appTint(_ app: String) -> SwiftUI.Color {
    switch app.lowercased() {
    case "claude": return .hopGlow
    case "vim", "nvim", "vi", "emacs": return SwiftUI.Color(hex: 0x2fbf9a)
    case "python", "python3", "ipython": return SwiftUI.Color(hex: 0x5aa7e0)
    case "node", "npm", "yarn", "bun": return SwiftUI.Color(hex: 0x7fcf6a)
    case "ssh", "mosh": return SwiftUI.Color(hex: 0xe0a45a)
    default: return SwiftUI.Color(hex: 0x93a0b4)
    }
}

/// Group label for a session: the first couple of path segments under home
/// ("~/Code/hop2"), matching how the web switcher buckets a fleet. Sessions in
/// a project root and its subdirectories land together.
func projectKey(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "Other" }
    var shortened = cwd
    if let r = cwd.range(of: #"^/(Users|home)/[^/]+"#, options: .regularExpression) {
        shortened = "~" + cwd[r.upperBound...]
    } else if cwd == "/root" {
        shortened = "~"
    } else if cwd.hasPrefix("/root/") {
        shortened = "~" + cwd.dropFirst("/root".count)
    }
    let home = shortened.hasPrefix("~")
    let parts = shortened.drop(while: { $0 == "~" || $0 == "/" })
        .split(separator: "/").map(String.init)
    let kept = Array(parts.prefix(home ? 2 : 3))
    if kept.isEmpty { return home ? "~" : "/" }
    return (home ? "~/" : "/") + kept.joined(separator: "/")
}

/// Sessions bucketed by project, most-recently-active bucket first.
func groupSessionsByProject(_ sessions: [HopSession]) -> [(label: String, rows: [HopSession])] {
    var buckets: [String: [HopSession]] = [:]
    for s in sessions { buckets[projectKey(s.cwd), default: []].append(s) }
    return buckets
        .map { (label: $0.key, rows: $0.value) }
        .sorted { a, b in
            let aa = a.rows.map(\.lastActivityAt).max() ?? 0
            let bb = b.rows.map(\.lastActivityAt).max() ?? 0
            return aa == bb ? a.label < b.label : aa > bb
        }
}

/// Sessions bucketed by Jian's OWN folders, in the daemon's folder order;
/// unfiled last (label "Unfiled" only when folders exist at all). His
/// explicit filing beats the cwd heuristic — this renders it verbatim.
func groupSessionsByFolder(_ sessions: [HopSession],
                           folders: [HopFolder]) -> [(label: String, rows: [HopSession])] {
    guard !folders.isEmpty else { return [(label: "", rows: sessions)] }
    var out: [(label: String, rows: [HopSession])] = []
    for f in folders {
        let rows = sessions.filter { $0.folderId == f.id }
        if !rows.isEmpty { out.append((label: f.name, rows: rows)) }
    }
    let known = Set(folders.map(\.id))
    let unfiled = sessions.filter { $0.folderId == nil || !known.contains($0.folderId!) }
    if !unfiled.isEmpty { out.append((label: "Unfiled", rows: unfiled)) }
    return out
}

func filterSessions(_ sessions: [HopSession], scope: SessionScope, query: String) -> [HopSession] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    return sessions.filter { s in
        guard !s.isPort else { return false }
        switch scope {
        case .user: if s.createdBy == "agent" { return false }
        case .agent: if s.createdBy != "agent" { return false }
        case .all: break
        }
        // Parked sessions are hidden from BROWSING but still SEARCHABLE, which
        // is exactly how hop's own switcher treats them: parking is "not part
        // of my working set right now", not "gone". A query means you are
        // looking for something specific, and hiding it then would just look
        // broken.
        guard !q.isEmpty else { return !s.parked }
        return s.name.lowercased().contains(q)
            || s.shortCwd.lowercased().contains(q)
            || s.runningApp.lowercased().contains(q)
            || s.tagline.lowercased().contains(q)
    }
}

/// Sessions that should raise a notification or badge: those wanting attention,
/// minus the one being watched right now. Notifying someone about the terminal
/// they are looking at is noise, and it inflates the badge for a session they
/// have already seen.
func alertable(_ sessions: [HopSession], openSession: String?) -> [HopSession] {
    // Ports are excluded: a forwarded port has no terminal to open and cannot
    // ring, so counting one would inflate a badge nobody could clear.
    // Parked sessions don't ring the phone. Parking exists to cut noise, and a
    // notification from something deliberately hidden — which then isn't in the
    // list you open to find it — is the worst of both.
    sessions.filter {
        $0.attention && !$0.isPort && !$0.parked && $0.internalName != openSession
    }
}

/// A 6-digit authenticator code, cleaned. Authenticator apps and password
/// managers hand over "123 456" or "123-456" often enough that pasting one
/// otherwise just fails, and the field is a number pad with no way to correct
/// it comfortably.
func sanitizedCode(_ raw: String) -> String {
    String(raw.filter(\.isNumber).prefix(6))
}

/// The seen-bell baseline for one session, or nil to leave it alone.
///
/// Two cases, and the second was missing: a session this device has never seen
/// gets a silent baseline so its history doesn't arrive as a pile of unread
/// bells. And a session whose bellSeq went BACKWARDS has been killed and
/// recreated under the same name — which hop encourages — so the old marker is
/// meaningless. Left alone, a rebuilt session would stay silent until it rang
/// more times than its predecessor ever did.
func rebaselinedMarker(existing: Int?, bellSeq: Int) -> Int? {
    guard let existing else { return bellSeq }
    return bellSeq < existing ? bellSeq : nil
}

/// Whether a bell still needs a notification, given what this device has
/// already posted for that session.
///
/// The restart case is the same one [[rebaselinedMarker]] exists for, seen
/// from the other side: a bellSeq that went BACKWARDS is a session killed and
/// recreated under the same name, and the record left by its predecessor must
/// not silence the new one. Left out, a rebuilt session stays quiet until it
/// out-rings the session it replaced.
func shouldNotify(bellSeq: Int, lastNotified: Int?) -> Bool {
    guard let lastNotified else { return true }
    return bellSeq != lastNotified
}

/// The line worth putting in a notification: the last thing the session SAID,
/// skipping the shell prompt that follows it.
///
/// Measured origin: a bell rung by `printf 'answer me \a'` produced a banner
/// whose body was "jianzhou@MED-GEN-ML-15 hop2 %" — the prompt returned after
/// the printf, so "the last non-empty line" was the least informative line on
/// the screen. A prompt is recognised narrowly: it ends in %, $ or # AND
/// contains '@' (the user@host shape), or it is a bare ❯ composer line. A
/// line like "CPU 97%" has no '@' and is kept — skipping real status lines
/// would be worse than showing a prompt.
///
/// If every line looks like a prompt, the last one is returned anyway: a
/// wrong-ish body beats an empty notification.
func notificationLine(from preview: String) -> String? {
    let lines = preview.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.count > 2 }
    guard !lines.isEmpty else { return nil }

    func promptLike(_ line: String) -> Bool {
        if line.hasSuffix("❯") || line == "❯" { return true }
        guard let last = line.last, "%$#".contains(last) else { return false }
        return line.contains("@")
    }

    let said = lines.last { !promptLike($0) } ?? lines.last!
    return String(said.prefix(180))
}

/// Who belongs in the in-terminal switcher menu: live, joinable, part of the
/// working set, and not the session you are already in.
///
/// Parked exclusion is the consistency rule: parking hides a session from
/// browsing and silences its bells, so the switcher offering it anyway made
/// "not my working set" mean three different things in three places. A parked
/// session is still reachable by name through the list's filter — deliberate,
/// like everything else about parking. Capped because a Menu is for the
/// twelve most recent, not the whole fleet; the list is the fleet view.
func switcherCandidates(_ sessions: [HopSession], excluding current: String,
                        cap: Int = 12) -> [HopSession] {
    Array(sessions.filter {
        $0.internalName != current && $0.live && !$0.isPort && !$0.parked
    }.prefix(cap))
}

/// What Siri says when asked for status — spoken aloud, so a sentence, not
/// a summary line with dots and parens.
func fleetStatusLine(wanting: Int, total: Int) -> String {
    guard total > 0 else { return "No sessions running." }
    let base = "\(total) session\(total == 1 ? "" : "s") running"
    guard wanting > 0 else { return base + ", nothing waiting on you." }
    return base + ", \(wanting) want\(wanting == 1 ? "s" : "") you."
}

/// The Handoff payload for an open session: hop web's canonical session
/// PATH (`/s/<internalName>/` — what buildSessionPath pushes and the daemon
/// routes with the session injection). The `?room=` query form was the
/// first attempt and FAILED on device: the daemon serves the hub at `/`,
/// which never reads the param — Jian: "almost works! except ?room= is not
/// entering the session anymore". Percent-encoding by hand — names are
/// user text.
func handoffURL(server: String, internalName: String) -> URL? {
    guard !internalName.isEmpty, var comps = URLComponents(string: server),
          comps.host != nil else { return nil }
    let encoded = internalName.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? internalName
    comps.percentEncodedPath = "/s/\(encoded)/"
    return comps.url
}

/// What "Copy screen" puts on the pasteboard: the screen as text someone
/// would paste into a message. The grid pads every line to the session's
/// cols and the tail of a quiet screen is blank rows — strip both, or the
/// paste arrives as a wall of trailing spaces. Nil when nothing remains,
/// which is also what hides the menu item.
func copyableScreen(_ text: String?) -> String? {
    guard let text else { return nil }
    var lines = text.components(separatedBy: "\n").map {
        $0.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
    }
    while lines.last?.isEmpty == true { lines.removeLast() }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
}

/// The toolbar title, at full width: "18 of 21 · 2 want you (1 not shown
/// here) · 1 parked". Pure so both renderings share one source of counts.
func fleetSummaryLine(shown: Int, total: Int, wanting: Int,
                      hiddenWanting: Int, parked: Int) -> String {
    let scope = shown == total
        ? "\(shown) session\(shown == 1 ? "" : "s")"
        : "\(shown) of \(total)"
    let parkedNote = parked > 0 ? " · \(parked) parked" : ""
    guard wanting > 0 else { return "\(scope) · nothing waiting on you\(parkedNote)" }
    // And say so when the thing waiting isn't one of the rows you can see.
    let note = hiddenWanting > 0 ? " (\(hiddenWanting) not shown here)" : ""
    return "\(scope) · \(wanting) want\(wanting == 1 ? "s" : "") you\(note)\(parkedNote)"
}

/// The same facts when the principal slot is too narrow for the sentence —
/// which is exactly when it used to ellipsize at the informative part
/// ("21 sessions · nothing…"). Numbers survive width pressure; filler
/// words don't: "21 · quiet · 1 parked", "18/21 · 2 want you (+1)".
func fleetSummaryCompact(shown: Int, total: Int, wanting: Int,
                         hiddenWanting: Int, parked: Int) -> String {
    let scope = shown == total ? "\(shown)" : "\(shown)/\(total)"
    let parkedNote = parked > 0 ? " · \(parked) parked" : ""
    guard wanting > 0 else { return "\(scope) · quiet\(parkedNote)" }
    let note = hiddenWanting > 0 ? " (+\(hiddenWanting))" : ""
    return "\(scope) · \(wanting) want\(wanting == 1 ? "s" : "") you\(note)\(parkedNote)"
}

/// What each session contributes to the system Spotlight index: the name to
/// find it by, and the tagline (or cwd) so the result card says what it's
/// for. Pure so the shape is testable; the donation side effect stays thin.
func spotlightEntries(_ sessions: [HopSession])
    -> [(id: String, title: String, description: String)] {
    sessions.filter { !$0.isPort }.map {
        (id: $0.internalName,
         title: $0.name,
         description: $0.tagline.isEmpty ? $0.shortCwd : $0.tagline)
    }
}

/// One utterance per session, shared by row and tile. VoiceOver walking a
/// tile's twenty rendered terminal lines element-by-element is noise, not
/// access — the summary is the session, not its pixels.
func sessionSpokenSummary(_ session: HopSession) -> String {
    var parts = [session.name]
    if session.attention { parts.append("wants attention") }
    switch session.phase {
    case .working: parts.append("agent working")
    case .doneUnread: parts.append("agent finished, not yet read")
    case .doneRead: parts.append("agent finished")
    case nil: break
    }
    parts.append(session.live ? "running" : "stopped")
    if !session.runningApp.isEmpty { parts.append(session.runningApp) }
    if session.attached { parts.append("someone attached") }
    if !session.tagline.isEmpty { parts.append(session.tagline) }
    parts.append("active \(session.relativeTime) ago")
    return parts.joined(separator: ", ")
}

/// The query, lit inside its snippet: every case-insensitive occurrence
/// brightened and bolded. The server already FOUND the text — the eye
/// shouldn't have to find it again inside the snippet.
func highlightMatches(in snippet: String, query: String) -> AttributedString {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return AttributedString(snippet) }
    var out = AttributedString()
    var rest = Substring(snippet)
    while let r = rest.range(of: q, options: .caseInsensitive) {
        out += AttributedString(String(rest[..<r.lowerBound]))
        var hit = AttributedString(String(rest[r]))
        hit.foregroundColor = .hopGlow
        hit.font = .caption2.monospaced().weight(.bold)
        out += hit
        rest = rest[r.upperBound...]
    }
    out += AttributedString(String(rest))
    return out
}

/// "Producing output right now": activity within the last ten seconds —
/// the wall's poll cadence plus slack, so the pulse survives between
/// refreshes without lying for long after a session goes quiet. The daemon
/// reports milliseconds; tolerate seconds too rather than trusting a unit
/// across a protocol boundary.
/// The colour an agent session's dot and ring wear for its phase — the same
/// three the web wall uses: working blue, finished-unread green, read quiet.
/// nil = not an agent session in a known phase (liveness colours apply).
func phaseTint(_ phase: HopSession.Phase?) -> Color? {
    switch phase {
    case .working: return .hopWorking
    case .doneUnread: return .hopLive
    case .doneRead: return Color.secondary.opacity(0.45)
    case nil: return nil
    }
}

func sessionBusy(lastActivityAt: Double, now: Double) -> Bool {
    guard lastActivityAt > 0 else { return false }
    let ts = lastActivityAt > 1e12 ? lastActivityAt / 1000 : lastActivityAt
    return now - ts < 10
}

/// Where a NEW session could start: the fleet's own working directories,
/// one per project, most recently active first. The full path rides along
/// because that's what the daemon needs; the label is what a human scans.
func recentProjects(_ sessions: [HopSession], cap: Int = 6) -> [(label: String, path: String)] {
    var seen = Set<String>()
    var out: [(label: String, path: String)] = []
    for s in sessions.sorted(by: { $0.lastActivityAt > $1.lastActivityAt }) {
        guard !s.isPort, !s.cwd.isEmpty else { continue }
        let key = projectKey(s.cwd)
        if seen.insert(key).inserted { out.append((key, s.cwd)) }
        if out.count == cap { break }
    }
    return out
}

/// A session name that arrived from OUTSIDE the app — a Handoff /s/ URL, a
/// Shortcuts phrase, hop://session/, Spotlight, HOP_DEV_OPEN — resolved to
/// the fleet's canonical internalName. Mirrors the daemon's addressing
/// contract (hop2 e4bdd86): exact match first, unique case-folded match
/// second, and an AMBIGUOUS fold resolves to nothing rather than guessing.
/// Internal lookups (pill swipe, fork, list taps) never come through here —
/// daemon-minted names round-trip verbatim and stay exact.
func resolveSessionName(_ raw: String, in sessions: [HopSession]) -> String? {
    if sessions.contains(where: { $0.internalName == raw }) { return raw }
    if let hit = sessions.first(where: { $0.name == raw }) { return hit.internalName }
    let lower = raw.lowercased()
    let internalFolds = sessions.filter { $0.internalName.lowercased() == lower }
    if internalFolds.count == 1 { return internalFolds[0].internalName }
    if internalFolds.count > 1 { return nil }
    let displayFolds = sessions.filter { $0.name.lowercased() == lower }
    return displayFolds.count == 1 ? displayFolds[0].internalName : nil
}

/// The pill-swipe ring: the neighbouring live session in switcher order,
/// wrapping at the ends — Safari's address-bar swipe, for terminals. Nil
/// when there is nowhere to go (lone session, or the current one has
/// already left the fleet — a stale swipe must not jump somewhere random).
func neighborSession(_ sessions: [HopSession], of current: String,
                     step: Int) -> HopSession? {
    let ring = swipeRing(sessions)
    guard ring.count > 1,
          let idx = ring.firstIndex(where: { $0.internalName == current }) else { return nil }
    let n = ring.count
    return ring[((idx + step) % n + n) % n]
}

/// The ordered pill-swipe ring itself — recency first, name as tiebreak. Both
/// switch surfaces (the pill drag and the body swipe) and the swipe filmstrip
/// walk THIS one order, so they can never disagree about who is left of whom.
/// Ordered by RECENCY, not list order (Jian: "swipe left and right between most
/// recent sessions") — the sessions worth a flick are the ones something just
/// happened in; the name tiebreak keeps equally-idle ones from shuffling mid-swipe.
func swipeRing(_ sessions: [HopSession]) -> [HopSession] {
    return sessions.filter { $0.live && !$0.isPort && !$0.parked }
        .sorted { a, b in
            a.lastActivityAt != b.lastActivityAt
                ? a.lastActivityAt > b.lastActivityAt
                : a.name < b.name
        }
}

/// The swipe ring in a STABLE, caller-supplied order (AppModel.swipeOrder):
/// recency, but FROZEN at a browse boundary so the filmstrip neighbours don't
/// reshuffle every time a session prints a line (Jian — the same trap the web
/// switcher's manual mode fixed). Sessions named in `order` keep that order;
/// any live session not yet in it (created since the last freeze) rides at the
/// end by recency, reachable without shoving the frozen neighbours around.
func swipeRing(_ sessions: [HopSession], order: [String], scope: SessionScope) -> [HopSession] {
    // Swiping stays inside the scope you were browsing: on "You" you never
    // land on an agent's session mid-swipe, and vice versa (Jian).
    let live = sessions.filter { $0.live && !$0.isPort && !$0.parked && matchesScope($0.createdBy, scope) }
    let byName = Dictionary(live.map { ($0.internalName, $0) }, uniquingKeysWith: { a, _ in a })
    var out: [HopSession] = []
    var seen = Set<String>()
    for name in order {
        if let s = byName[name], !seen.contains(name) { out.append(s); seen.insert(name) }
    }
    // Newcomers not yet in the frozen order ride at the end by recency.
    for s in live.sorted(by: { $0.lastActivityAt != $1.lastActivityAt
                               ? $0.lastActivityAt > $1.lastActivityAt : $0.name < $1.name })
        where !seen.contains(s.internalName) {
        out.append(s); seen.insert(s.internalName)
    }
    return out
}

/// The scope's origin filter, shared by the browse list and the swipe ring so
/// they never disagree about who is in scope. "You" hides agent-created
/// sessions; "Agents" shows only them; "All" shows both.
/// The ring as seen FROM a session: that session is always in it, at its
/// recency slot, even when the scope filter, a parked flag or a transient
/// !live (mid-reconnect) would drop it. Without this a swipe from an agent
/// session opened under the user scope — or during a blip — found no
/// "current" and silently did nothing (Jian: "swipe to switch session has a
/// chance to fail"). Neighbours still follow the scope.
func swipeRing(_ sessions: [HopSession], order: [String], scope: SessionScope,
               including current: String) -> [HopSession] {
    let ring = swipeRing(sessions, order: order, scope: scope)
    if ring.contains(where: { $0.internalName == current }) { return ring }
    guard let me = sessions.first(where: { $0.internalName == current }) else { return ring }
    // Its slot: where recency would put it among the ring's members.
    let idx = ring.firstIndex(where: { $0.lastActivityAt < me.lastActivityAt }) ?? ring.count
    var out = ring
    out.insert(me, at: idx)
    return out
}

func matchesScope(_ createdBy: String, _ scope: SessionScope) -> Bool {
    switch scope {
    case .user: return createdBy != "agent"
    case .agent: return createdBy == "agent"
    case .all: return true
    }
}



/// The four modifiers a MacBook keyboard actually has. hop's accessory bar
/// carries them as sticky keys (⌃ ⌥ ⇧ ⌘) so a phone can produce any Mac
/// chord; everything else on the bar is a real Mac key too (Jian: "you need
/// to be able to simulate a full mac keyboard … other keys that do not
/// exist in a macbook pro keyboard i also do not need them").
struct KeyMods: OptionSet {
    let rawValue: Int
    static let shift = KeyMods(rawValue: 1)
    static let alt   = KeyMods(rawValue: 2)      // ⌥ option
    static let ctrl  = KeyMods(rawValue: 4)
    static let cmd   = KeyMods(rawValue: 8)      // ⌘ super
    /// xterm/kitty's modifier parameter: 1 + shift + 2·alt + 4·ctrl + 8·super.
    var param: Int { 1 + rawValue }
    var isEmpty: Bool { rawValue == 0 }
}

/// CSI-u: the only encoding that can carry ⌘ (and the only one that can
/// distinguish e.g. ⌃⇧A from ⌃A). Apps opt in — claude and codex parse it —
/// so callers must gate on that; a shell would print the bytes as junk.
func csiU(_ codepoint: Int, mods: KeyMods) -> String {
    "\u{1b}[\(codepoint);\(mods.param)u"
}

/// The byte sequence for an accessory arrow under modifiers — xterm's
/// modified-arrow form, CSI 1;<param> <letter>; a bare arrow stays CSI
/// <letter>. The shift* keys carry shift themselves. Nil for non-arrow keys.
func arrowSequence(_ key: AccessoryKey, shift: Bool, alt: Bool, ctrl: Bool, cmd: Bool = false) -> String? {
    let letter: Character, held: Bool
    switch key {
    case .up: (letter, held) = ("A", false)
    case .down: (letter, held) = ("B", false)
    case .right: (letter, held) = ("C", false)
    case .left: (letter, held) = ("D", false)
    case .shiftUp: (letter, held) = ("A", true)
    case .shiftDown: (letter, held) = ("B", true)
    case .shiftRight: (letter, held) = ("C", true)
    case .shiftLeft: (letter, held) = ("D", true)
    default: return nil
    }
    var mods: KeyMods = []
    if shift || held { mods.insert(.shift) }
    if alt { mods.insert(.alt) }
    if ctrl { mods.insert(.ctrl) }
    if cmd { mods.insert(.cmd) }
    return mods.isEmpty ? "\u{1b}[\(letter)" : "\u{1b}[1;\(mods.param)\(letter)"
}

/// What ONE typed character becomes under armed modifiers, in the encoding a
/// terminal actually understands:
///   ⌃ alone       the control code (⌃A = 0x01) — universal
///   ⌥ alone       ESC prefix (meta), the classic option encoding
///   ⌃⌥           ESC + control code
///   ⌘ anything    CSI-u, which is the ONLY form that carries super — and
///                 only when the app negotiated it (`enhanced`); nil means
///                 "this chord cannot reach that app", so the caller can say
///                 so instead of sending junk.
/// Shift is deliberately NOT applied to letters: the on-screen keyboard
/// already produces the capital, and doubling it would send the wrong key.
/// It still rides along in the CSI-u bitmask, where it is meaningful.
func modifiedKey(_ ch: Character, shift: Bool, alt: Bool, ctrl: Bool, cmd: Bool,
                 enhanced: Bool) -> String? {
    var mods: KeyMods = []
    if shift { mods.insert(.shift) }
    if alt { mods.insert(.alt) }
    if ctrl { mods.insert(.ctrl) }
    if cmd { mods.insert(.cmd) }
    if mods.isEmpty { return String(ch) }
    guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return nil }
    if cmd { return enhanced ? csiU(Int(scalar.value), mods: mods) : nil }
    var out = ""
    if alt { out += "\u{1b}" }
    if ctrl {
        // `.first`, never `Character(ch.lowercased())`: lowercasing can yield
        // more than one character and that initialiser traps on it.
        guard let low = ch.lowercased().first, let ascii = low.asciiValue,
              ascii >= 0x40 || ascii == 0x20
            else { return enhanced ? csiU(Int(scalar.value), mods: mods) : nil }
        out += String(UnicodeScalar(ascii & 0x1f))
    } else {
        out += String(ch)
    }
    return out
}

/// Does releasing a session swipe switch? Exactly when the filmstrip is
/// lighting a different session (`lit`) and the gesture ENDED rather than
/// being cancelled — what you see highlighted is what you get, with no
/// distance or velocity gate to veto it.
func swipeShouldCommit(lit: Bool, released: Bool) -> Bool { lit && released }


/// The arrow keys that walk a terminal cursor from (fromRow, fromCol) to
/// (toRow, toCol) — hop's tap-to-position for apps that take no mouse.
///
/// Vertical first, then horizontal, and the horizontal leg starts from where
/// the vertical leg LANDS rather than where it began: every composer hop
/// meets — claude's and codex's, and zsh's own `up-line-or-history` — keeps
/// the column when the target line is long enough and clamps to the line's
/// end when it isn't. `targetLineLength` is that clamp, and it also bounds
/// the destination: tapping past the end of a line lands at its end.
///
/// Nil means "don't guess": nothing to do, or further than `maxRows`.
///
/// That bound was 8, which is why tapping an earlier line of a longer
/// message did nothing (Jian: "tap to position cursor is not working in
/// codex very well") — a phone composer runs well past eight lines. Driving
/// a real codex PTY settled what the bound is actually protecting against:
///   • codex — an Up past the top of its composer is a NO-OP. Overshooting
///     costs nothing at all.
///   • zsh — `up-line-or-history` walks a multiline buffer first and only
///     reaches history from a single-line one, and Down brings it back.
///   • bash — Up is history recall, recoverable but ugly in bulk.
/// So the rail only has to stop a mis-tap from spraying arrows across a
/// whole screen of scrollback; one composer's worth of travel is safe.
func cursorWalk(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int,
                targetLineLength: Int, maxRows: Int = 24) -> String? {
    let dy = toRow - fromRow
    guard abs(dy) <= maxRows else { return nil }
    let target = max(0, min(toCol, targetLineLength))
    var seq = ""
    if dy != 0 {
        seq += String(repeating: dy > 0 ? "\u{1b}[B" : "\u{1b}[A", count: abs(dy))
    }
    let landed = dy == 0 ? fromCol : min(fromCol, targetLineLength)
    let dx = target - landed
    if dx != 0 {
        seq += String(repeating: dx > 0 ? "\u{1b}[C" : "\u{1b}[D", count: abs(dx))
    }
    return seq.isEmpty ? nil : seq
}


/// Should this phone put a size on the wire right now?
///
/// Every SwiftTerm fit change used to send one, and a keyboard settle churns
/// the fit dozens of times in a few milliseconds. Each send is an ELECTION
/// event: while this client owns the grid the server applies it, a peer at a
/// different width answers with its own, we adopt, the adopt re-fits, and the
/// re-fit sends again — the page flapping between two sizes several times a
/// second (Jian's 2026-09-26 trace: `58x34 OURS` → `121x32 ADOPT-FOREIGN`,
/// three round trips in 70ms).
///
/// Two rules break the loop without giving up the right to own our size:
///   • say nothing for `cooldown` after ADOPTING a peer's grid — that adopt
///     is what provokes the re-fit, and answering it immediately is the
///     fight itself;
///   • don't repeat dimensions we already sent inside `repeatWindow`.
/// A human act (a keystroke, the size chip) claims outright and is never
/// gated by this.
func shouldDeclareSize(cols: Int, rows: Int, now: TimeInterval,
                       lastSent: (cols: Int, rows: Int, at: TimeInterval)?,
                       lastForeignAdoptAt: TimeInterval?,
                       cooldown: TimeInterval = 2,
                       repeatWindow: TimeInterval = 2) -> Bool {
    guard cols > 1, rows > 1 else { return false }
    if let adopted = lastForeignAdoptAt, now - adopted < cooldown { return false }
    if let last = lastSent, last.cols == cols, last.rows == rows,
       now - last.at < repeatWindow { return false }
    return true
}
