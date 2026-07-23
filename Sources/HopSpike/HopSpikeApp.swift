import SwiftUI

@main
struct HopSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
        }
    }
}

// Connection form: bridge URL + session name, persisted for quick relaunch.
struct ConnectView: View {
    @AppStorage("bridgeUrl") private var bridgeUrl = "ws://192.168.1.10:9877/ws"
    @AppStorage("room") private var room = "Solstice"
    @State private var connected = false

    var body: some View {
        NavigationStack {
            Form {
                Section("hop bridge (tools/lan-bridge.mjs on the Mac)") {
                    TextField("ws://mac-ip:9877/ws", text: $bridgeUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    TextField("session name", text: $room)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section {
                    Button("Attach") { connected = true }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
            }
            .navigationTitle("hop spike")
            .navigationDestination(isPresented: $connected) {
                TerminalScreen(url: bridgeUrl, room: room)
                    .navigationTitle(room)
                    .navigationBarTitleDisplayMode(.inline)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }
}
