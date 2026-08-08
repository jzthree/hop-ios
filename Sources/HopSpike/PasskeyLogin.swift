import AuthenticationServices
import SwiftUI
import UIKit

// Native passkey sign-in and enrollment — the real Face ID sheet, not a web
// page. This file used to wrap the hop web login in a WKWebView on the theory
// that passkeys work there; they do not, and never can: Apple restricts
// WebAuthn to Safari-class surfaces (Safari, SFSafariViewController,
// ASWebAuthenticationSession) and to browsers holding a restricted
// entitlement. A WKWebView's passkey button is a silent no-op.
//
// The native path's two former blockers are gone: the developer account is
// live (team 5AD7QB9795 signs TestFlight builds), and the daemon serves
// /.well-known/apple-app-site-association naming this app. The entitlement
// (project.yml: webcredentials:hop.zhoulab.io) closes the triangle. Both
// ceremonies speak to the daemon's existing @simplewebauthn endpoints with
// exactly the JSON the web login page sends, so a passkey enrolled in hop web
// and one enrolled here are indistinguishable to the server.
//
// Enrollment exists because sign-in alone only helps if the laptop's passkey
// happened to sync through iCloud Keychain. "Add Face ID sign-in" in Account
// gives this phone its own credential, so the feature owes nothing to sync.
@MainActor
final class PasskeyAuth: NSObject, ObservableObject {
    @Published var busy = false
    @Published var error: String?

    private var serverURL = ""
    private var continuation: CheckedContinuation<ASAuthorization?, Never>?
    private var controller: ASAuthorizationController?   // retained through the ceremony
    private var ceremonyError: String?

    /// Assert an existing passkey and trade it for the session cookie.
    /// Returns true once `tunnel_session` is in shared cookie storage —
    /// the exact state a password login leaves behind. False means the user
    /// cancelled or `error` says why.
    func signIn(server: String) async -> Bool {
        await run(server: server) {
            let opt = try await self.post("/api/passkeys/login-options")
            guard opt["ok"] as? Bool == true,
                  let token = opt["token"] as? String,
                  let options = opt["options"] as? [String: Any],
                  let challenge = Self.b64uDecode(options["challenge"] as? String ?? "")
            else { throw Failure(opt["error"] as? String ?? "No passkey challenge from server") }

            let rpID = options["rpId"] as? String ?? URL(string: server)?.host ?? ""
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
            let request = provider.createCredentialAssertionRequest(challenge: challenge)
            request.userVerificationPreference = .preferred
            request.allowedCredentials = Self.descriptors(options["allowCredentials"])

            guard let assertion = await self.perform(request)?.credential
                as? ASAuthorizationPlatformPublicKeyCredentialAssertion
            else { throw Failure(self.ceremonyError) }

            var inner: [String: Any] = [
                "clientDataJSON": Self.b64u(assertion.rawClientDataJSON),
                "authenticatorData": Self.b64u(assertion.rawAuthenticatorData),
                "signature": Self.b64u(assertion.signature),
            ]
            if let uid = assertion.userID, !uid.isEmpty { inner["userHandle"] = Self.b64u(uid) }
            let verdict = try await self.post("/api/passkeys/login", body: [
                "token": token,
                "response": Self.credentialJSON(id: assertion.credentialID, response: inner),
            ])
            guard verdict["ok"] as? Bool == true
            else { throw Failure(verdict["error"] as? String ?? "Passkey verification failed") }
        }
    }

    /// Create a passkey for this phone against the signed-in server. Requires
    /// an authenticated session — the register endpoints sit behind the same
    /// cookie every other API call rides on.
    func enroll(server: String) async -> Bool {
        await run(server: server) {
            let opt = try await self.post("/api/passkeys/register-options")
            guard opt["ok"] as? Bool == true,
                  let token = opt["token"] as? String,
                  let options = opt["options"] as? [String: Any],
                  let challenge = Self.b64uDecode(options["challenge"] as? String ?? ""),
                  let rp = options["rp"] as? [String: Any],
                  let rpID = rp["id"] as? String,
                  let user = options["user"] as? [String: Any],
                  let userID = Self.b64uDecode(user["id"] as? String ?? "")
            else { throw Failure(opt["error"] as? String ?? "No enrollment challenge from server") }

            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
            let request = provider.createCredentialRegistrationRequest(
                challenge: challenge,
                name: user["name"] as? String ?? "hop",
                userID: userID)
            request.userVerificationPreference = .preferred
            if #available(iOS 17.4, *) {
                request.excludedCredentials = Self.descriptors(options["excludeCredentials"])
            }

            guard let reg = await self.perform(request)?.credential
                as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
                let attestation = reg.rawAttestationObject
            else { throw Failure(self.ceremonyError) }

            let verdict = try await self.post("/api/passkeys/register", body: [
                "token": token,
                "label": "iPhone · \(UIDevice.current.name)",
                "response": Self.credentialJSON(id: reg.credentialID, response: [
                    "clientDataJSON": Self.b64u(reg.rawClientDataJSON),
                    "attestationObject": Self.b64u(attestation),
                    "transports": ["internal"],
                ]),
            ])
            guard verdict["ok"] as? Bool == true
            else { throw Failure(verdict["error"] as? String ?? "Enrollment was rejected") }
        }
    }

    // MARK: - ceremony plumbing

    /// nil message == the user dismissed the sheet; stay silent about it.
    private struct Failure: Error { let message: String?
        init(_ m: String?) { message = m } }

    private func run(server: String, _ flow: @escaping () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        serverURL = server
        busy = true
        error = nil
        ceremonyError = nil
        defer { busy = false; controller = nil }
        do {
            try await flow()
            return true
        } catch let f as Failure {
            error = f.message
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func perform(_ request: ASAuthorizationRequest) async -> ASAuthorization? {
        await withCheckedContinuation { cont in
            continuation = cont
            let c = ASAuthorizationController(authorizationRequests: [request])
            c.delegate = self
            c.presentationContextProvider = self
            controller = c
            c.performRequests()
        }
    }

    private func post(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: serverURL + path) else { throw Failure("Bad server address") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func credentialJSON(id: Data, response: [String: Any]) -> [String: Any] {
        [
            "id": b64u(id),
            "rawId": b64u(id),
            "type": "public-key",
            "authenticatorAttachment": "platform",
            "clientExtensionResults": [:] as [String: Any],
            "response": response,
        ]
    }

    private static func descriptors(_ raw: Any?) -> [ASAuthorizationPlatformPublicKeyCredentialDescriptor] {
        ((raw as? [[String: Any]]) ?? []).compactMap { c in
            b64uDecode(c["id"] as? String ?? "").map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
    }

    private static func b64u(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func b64uDecode(_ s: String) -> Data? {
        guard !s.isEmpty else { return nil }
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}

extension PasskeyAuth: ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            self.continuation?.resume(returning: authorization)
            self.continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            // Cancellation is a decision, not a failure — no message for it.
            if (error as? ASAuthorizationError)?.code != .canceled {
                var msg = error.localizedDescription
                if msg.contains("not associated with domain") {
                    // The one failure with a fix the person can apply: Apple's
                    // CDN hasn't re-fetched the server's association yet.
                    msg += " — the server's Apple association may still be propagating; try again in a few minutes."
                }
                self.ceremonyError = msg
            }
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // AuthenticationServices calls this on the main thread.
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
