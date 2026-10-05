import SwiftUI
import UIKit

// mybot's morning pulse, rendered natively.
//
// mybot (on the host) writes pulse.json into the directory the daemon serves
// under /assets/ — beside digest.json — so this reads it the same way the
// briefing is read: a static file behind the cookie the app already holds.
// The two are complementary: the digest says what the fleet needs from you;
// the pulse brings ideas and things that slipped through the cracks.
//
// A follow-up is one tap: create a session in the item's folder and type the
// one-line launch command mybot prepared (the task itself sits in a file on
// the host, so nothing long crosses the terminal), then open that session.

struct MybotPulseSection: Identifiable, Equatable {
    let id: String
    let kind: String      // intro | overlooked | note | article
    let title: String
    let body: String
}

struct MybotPulseAction: Equatable {
    let id: String
    let label: String
    let cwd: String
    let sessionName: String
    let command: String
    /// The live hop session that already owns this item, if any — the
    /// preferred destination: a one-line message instead of a new agent.
    let targetInternalName: String?
    let targetName: String?
    let message: String?
}

struct MybotPulse: Identifiable, Equatable {
    var id: String { engine }
    let engine: String
    let label: String
    let date: String
    let title: String
    let sections: [MybotPulseSection]
    let actions: [String: MybotPulseAction]

    var intro: String { sections.first(where: { $0.kind == "intro" })?.body ?? "" }
    var overlookedCount: Int { sections.filter { $0.kind == "overlooked" }.count }
    var articleCount: Int { sections.filter { $0.kind == "article" }.count }
}

struct MybotPulseFeed: Equatable {
    let generatedAt: String
    let pulses: [MybotPulse]

    init?(json: [String: Any]) {
        guard let raw = json["pulses"] as? [[String: Any]] else { return nil }
        generatedAt = (json["generated_at"] as? String) ?? ""
        pulses = raw.compactMap { p in
            guard let engine = p["engine"] as? String, let date = p["date"] as? String else { return nil }
            let sections = ((p["sections"] as? [[String: Any]]) ?? []).enumerated().map { i, s in
                MybotPulseSection(id: (s["id"] as? String) ?? "s\(i)",
                                  kind: (s["kind"] as? String) ?? "note",
                                  title: (s["title"] as? String) ?? "",
                                  body: (s["body"] as? String) ?? "")
            }
            var actions: [String: MybotPulseAction] = [:]
            for a in (p["actions"] as? [[String: Any]]) ?? [] {
                guard let id = a["id"] as? String,
                      let name = a["session_name"] as? String,
                      let command = a["command"] as? String else { continue }
                actions[id] = MybotPulseAction(id: id, label: (a["label"] as? String) ?? "Follow up",
                                               cwd: (a["cwd"] as? String) ?? "", sessionName: name,
                                               command: command,
                                               targetInternalName: a["target_internal_name"] as? String,
                                               targetName: a["target_name"] as? String,
                                               message: a["message"] as? String)
            }
            return MybotPulse(engine: engine, label: (p["label"] as? String) ?? engine, date: date,
                              title: (p["title"] as? String) ?? "Morning pulse",
                              sections: sections, actions: actions)
        }
        if pulses.isEmpty { return nil }
    }
}

