import CoreSpotlight
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
    /// State dots share one pair of designed tones instead of system .green /
    /// .red, whose saturation belongs to traffic lights, not a dark UI.
    static let hopLive = Color(hex: 0x35d47a)
    static let hopDead = Color(hex: 0xd95a6b)
    /// Card material: dark surfaces read as SHAPES only when lit from above —
    /// a slightly lifted top tone falling to the page's own dark, under a
    /// hairline that catches light on the top edge and fades out by the
    /// bottom. Flat fills next to these look like holes.
    static let hopCardTop = Color(hex: 0x1a212c)
    static let hopCardBottom = Color(hex: 0x10151c)

    static var hopCard: LinearGradient {
        LinearGradient(colors: [.hopCardTop, .hopCardBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    static var hopHairline: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)],
                       startPoint: .top, endPoint: .bottom)
    }

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
    static let hopKeyArmed = UIColor(red: 0x9d / 255, green: 0x7b / 255, blue: 0xf5 / 255, alpha: 1)

    /// The cap "lights" under the finger: a step toward white, not a dim —
    /// physical keys brighten when pressed, and dimming reads as disabled.
    var hopPressed: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let k: CGFloat = 0.16
        return UIColor(red: r + (1 - r) * k, green: g + (1 - g) * k,
                       blue: b + (1 - b) * k, alpha: a)
    }
}

@main
struct HopApp: App {
    @UIApplicationDelegateAdaptor(HopAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must register before the app finishes launching.
        BackgroundRefresh.register(model: AppModel.shared)
        // Locked from the first frame: the fleet must never flash before
        // the gate on a cold launch.
        BioLock.shared.armOnLaunch()
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
                    HopTips.configure()
                    await model.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    model.foreground = phase == .active
                    BioLock.shared.noteScene(phase)
                    // Ask for a background slot whenever we leave the
                    // foreground, so bells rung in a pocket still land.
                    if phase == .background { BackgroundRefresh.schedule() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var lock = BioLock.shared

    var body: some View {
        Group {
        if model.checkingAuth {
            VStack(spacing: 12) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.hopPurple)
                ProgressView()
            }
        } else if model.authenticated {
            if lock.locked {
                // REPLACED, not overlaid: an overlay's content still exists
                // in the hierarchy for accessibility tools to read.
                LockView()
            } else {
                SessionsView()
                    .overlay {
                        // The app-switcher snapshot: iOS captures it as the
                        // app leaves the foreground, and without this the
                        // "locked" fleet is readable in the carousel.
                        if lock.shielded { LockView(interactive: false) }
                    }
            }
        } else {
            LoginView()
        }
        }
        // On the Group, not the LockView: the view that unlocks is the view
        // that DISAPPEARS, and feedback attached to a disappearing view dies
        // with it. The same cue Apple Pay uses for a successful scan.
        .sensoryFeedback(.success, trigger: lock.locked) { old, new in
            old && !new
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var totp = ""
    @State private var busy = false
    @State private var remember = true
    @State private var passkeyShown = false
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

                // The way in you actually want: the passkey already enrolled
                // in hop web. Face ID instead of a password AND a 6-digit
                // code — the daemon's /api/passkeys/login issues the same
                // session cookie, so nothing downstream knows the difference.
                // Above the fields on purpose: the password path is the
                // fallback now, not the headline.
                Button {
                    passkeyShown = true
                } label: {
                    Label("Sign in with \(BioLock.biometryName)",
                          systemImage: "person.badge.key.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.hopPurple, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Sign in with a passkey")
                HStack(spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                    Text("or password").font(.caption2).foregroundStyle(.tertiary)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                }

                VStack(spacing: 12) {
                    TextField("server", text: $model.serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                    SecureField("password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .padding(12)
                        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
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
                        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
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
            .sheet(isPresented: $passkeyShown) {
                PasskeyLoginSheet(serverURL: model.normalizedServerURL) {
                    // The cookie is in shared storage; from here the app is in
                    // exactly the state a password login leaves it in.
                    model.authenticated = true
                    model.sessionExpired = false
                    Task { await model.refreshSessions(silent: true) }
                }
            }
        }
    }
}
