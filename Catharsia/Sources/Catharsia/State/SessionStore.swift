import AuthenticationServices
import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class SessionStore {
    private let accountService = SupabaseAccountService()
    private let interactionService = SupabaseInteractionService()
    private var authListener: Task<Void, Never>?
    private var appleNonce: String?

    private(set) var isSignedIn = false
    private(set) var userID = ""
    private(set) var userEmail = ""
    private(set) var displayName = ""
    private(set) var username = ""
    private(set) var profilePhotoURL: String?
    private(set) var emailIsVerified = false
    var accountMessage: String?
    private(set) var isWorking = false
    private(set) var isCheckingSession = false
    private(set) var canPublish = false
    private(set) var isAdmin = false
    private(set) var isTherapist = false
    private(set) var isBetaPublisher = false
    private(set) var needsAdminVerification = false
    private(set) var blockedUsers: [BlockedUser] = []

    var blockedUserIDs: Set<String> { Set(blockedUsers.map(\.userID)) }
    var isBackendConfigured: Bool { accountService.isConfigured }

    func signIn(email: String, password: String) async {
        await performAccountAction { try await accountService.signIn(email: email, password: password) }
    }

    func register(name: String, email: String, password: String) async {
        guard isBackendConfigured else {
            accountMessage = AccountServiceError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        accountMessage = nil
        defer { isWorking = false }
        do {
            let hasSession = try await accountService.register(name: name, email: email, password: password)
            if hasSession {
                try await refreshIdentity()
            } else {
                accountMessage = AccountServiceError.emailConfirmationRequired.localizedDescription
            }
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        await performAccountAction { try await accountService.signInWithGoogle() }
    }

    func prepareAppleSignIn() -> String {
        let nonce = AppleNonce.generate()
        appleNonce = nonce
        return AppleNonce.hash(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        accountMessage = nil
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                appleNonce = nil
                accountMessage = "Apple Sign-In returned an incomplete response. Please try again."
                return
            }
            let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            isWorking = true
            defer { isWorking = false; appleNonce = nil }
            do {
                try await accountService.signInWithApple(idToken: idToken, nonce: nonce, name: displayName.isEmpty ? nil : displayName)
                try await refreshIdentity()
            } catch {
                accountMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                accountMessage = error.localizedDescription
            }
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard isBackendConfigured else { return }
        do {
            try await accountService.handleOpenURL(url)
            try await refreshIdentity()
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard isBackendConfigured else {
            accountMessage = AccountServiceError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        accountMessage = nil
        defer { isWorking = false }
        do {
            await PushNotificationService.shared.unregisterCurrentDevice()
            try await accountService.signOut()
            clearIdentity()
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    func deleteAccount() async {
        guard isSignedIn else {
            accountMessage = "Sign in before deleting your account."
            return
        }
        isWorking = true
        accountMessage = nil
        defer { isWorking = false }
        do {
            await PushNotificationService.shared.unregisterCurrentDevice()
            try await accountService.deleteAccountAndData()
            clearIdentity()
            accountMessage = "Your Catharsia profile and data were deleted. Your shared Nexus sign-in remains available to other apps."
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    func refreshBlockedUsers() async {
        guard isSignedIn else { blockedUsers = []; return }
        blockedUsers = (try? await interactionService.blockedUsers()) ?? []
    }

    func setBlockedUser(_ user: BlockedUser, blocked: Bool) async throws {
        try await interactionService.setBlockedUser(user, blocked: blocked)
        if blocked {
            blockedUsers.removeAll { $0.userID == user.userID }
            blockedUsers.append(user)
        } else {
            blockedUsers.removeAll { $0.userID == user.userID }
        }
    }

    func restoreSession() async {
        guard isBackendConfigured else { return }
        isCheckingSession = true
        defer { isCheckingSession = false }
        observeAuthChangesIfNeeded()
        do {
            try await refreshIdentity()
        } catch {
            clearIdentity()
        }
    }

    func refreshIdentity() async throws {
        let identity = try await accountService.currentIdentity()
        userID = identity.id
        userEmail = identity.email
        displayName = identity.name
        emailIsVerified = identity.emailVerified
        do {
            let capabilities = try await interactionService.publisherCapabilities()
            canPublish = capabilities.canPublish
            isAdmin = capabilities.isAdmin
            isTherapist = capabilities.isTherapist
            isBetaPublisher = capabilities.isBetaPublisher
            needsAdminVerification = capabilities.needsAdminVerification
        } catch {
            canPublish = false
            isAdmin = false
            isTherapist = false
            isBetaPublisher = false
            needsAdminVerification = false
        }
        if let profile = try? await interactionService.fetchMyMemberProfile() {
            displayName = profile.displayName ?? profile.fullName ?? identity.name
            username = profile.username ?? ""
            profilePhotoURL = profile.photoURL
        } else {
            username = ""
            profilePhotoURL = nil
        }
        blockedUsers = (try? await interactionService.blockedUsers()) ?? []
        isSignedIn = true
        PushNotificationService.shared.setSignedInUser(identity.id)
    }

    private func performAccountAction(_ action: () async throws -> Void) async {
        guard isBackendConfigured else {
            accountMessage = AccountServiceError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        accountMessage = nil
        defer { isWorking = false }
        do {
            try await action()
            try await refreshIdentity()
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    private func observeAuthChangesIfNeeded() {
        guard authListener == nil else { return }
        authListener = Task {
            for await (event, session) in SupabaseServices.shared.client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                switch event {
                case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
                    if session != nil { try? await refreshIdentity() }
                    else if event == .initialSession { clearIdentity() }
                case .signedOut, .userDeleted:
                    clearIdentity()
                default:
                    break
                }
            }
        }
    }

    private func clearIdentity() {
        isSignedIn = false
        userID = ""
        userEmail = ""
        displayName = ""
        username = ""
        profilePhotoURL = nil
        emailIsVerified = false
        canPublish = false
        isAdmin = false
        isTherapist = false
        isBetaPublisher = false
        needsAdminVerification = false
        blockedUsers = []
        PushNotificationService.shared.setSignedInUser(nil)
    }
}