enum PulseText {
    /// Paragraphs and "- " bullets joined into ONE attributed string, so a
    /// long-press selection runs across the whole section.
    static func attributed(_ text: String) -> AttributedString {
        var blocks: [String] = []
        var paragraph: [String] = []
        func flush() { if !paragraph.isEmpty { blocks.append(paragraph.joined(separator: " ")); paragraph = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { flush(); blocks.append(line); continue }
            paragraph.append(line)
        }
        flush()
        var out = AttributedString()
        for (i, block) in blocks.enumerated() {
            if i > 0 { out += AttributedString("\n\n") }
            let bullet = block.hasPrefix("- ") || block.hasPrefix("* ")
            let body = bullet ? String(block.dropFirst(2)) : block
            if bullet { out += AttributedString("•  ") }
            out += (try? AttributedString(markdown: body,
                                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(body)
        }
        return out
    }
}

/// The compact card on the wall, under the hop briefing.
struct MybotPulseCard: View {
    let pulse: MybotPulse
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.horizon.fill").foregroundStyle(Color.hopGlow)
                    Text(pulse.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if !pulse.intro.isEmpty {
                    Text(PulseText.attributed(pulse.intro)).font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(3).multilineTextAlignment(.leading)
                }
                Text("\(pulse.overlookedCount) may be overlooked · \(pulse.articleCount) idea\(pulse.articleCount == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.hopSurface))
        }
        .buttonStyle(.plain)
    }
}

/// The full page: native reading, selectable text, copy, one-tap follow-ups.
struct MybotPulsePage: View {
    let feed: MybotPulseFeed
    /// Existing session names, so a follow-up already started reads "Open".
    let existing: Set<String>
    let onFollowUp: (MybotPulseAction) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mybotPulseEngine") private var engine = "claude"
    @State private var launching: String?
    @State private var failed: String?
    @State private var copied: String?

    private var pulse: MybotPulse? { feed.pulses.first { $0.engine == engine } ?? feed.pulses.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let pulse {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(pulse.sections) { section in
                            sectionView(section, pulse: pulse)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(pulse?.title ?? "Morning pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if feed.pulses.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Picker("Engine", selection: $engine) {
                            ForEach(feed.pulses) { Text($0.label).tag($0.engine) }
                        }
                        .pickerStyle(.segmented).frame(width: 170)
                    }
                }
            }
            .alert("Couldn't start the follow-up", isPresented: Binding(
                get: { failed != nil }, set: { if !$0 { failed = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(failed ?? "") }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: MybotPulseSection, pulse: MybotPulse) -> some View {
        switch section.kind {
        case "intro":
            Text(PulseText.attributed(section.body)).font(.body.weight(.medium))
                .textSelection(.enabled)
        case "overlooked":
            VStack(alignment: .leading, spacing: 8) {
                if pulse.sections.first(where: { $0.kind == "overlooked" })?.id == section.id {
                    Text("YOU MAY HAVE OVERLOOKED").font(.caption2.weight(.heavy)).tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(PulseText.attributed(section.body)).font(.callout).textSelection(.enabled)
                    controls(section: section, pulse: pulse)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.hopSurface))
            }
        case "article":
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text(section.title).font(.title3.weight(.bold)).textSelection(.enabled)
                controls(section: section, pulse: pulse)
                Text(PulseText.attributed(section.body)).font(.body).lineSpacing(3).textSelection(.enabled)
            }
        default:
            Text(PulseText.attributed(section.body)).font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func buttonTitle(_ action: MybotPulseAction) -> String {
        if let target = action.targetName { return "Send to \(target)" }
        return existing.contains(action.sessionName) ? "Open follow-up" : action.label
    }

    @ViewBuilder
    private func controls(section: MybotPulseSection, pulse: MybotPulse) -> some View {
        HStack(spacing: 12) {
            if let action = pulse.actions[section.id] {
                if launching == action.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task {
                            launching = action.id
                            let ok = await onFollowUp(action)
                            launching = nil
                            if ok { dismiss() } else { failed = "hop didn't accept the new session. Check the connection and try again." }
                        }
                    } label: {
                        Label(buttonTitle(action),
                              systemImage: action.targetName != nil ? "arrowshape.turn.up.right"
                                  : existing.contains(action.sessionName) ? "arrow.right.circle" : "arrow.up.forward.app")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered).tint(Color.hopGlow)
                }
            }
            Spacer()
            Button {
                let text = section.title.isEmpty ? section.body : "\(section.title)\n\n\(section.body)"
                UIPasteboard.general.string = text
                copied = section.id
                Task { try? await Task.sleep(for: .seconds(1.5)); if copied == section.id { copied = nil } }
            } label: {
                Label(copied == section.id ? "Copied" : "Copy",
                      systemImage: copied == section.id ? "checkmark" : "doc.on.doc")
                    .font(.footnote)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
}
