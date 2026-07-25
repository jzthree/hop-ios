import SwiftUI
import UIKit

extension Color {
    static let hopPurple = Color(red: 0x7c / 255, green: 0x3a / 255, blue: 0xed / 255)
    static let hopGlow = Color(red: 0xa8 / 255, green: 0x55 / 255, blue: 0xf7 / 255)

    /// One surface palette instead of ad-hoc greys. The base is the terminal's
    /// own background (#0d1117, hop's web colour), and the raised tones are the
    /// values that go with it — so chrome reads as the same material as the
    /// terminal rather than three unrelated darks sitting next to each other.
    static let hopSurface = Color(hex: 0x0d1117)      // terminal, page
    static let hopRaised = Color(hex: 0x161b22)       // nav bar, key bar
    static let hopKey = Color(hex: 0x272e38)          // key caps
    static let hopKeyArmed = Color(hex: 0x9d7bf5)     // armed modifier
    /// Attention. Amber rather than red: red in a list of agent sessions reads
    /// as "something failed", and a session wanting you usually hasn't.
    static let hopAttention = Color(hex: 0xf0a53a)

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

extension UIColor {
    static let hopSurface = UIColor(red: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1)
    static let hopRaised = UIColor(red: 0x16 / 255, green: 0x1b / 255, blue: 0x22 / 255, alpha: 1)
    static let hopKey = UIColor(red: 0x27 / 255, green: 0x2e / 255, blue: 0x38 / 255, alpha: 1)
}

@main
struct HopApp: App {
    @UIApplicationDelegateAdaptor(HopAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must register before the app finishes launching.
        BackgroundRefresh.register(model: AppModel.shared)
        // Dev-only: set the navigation request HERE, before any view exists,
        // so `make sim OPEN=X` exercises the real cold-launch path — the one a
        // quick action or a notification tap takes, where onChange can never
        // fire because the value predates the view.
        if let want = ProcessInfo.processInfo.environment["HOP_DEV_OPEN"] {
            AppModel.shared.requestedSession = want
        }
        // Dev-only: let `make sim GROUP=1` land on the grouped list without
        // hand-toggling a menu the screenshot loop can't reach.
        if ProcessInfo.processInfo.environment["HOP_DEV_GROUP"] == "1" {
            UserDefaults.standard.register(defaults: ["groupByProject": true])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(.hopPurple)
                .preferredColorScheme(.dark)
                .task {
                    HopNotifier.shared.configure()
                    await model.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    model.foreground = phase == .active
                    // Ask for a background slot whenever we leave the
                    // foreground, so bells rung in a pocket still land.
                    if phase == .background { BackgroundRefresh.schedule() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.checkingAuth {
            VStack(spacing: 12) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.hopPurple)
                ProgressView()
            }
        } else if model.authenticated {
            SessionsView()
        } else {
            LoginView()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var totp = ""
    @State private var busy = false
    @State private var remember = true
    @FocusState private var focus: Field?
    enum Field { case password, totp }

    private func loadSavedPassword() {
        if let saved = Keychain.read(account: model.normalizedServerURL) {
            password = saved
            remember = true
        }
    }

    /// Focus set synchronously in onAppear is silently dropped — the view
    /// isn't in a window yet, so the keyboard never comes up. Yield first.
    private func focusFirstEmptyField() async {
        try? await Task.sleep(for: .milliseconds(400))
        focus = password.isEmpty ? .password : .totp
    }

    private func submit() {
        busy = true
        Task {
            await model.login(password: password, totp: totp)
            if model.authenticated {
                // Only the password — never the TOTP secret, which would put
                // both factors on one device.
                if remember { Keychain.save(password, account: model.normalizedServerURL) }
                else { Keychain.delete(account: model.normalizedServerURL) }
            } else {
                totp = ""            // a code is single-use; a failed one is spent
                focus = .totp
            }
            busy = false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "hare.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.hopPurple.gradient)
                        .shadow(color: .hopGlow.opacity(0.45), radius: 18)
                    Text("hop")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                    Text("terminals for humans + agents")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("server", text: $model.serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    SecureField("password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    TextField("authenticator code", text: $totp)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .totp)
                        .onChange(of: totp) { _, raw in
                            // A number pad has no return key, so there is no
                            // "submit" gesture at all — and a code copied from
                            // an authenticator often arrives as "123 456".
                            // Clean it, and go the moment it's complete.
                            let clean = sanitizedCode(raw)
                            if clean != raw { totp = clean }
                            if clean.count == 6, !busy, !password.isEmpty { submit() }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
                .font(.system(.body, design: .monospaced))

                Toggle(isOn: $remember) {
                    Text("Remember password on this device")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)

                if model.sessionExpired && model.lastError == nil {
                    // fixedSize, or a Label silently truncates to one line
                    // and eats the explanation it exists to give.
                    Label("Session expired — hop signs you out after 7 days.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let err = model.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    submit()
                } label: {
                    if busy {
                        ProgressView().frame(maxWidth: .infinity).padding(6)
                    } else {
                        Text("Connect").font(.headline).frame(maxWidth: .infinity).padding(6)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || password.isEmpty || totp.count < 6)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
            .task {
                loadSavedPassword()
                await focusFirstEmptyField()
            }
            .onChange(of: model.normalizedServerURL) { _, _ in
                // A password belongs to a server. Editing the address must not
                // leave the previous server's password sitting in the field.
                password = ""
                loadSavedPassword()
            }
        }
    }
}
