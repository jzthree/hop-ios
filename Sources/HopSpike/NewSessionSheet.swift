import SwiftUI

/// What the "+" sheet asks the daemon for — the web create form's fields.
struct NewSessionRequest {
    let name: String
    let cwd: String?          // nil = daemon default
    let startup: String?      // "claude" / "codex"; nil = a plain shell
    let agentHome: String?    // that agent's account; nil = its default
}

/// The "+" flow, grown up from a bare alert. A name is still the only
/// requirement — but the sheet also offers WHAT to start (a shell, or
/// straight into Claude or Codex, under which account) and WHERE: the
/// fleet's own project directories as chips, most recent first, or any
/// directory on the host typed with completion (the web's CwdField).
struct NewSessionSheet: View {
    @EnvironmentObject var model: AppModel
    @Binding var name: String
    var onCreate: (NewSessionRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newSessionType") private var kind = "terminal"
    @State private var home = ""                 // "" = the agent's default account
    @State private var cwdText = ""              // "" = daemon default
    @State private var suggestions: [DirEntry] = []
    @State private var hostHome: String?
    @FocusState private var nameFocused: Bool
    @FocusState private var cwdFocused: Bool

    private var projects: [(label: String, path: String)] {
        recentProjects(model.sessions)
    }
    private var trimmed: String {
        name.trimmingCharacters(in: .whitespaces)
    }
    private var homes: [AgentHome] { kind == "terminal" ? [] : (model.agentHomes[kind] ?? []) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("New session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                TextField("name", text: $name)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.hopLine(0.08), lineWidth: 0.5))
                    .onSubmit { create() }
                Text("Letters, numbers, - and _")
                    .font(.caption2).foregroundStyle(.tertiary)

                Picker("Start", selection: $kind) {
                    Text("Shell").tag("terminal")
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, _ in home = "" }
                .accessibilityIdentifier("new-session-type")

                if homes.count > 1 {
                    HStack {
                        Text("Account").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("Account", selection: $home) {
                            ForEach(homes) { h in
                                Text(h.described).tag(h.isDefault ? "" : h.dir)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.hopGlow)
                    }
                }

                Text("Start in")
                    .font(.caption).foregroundStyle(.secondary)
                if !projects.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Default", selected: cwdText.isEmpty) { cwdText = "" }
                            ForEach(projects, id: \.path) { p in
                                chip(p.label, selected: cwdText == p.path) { cwdText = p.path }
                            }
                        }
                    }
                }
                TextField("any directory on the host — ~/Code/…", text: $cwdText)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($cwdFocused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.hopLine(0.08), lineWidth: 0.5))
                    .onSubmit { create() }
                    .accessibilityIdentifier("new-session-cwd")
                if cwdFocused && !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions.prefix(6)) { e in
                            Button {
                                cwdText = tilde(e.path) + "/"
                            } label: {
                                Label(e.name, systemImage: "folder")
                                    .font(.footnote.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    create()
                } label: {
                    Text("Create")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.hopPurple)
                .disabled(trimmed.isEmpty)
            }
            .padding(18)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.hopSurface)
        .onAppear { nameFocused = true }
        .task { if model.agentHomes.isEmpty { await model.loadAgentHomes() } }
        // Completion asks the HOST — the phone cannot see its disk. Debounced
        // by the task restarting on every keystroke.
        .task(id: cwdText) {
            let q = cwdText.trimmingCharacters(in: .whitespaces)
            guard cwdFocused, !q.isEmpty else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let r = await model.completeDirectory(q)
            guard !Task.isCancelled else { return }
            if let h = r.home { hostHome = h }
            suggestions = r.entries
        }
    }

    /// The host's home shown as "~", the way you would type it.
    private func tilde(_ path: String) -> String {
        guard let h = hostHome, path == h || path.hasPrefix(h + "/") else { return path }
        return "~" + path.dropFirst(h.count)
    }

    /// The daemon wants an absolute path: expand "~", drop a trailing "/".
    private var resolvedCwd: String? {
        var p = cwdText.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return nil }
        if p.hasPrefix("~"), let h = hostHome { p = h + p.dropFirst() }
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        let agent = kind == "terminal" ? nil : kind
        onCreate(NewSessionRequest(name: trimmed, cwd: resolvedCwd, startup: agent,
                                   agentHome: agent != nil && !home.isEmpty ? home : nil))
        dismiss()
    }

    private func chip(_ label: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.monospaced())
                .lineLimit(1)
                .foregroundStyle(selected ? .white : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.hopPurple.opacity(0.85)
                                     : Color.hopLine(0.06),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? Color.hopGlow.opacity(0.5) : Color.hopLine(0.05),
                    lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
