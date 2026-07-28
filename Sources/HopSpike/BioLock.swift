import LocalAuthentication
import SwiftUI

/// App-level biometric lock — the native answer to what hop's web client can
/// only do with a password prompt. The session is ALREADY authenticated; what
/// Face ID protects is the phone changing hands: launch or return from
/// background and the fleet is behind the OS's own gate.
///
/// Policy is .deviceOwnerAuthentication, biometrics WITH passcode fallback: a
/// failed scan on a moving train degrades to the passcode sheet, never to a
/// locked-out terminal fleet. And the lock screen keeps a sign-out escape
/// hatch, so even a wedged Secure Enclave can't hold the app hostage — the
/// password path is always behind it.
@MainActor
final class BioLock: ObservableObject {
    static let shared = BioLock()
    /// Content is replaced by the lock screen, not merely covered.
    @Published var locked = false
    /// Softer than locked: hides content from the app-switcher snapshot
    /// while inactive. iOS captures that image the moment the app leaves
    /// the foreground — without this, the "locked" fleet is readable in the
    /// switcher carousel.
    @Published var shielded = false
    private var evaluating = false

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "bioLock") }
        set { UserDefaults.standard.set(newValue, forKey: "bioLock") }
    }

    /// What the toggle and button should call the gate on THIS device.
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Pure and unit-tested: lock only when the feature is on and the app
    /// actually reached the BACKGROUND. Locking on .inactive would fire for
    /// the app-switcher flash, permission alerts and notification pulls —
    /// churn, not protection.
    nonisolated static func shouldLock(enabled: Bool, phase: ScenePhase) -> Bool {
        enabled && phase == .background
    }

    func noteScene(_ phase: ScenePhase) {
        shielded = enabled && phase != .active
        if Self.shouldLock(enabled: enabled, phase: phase) { locked = true }
        if phase == .active, locked { attempt() }
    }

    /// Cold launch: locked from the first frame, so the terminal never
    /// flashes before the gate.
    func armOnLaunch() {
        if enabled { locked = true }
    }

    func attempt() {
        guard !evaluating, locked else { return }
        // Under test the system prompt never rises: it's OS-owned UI that
        // XCUITest can't drive (the sim's passcode sheet has no Cancel), and
        // it covers the lock screen's own controls. Every caller funnels
        // through here — scene activation included — so this is the one gate.
        guard !ProcessInfo.processInfo.arguments.contains("-hop-ui-testing") else { return }
        let ctx = LAContext()
        // No gate available (simulator, fresh device, no passcode): don't
        // throw system UI that can cover the lock screen's own buttons —
        // stay locked and let sign-out be the way through.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return }
        evaluating = true
        Task {
            defer { evaluating = false }
            let ok = (try? await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your hop sessions")) ?? false
            if ok { locked = false }
            // Failure: stay locked. The lock screen's button retries.
        }
    }
}

/// What stands in for the fleet while locked (or while iOS is taking the
/// app-switcher snapshot). Deliberately shows NOTHING about the sessions.
struct LockView: View {
    @ObservedObject var lock = BioLock.shared
    @EnvironmentObject var model: AppModel
    /// Shield mode renders the brand only — no buttons — because it also
    /// appears for half a second around permission alerts.
    var interactive = true

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "hare.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.hopPurple)
            if interactive {
                Text("hop is locked")
                    .font(.headline)
                Button {
                    lock.attempt()
                } label: {
                    Label("Unlock with \(BioLock.biometryName)",
                          systemImage: "faceid")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.hopPurple)
                Button("Sign out") {
                    lock.locked = false
                    lock.enabled = false
                    model.signOut()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hopSurface)
        .task { if interactive { lock.attempt() } }
    }
}
