import CoreSpotlight
import SwiftUI
import UIKit

extension UIColor {
    /// A colour with two faces, resolved per trait collection. The whole
    /// "light UI to pair with the light terminal" feature is this one
    /// function applied to the palette: every surface below names its dark
    /// value and its light value, and UIKit/SwiftUI re-resolve on the flip.
    static func hop(dark: UInt32, light: UInt32,
                    darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(hex: light, alpha: lightAlpha)
                : UIColor(hex: dark, alpha: darkAlpha)
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// One surface palette instead of ad-hoc greys. The base is the
    /// terminal's own background (#0d1117 dark / #ffffff light — the two
    /// TerminalTheme papers), and the raised tones are the values that go
    /// with each, so chrome reads as the same material as the terminal
    /// rather than three unrelated tones sitting next to each other.
    static let hopSurface = hop(dark: 0x0d1117, light: 0xffffff)   // terminal, page
    static let hopRaised = hop(dark: 0x161b22, light: 0xf2f3f5)    // nav bar, key bar
    static let hopKey = hop(dark: 0x272e38, light: 0xe3e6eb)       // key caps
    static let hopKeyArmed = hop(dark: 0x9d7bf5, light: 0x7c3aed)  // armed modifier
    static let hopArmedInk = hop(dark: 0x000000, light: 0xffffff) // ink on it
    /// Card material: a slightly lifted top tone falling to the page's own
    /// tone under a hairline. Dark surfaces read as SHAPES only when lit
    /// from above; in the light a card is paper lifting off a grey page.
    static let hopCardTop = hop(dark: 0x1a212c, light: 0xffffff)
    static let hopCardBottom = hop(dark: 0x10151c, light: 0xf3f4f7)
    /// The chrome pill. Dark: the Dynamic Island's own black, so the pill
    /// reads as an extension of the bezel rather than another floating
    /// glass panel. Light: the island stays black hardware, and a black
    /// pill on white paper would be the heaviest thing on screen — the pill
    /// takes the raised tone instead and lets its hairline draw it.
    static let hopPill = hop(dark: 0x000000, light: 0xf2f3f5)
    /// A sunken input well (the reply composer).
    static let hopWell = hop(dark: 0x090b10, light: 0xeceef2)
    /// Tile ink — what colourless preview text renders as.
    static let hopInk = hop(dark: 0xe6edf3, light: 0x1f2328)
    /// Attention. Amber rather than red: red in a list of agent sessions
    /// reads as "something failed", and a session wanting you usually
    /// hasn't. Each state tone is a shade deeper on white, where the
    /// dark-tuned values wash out.
    static let hopAttention = hop(dark: 0xf0a53a, light: 0xd4841a)
    static let hopLive = hop(dark: 0x35d47a, light: 0x1f9e5b)
    static let hopDead = hop(dark: 0xd95a6b, light: 0xc9414f)
    /// An agent mid-turn. Blue: green is "finished, waiting for you" and
    /// amber is "asking you", so work-in-progress needs a hue of its own.
    static let hopWorking = hop(dark: 0x5aa7e0, light: 0x2b7bc4)
    /// One card shadow: heavy in the dark (lift is the only cue), a
    /// whisper in the light (paper barely floats).
    static let hopShadow = hop(dark: 0x000000, light: 0x000000,
                               darkAlpha: 0.5, lightAlpha: 0.12)

    /// The cap "lights" under the finger: a step toward the paper's
    /// opposite — toward white in the dark, toward black in the light.
    /// Physical keys brighten when pressed, and dimming reads as disabled.
    var hopPressed: UIColor {
        UIColor { trait in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            self.resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
            let k: CGFloat = 0.16
            let to: CGFloat = trait.userInterfaceStyle == .light ? 0 : 1
            return UIColor(red: r + (to - r) * k, green: g + (to - g) * k,
                           blue: b + (to - b) * k, alpha: a)
        }
    }
}

extension Color {
    static let hopPurple = Color(red: 0x7c / 255, green: 0x3a / 255, blue: 0xed / 255)
    static let hopGlow = Color(red: 0xa8 / 255, green: 0x55 / 255, blue: 0xf7 / 255)

    // The palette above, as SwiftUI colours. Same dynamic values — a view
    // built from these flips with the scheme, no per-view branching.
    static let hopSurface = Color(uiColor: .hopSurface)
    static let hopRaised = Color(uiColor: .hopRaised)
    static let hopKey = Color(uiColor: .hopKey)
    static let hopKeyArmed = Color(uiColor: .hopKeyArmed)
    static let hopAttention = Color(uiColor: .hopAttention)
    static let hopLive = Color(uiColor: .hopLive)
    static let hopDead = Color(uiColor: .hopDead)
    static let hopWorking = Color(uiColor: .hopWorking)
    static let hopCardTop = Color(uiColor: .hopCardTop)
    static let hopCardBottom = Color(uiColor: .hopCardBottom)
    static let hopPill = Color(uiColor: .hopPill)
    static let hopWell = Color(uiColor: .hopWell)
    static let hopInk = Color(uiColor: .hopInk)
    static let hopShadow = Color(uiColor: .hopShadow)

    /// Hairlines, seams and strokes: `primary` at a low alpha is a faint
    /// white on dark paper and a faint black on light paper. Every
    /// `Color.hopLine(x)` the chrome had became this — white on white
    /// is no line at all.
    static func hopLine(_ alpha: Double) -> Color { Color.primary.opacity(alpha) }

    static var hopCard: LinearGradient {
        LinearGradient(colors: [.hopCardTop, .hopCardBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The light-catching top edge on a card. A white sheen — invisible on
    /// white paper by design, where the card's hairline stroke and shadow
    /// carry the shape instead.
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

@main
struct HopApp: App {
    @UIApplicationDelegateAdaptor(HopAppDelegate.self) private var appDelegate
    @AppStorage("termLight") private var lightTheme = false
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
                // ONE switch: the terminal's light/dark IS the app's. The
                // palette is dual-faced, so this flips every surface at once.
                .preferredColorScheme(lightTheme ? .light : .dark)
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
    @StateObject private var passkey = PasskeyAuth()
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

                // The way in you actually want: the native passkey ceremony —
                // Face ID instead of a password AND a 6-digit code — against
                // the daemon's /api/passkeys/login, which issues the same
                // session cookie, so nothing downstream knows the difference.
                // Above the fields on purpose: the password path is the
                // fallback now, not the headline.
                Button {
                    Task {
                        if await passkey.signIn(server: model.normalizedServerURL) {
                            model.authenticated = true
                            model.sessionExpired = false
                            await model.refreshSessions(silent: true)
                        }
                    }
                } label: {
                    Label("Sign in with \(BioLock.biometryName)",
                          systemImage: "person.badge.key.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.hopPurple, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .opacity(passkey.busy ? 0.6 : 1)
                }
                .disabled(passkey.busy)
                .accessibilityLabel("Sign in with a passkey")
                if let pkErr = passkey.error {
                    Text(pkErr).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Rectangle().fill(Color.hopLine(0.12)).frame(height: 0.5)
                    Text("or password").font(.caption2).foregroundStyle(.tertiary)
                    Rectangle().fill(Color.hopLine(0.12)).frame(height: 0.5)
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
                            .strokeBorder(Color.hopLine(0.08), lineWidth: 0.5))
                    SecureField("password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .padding(12)
                        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.hopLine(0.08), lineWidth: 0.5))
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
                            .strokeBorder(Color.hopLine(0.08), lineWidth: 0.5))
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
