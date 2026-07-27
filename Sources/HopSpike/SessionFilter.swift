import Foundation

// Pure list-shaping, extracted from the view so it can be unit-tested:
// which sessions a scope shows, and how a filter query matches.
enum SessionScope: String, CaseIterable {
    case user = "You", agent = "Agents", all = "All"
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

