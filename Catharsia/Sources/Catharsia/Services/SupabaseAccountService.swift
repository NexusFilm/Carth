import AuthenticationServices
import CryptoKit
import Foundation
import Security
import Supabase
import UIKit

struct AccountIdentity: Equatable, Sendable {
    let id: String
    let email: String
    let name: String
    let emailVerified: Bool
}

enum AccountServiceError: LocalizedError {
    case notConfigured
    case emailConfirmationRequired
    case invalidAuthResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Account sign-in isn’t available in this build. Please try again later."
        case .emailConfirmationRequired:
            "Check your email to confirm your Catharsia account, then sign in."
        case .invalidAuthResponse:
            "Supabase returned an incomplete sign-in response. Please try again."
        }
    }
}

final class SupabaseAccountService: @unchecked Sendable {
    private let services: SupabaseServices

    init(services: SupabaseServices = .shared) {
        self.services = services
    }

    var isConfigured: Bool { services.configuration.isConfigured }

    func register(name: String, email: String, password: String) async throws -> Bool {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        guard let tenantID = services.configuration.tenantID else { throw AccountServiceError.notConfigured }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = try await services.client.auth.signUp(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            password: password,
            data: [
                "display_name": .string(normalizedName),
                "full_name": .string(normalizedName),
                "kathar_tenant_id": .string(tenantID.uuidString.lowercased())
            ]
        )
        return response.session != nil
    }

    func signIn(email: String, password: String) async throws {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        _ = try await services.client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            password: password
        )
    }

    @MainActor
    func signInWithGoogle() async throws {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        guard let redirectURL = services.configuration.authRedirectURL else {
            throw AccountServiceError.notConfigured
        }
        let provider = WebAuthContextProvider.shared
        try await services.client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: redirectURL,
            configure: { session in
                session.presentationContextProvider = provider
                session.prefersEphemeralWebBrowserSession = false
            }
        )
    }

    func signInWithApple(idToken: String, nonce: String, name: String?) async throws {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        _ = try await services.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        if let name, !name.isEmpty {
            _ = try? await services.client.auth.update(user: .init(data: ["display_name": .string(name)]))
        }
    }

    func handleOpenURL(_ url: URL) async throws {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        guard let redirectURL = services.configuration.authRedirectURL,
              url.scheme == redirectURL.scheme,
              url.host == redirectURL.host else { return }
        _ = try await services.client.auth.session(from: url)
    }

    func signOut() async throws {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        try await services.client.auth.signOut()
    }

    func currentIdentity() async throws -> AccountIdentity {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        let user = try await services.client.auth.session.user
        let metadataName = user.userMetadata["display_name"]?.stringValue
            ?? user.userMetadata["full_name"]?.stringValue
            ?? user.userMetadata["name"]?.stringValue
        let email = user.email ?? ""
        let fallbackName = email.components(separatedBy: "@").first?
            .replacingOccurrences(of: ".", with: " ").capitalized ?? "Member"
        return AccountIdentity(
            id: user.id.uuidString.lowercased(),
            email: email,
            name: metadataName ?? fallbackName,
            emailVerified: user.emailConfirmedAt != nil
        )
    }

    func deleteAccountAndData() async throws {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        struct DeleteRequest: Encodable, Sendable { let confirmation = "DELETE" }
        struct DeleteResponse: Decodable, Sendable {
            let success: Bool
            let sharedIdentityRetained: Bool
            enum CodingKeys: String, CodingKey {
                case success
                case sharedIdentityRetained = "sharedIdentityRetained"
            }
        }

        let response: DeleteResponse = try await services.client.functions.invoke(
            "kathar-delete-account",
            options: FunctionInvokeOptions(method: .post, body: DeleteRequest())
        )
        guard response.success, response.sharedIdentityRetained else { throw AccountServiceError.invalidAuthResponse }
        try await services.client.auth.signOut()
    }
}

@MainActor
final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = WebAuthContextProvider()

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                return UIWindow()
            }
            return scene.windows.first(where: \.isKeyWindow) ?? UIWindow(windowScene: scene)
        }
    }
}

enum AppleNonce {
    static func generate(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
