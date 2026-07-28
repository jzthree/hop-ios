import SwiftUI

/// The "+" flow, grown up from a bare alert. A name is still the only
/// requirement — but the sheet also offers WHERE to start: the fleet's own
/// project directories, one chip per project, most recent first. On a phone
/// the working directory was the thing you couldn't choose at all; picking
/// it from what's already running covers nearly every real case without a
/// file browser.
struct NewSessionSheet: View {
    @EnvironmentObject var model: AppModel
    @Binding var name: String
    var onCreate: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cwd: String?              // nil = daemon default
    @FocusState private var nameFocused: Bool

    private var projects: [(label: String, path: String)] {
        recentProjects(model.sessions)
    }
    private var trimmed: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
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
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .onSubmit { create() }
            Text("Letters, numbers, - and _")
                .font(.caption2).foregroundStyle(.tertiary)

            if !projects.isEmpty {
                Text("Start in")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Default", selected: cwd == nil) { cwd = nil }
                        ForEach(projects, id: \.path) { p in
                            chip(p.label, selected: cwd == p.path) { cwd = p.path }
                        }
                    }
                }
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
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.hopSurface)
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, cwd)
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
                                     : Color.white.opacity(0.06),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? Color.hopGlow.opacity(0.5) : Color.white.opacity(0.05),
                    lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
