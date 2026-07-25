import SwiftUI

// Server + account. Until this existed, the only way off a server — or off an
// account, on a phone you were handing to someone — was deleting the app.
struct AccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    /// Shows the git description too, so "is the fix on my phone?" is a
    /// question the Account sheet can answer.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        let desc = info?["HopGitDescribe"] as? String ?? ""
        return desc.isEmpty || desc.hasPrefix("$(") ? "\(v) (\(b))" : "\(v) (\(b)) · \(desc)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    LabeledContent("Address") {
                        Text(model.normalizedServerURL.replacingOccurrences(of: "https://", with: ""))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Sessions") {
                        Text("\(model.sessions.count)").foregroundStyle(.secondary)
                    }
                    if let err = model.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Signs out of this server and forgets the saved password. Changing servers starts here too — sign out, then enter a different address.")
                }
                Section {
                    LabeledContent("Version") { Text(version).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Sign out of \(model.normalizedServerURL)?",
                                isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    model.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
