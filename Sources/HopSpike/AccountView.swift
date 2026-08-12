import SwiftUI

// Server + account. Until this existed, the only way off a server — or off an
// account, on a phone you were handing to someone — was deleting the app.
struct AccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var bioLockOn = BioLock.shared.enabled
    @State private var copied = false
    @State private var enrolled = false
    @State private var sent = false
    @State private var sending = false
    @StateObject private var passkey = PasskeyAuth()

    /// Hand the trace to the host. Best effort and quiet about the shape of
    /// failure: if it doesn't land, Copy is still right there.
    @MainActor private func sendDiagnostics() async -> Bool {
        guard !sending, let base = URL(string: model.normalizedServerURL) else { return false }
        sending = true
        defer { sending = false }
        var req = URLRequest(url: base.appendingPathComponent("api/diagnostics"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "label": "iphone", "text": diagnostics
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
    @StateObject private var network = NetworkConditions.shared
    @StateObject private var notifier = HopNotifier.shared
    @StateObject private var push = PushRegistry.shared

    /// The state worth knowing when something is wrong on a phone I can't
    /// attach a debugger to. Deliberately no session names, no cwds and no
    /// output: this gets pasted into a chat, and a fleet's session names say
    /// more about someone's work than they'd expect.
    private var diagnostics: String {
        let net = !network.isOnline ? "offline"
            : network.isConstrained ? "low-data"
            : network.isExpensive ? "cellular" : "wifi"
        return """
        hop-ios \(version)
        server: \(model.normalizedServerURL)
        authenticated: \(model.authenticated), sessions: \(model.sessions.count),         attention: \(model.sessions.filter(\.attention).count)
        network: \(net)
        notifications: \(notifier.enabled ? "on" : "off")
        apns: \(push.deviceToken.map { String($0.prefix(16)) + "…" } ?? push.failure ?? "not registered")
        background: \(BackgroundRefresh.lastSchedule) / \(BackgroundRefresh.lastRun)
        lastError: \(model.lastError ?? "none")

        keyboard/fit trace (newest last):
        \(KBLog.dump())
        """
    }

    /// Shows the git description too, so "is the fix on my phone?" is a
    /// question the Account sheet can answer.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        let desc = info?["HopGitDescribe"] as? String ?? ""
        // Says which BUILD, not just which commit. The phone ran an
        // unoptimised Debug build for its whole life without anything on
        // screen saying so, while the scroll feel was being judged on it.
        // A debug build is a fair explanation for "this feels sluggish", and
        // it should never have to be inferred.
#if DEBUG
        let config = " · debug"
#else
        let config = ""
#endif
        let base = desc.isEmpty || desc.hasPrefix("$(") ? "\(v) (\(b))" : "\(v) (\(b)) · \(desc)"
        return base + config
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
                        // Excluding ports, because that is what "sessions"
                        // means everywhere else in the app — a count here that
                        // disagrees with the list is worse than no count.
                        Text("\(model.terminalSessions.count)").foregroundStyle(.secondary)
                    }
                    if let err = model.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section {
                    Toggle(isOn: Binding(
                        get: { bioLockOn },
                        set: { on in
                            bioLockOn = on
                            BioLock.shared.enabled = on
                        })) {
                        Label("Require \(BioLock.biometryName)", systemImage: "faceid")
                    }
                    // A passkey minted ON this phone, so Face ID sign-in owes
                    // nothing to iCloud syncing the laptop's credential over.
                    Button {
                        enrolled = false
                        Task { enrolled = await passkey.enroll(server: model.normalizedServerURL) }
                    } label: {
                        Label(enrolled ? "Passkey added" : "Add \(BioLock.biometryName) sign-in",
                              systemImage: enrolled ? "checkmark.circle.fill" : "person.badge.key.fill")
                    }
                    .disabled(passkey.busy || enrolled)
                    if let pkErr = passkey.error {
                        Text(pkErr).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Locks hop when the app leaves the screen and on launch. Your passcode is the fallback when \(BioLock.biometryName) fails; the lock screen can always sign out. Adding \(BioLock.biometryName) sign-in enrolls a passkey on this phone — the next sign-in needs no password and no code.")
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Signs out of this server and forgets the saved password. Changing servers starts here too — sign out, then enter a different address.")
                }
                Section {
                    LabeledContent("Version") { Text(version).foregroundStyle(.secondary) }
                    Button {
                        UIPasteboard.general.string = diagnostics
                        #if DEBUG
                        // Same side channel as Copy screen: the UI test can't
                        // read the pasteboard (iOS 16 background-paste denial).
                        if let m = ProcessInfo.processInfo.environment["HOP_COPY_MARKER"] {
                            try? diagnostics.write(toFile: m, atomically: true, encoding: .utf8)
                        }
                        #endif
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy diagnostics",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    // The pasteboard is the wrong pipe when the person who
                    // needs this is an agent on the other side of the tunnel
                    // (Jian: "there is no way for me to copy any diagnostic
                    // log for you"). This puts it on the host, where a session
                    // can just read it.
                    Button {
                        sent = false
                        Task { sent = await sendDiagnostics() }
                    } label: {
                        Label(sent ? "Sent to hop" : "Send diagnostics to hop",
                              systemImage: sent ? "checkmark.circle.fill" : "paperplane")
                    }
                    .disabled(sending || sent)
                } footer: {
                    Text("Version, server, network state and counts. Copy pastes it here; Send puts it on the host, in ~/.hop2/diagnostics, where an agent can read it without you relaying anything.")
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
