import Foundation
import SwiftUI

// Pure list-shaping, extracted from the view so it can be unit-tested:
// which sessions a scope shows, and how a filter query matches.
enum SessionScope: String, CaseIterable {
    case user = "You", agent = "Agents", all = "All"
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

/// The pill-swipe ring: the neighbouring live session in switcher order,
/// wrapping at the ends — Safari's address-bar swipe, for terminals. Nil
/// when there is nowhere to go (lone session, or the current one has
/// already left the fleet — a stale swipe must not jump somewhere random).
func neighborSession(_ sessions: [HopSession], of current: String,
                     step: Int) -> HopSession? {
    let ring = sessions.filter { $0.live && !$0.isPort && !$0.parked }
    guard ring.count > 1,
          let idx = ring.firstIndex(where: { $0.internalName == current }) else { return nil }
    let n = ring.count
    return ring[((idx + step) % n + n) % n]
}

