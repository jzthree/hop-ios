import SwiftUI

extension Color {
    static let hopPurple = Color(red: 0x7c / 255, green: 0x3a / 255, blue: 0xed / 255)
    static let hopGlow = Color(red: 0xa8 / 255, green: 0x55 / 255, blue: 0xf7 / 255)
}

@main
struct HopApp: App {
    @StateObject private var model = AppModel()

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

                if let err = model.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    busy = true
                    Task {
                        await model.login(password: password, totp: totp)
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
        }
    }
}
