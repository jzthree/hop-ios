import Foundation

// Answering an agent from the lock screen, without opening the app.
//
// This is the most phone-shaped thing hop can do: an agent asks "proceed?",
// the notification carries the question (see HopNotifier), and you answer it
// where you're standing. A browser tab cannot do this at all.
//
// hop takes input only over the WebSocket — there is no HTTP input endpoint —
// so this opens a throwaway connection, sends, and closes. It asks for
// `replay=1` because a fire-and-forget send has no use for the 334 KB join
// snapshot it would otherwise be handed.
@MainActor
enum QuickReply {
    /// Sends `text` to `room` as a line of input. Returns false if the socket
    /// never opened or the send failed, so the caller can say so rather than
    /// leaving the user believing an answer was delivered.
    static func send(_ text: String, to room: String, model: AppModel) async -> Bool {
        guard !text.isEmpty else { return false }
        let client = HayClient()
        client.replayOverride = 1

        return await withCheckedContinuation { continuation in
            var settled = false
            func finish(_ ok: Bool) {
                guard !settled else { return }
                settled = true
                client.close()
                continuation.resume(returning: ok)
            }

            client.onEvent = { event in
                switch event {
                case .connected:
                    // A newline is the point: the agent is waiting on a line,
                    // not on keystrokes.
                    client.sendInput(text + "\r")
                    // Give the frame a moment to leave before closing; closing
                    // instantly can drop it.
                    // Wait past the point where a rejection would arrive
                    // before calling it sent — the server answers immediately,
                    // so 600ms is generous.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        finish(true)
                    }
                case .rejected(let reason):
                    // Another client holds control, so the session never saw
                    // it. Reporting success here would be the worst outcome:
                    // the user walks away believing they answered.
                    Logger.quickReply.error("reply rejected: \(reason, privacy: .public)")
                    finish(false)
                case .failed(let reason, _):
                    Logger.quickReply.error("reply failed: \(reason, privacy: .public)")
                    finish(false)
                case .ended, .closed:
                    finish(false)
                default:
                    break
                }
            }
            client.connect(base: model.wsBase, httpBase: model.normalizedServerURL,
                           room: room, cols: 80, rows: 24,
                           token: model.accessToken, using: model.urlSession)
            // Don't hang a background launch forever if the tunnel is asleep.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                finish(false)
            }
        }
    }
}

import os
extension Logger {
    static let quickReply = Logger(subsystem: "io.zhoulab.hop.spike", category: "quickreply")
}
