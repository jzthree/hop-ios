import SwiftUI

extension Color {
    static let hopPurple = Color(red: 0x7c / 255, green: 0x3a / 255, blue: 0xed / 255)
    static let hopGlow = Color(red: 0xa8 / 255, green: 0x55 / 255, blue: 0xf7 / 255)
}

@main
struct HopApp: App {
    @UIApplicationDelegateAdaptor(HopAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must register before the app finishes launching.
        BackgroundRefresh.register(model: AppModel.shared)
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

                if let err = model.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    busy = true
                    Task {
                        await model.login(password: password, totp: totp)
                        if model.authenticated {
                            // Only the password — never the TOTP secret, which
                            // would put both factors on one device.
                            if remember { Keychain.save(password, account: model.normalizedServerURL) }
                            else { Keychain.delete(account: model.normalizedServerURL) }
                        }
                        busy = false
                    }
                } label: {
                    if busy {
                        ProgressView().frame(maxWidth: .infinity).padding(6)
                    } else {
                        Text("Connect").font(.headline).frame(maxWidth: .infinity).padding(6)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || totp.isEmpty)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
            .onAppear {
                if password.isEmpty, let saved = Keychain.read(account: model.normalizedServerURL) {
                    password = saved
                    remember = true
                }
            }
        }
    }
}
