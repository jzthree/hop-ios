import SwiftUI

/// Answering an agent means SEEING its question. The old alert showed one
/// trimmed line of context; this sheet shows the session's last meaningful
/// rows in their real colours above the composer — the same ink the tiles
/// and peeks use — so replying from the list carries the context a terminal
/// visit would, without the visit.
struct ReplySheet: View {
    let session: HopSession
    let screen: ScreenPreview?
    let fallback: String
    var onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var dotColor: Color {
        session.attention ? .hopAttention : session.live ? .hopLive : .hopDead
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: dotColor.opacity(0.9), radius: 3)
                Text("Reply to \(session.name)")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                if !session.runningApp.isEmpty {
                    let tint = appTint(session.runningApp)
                    Text(session.runningApp)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tint.opacity(0.16), in: Capsule())
                        .foregroundStyle(tint)
                }
            }

            // The question, in ink. Falls back to the plain preview, then the
            // tagline — something is always above the composer.
            Group {
                if let screen, let snip = TileInk.snippet(screen, lines: 7) {
                    Text(snip)
                } else {
                    Text(fallback.isEmpty ? session.tagline : fallback)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .lineSpacing(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(hex: 0x090b10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))

            HStack(spacing: 8) {
                TextField("Answer…", text: $text)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { send() }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31))
                }
                .tint(.hopPurple)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.hopSurface)
        .onAppear { focused = true }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onSend(t)
        dismiss()
    }
}
