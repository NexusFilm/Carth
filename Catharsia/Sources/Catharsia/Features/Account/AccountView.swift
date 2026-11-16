import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var profile: BentoProfessionalRecord?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showBentoEditor = false
    @State private var showPublicProfile = false
    @State private var feed = ExploreFeedStore()
    @State private var reloadID = UUID()

    private let service = SupabaseInteractionService()

    private var canEdit: Bool { session.isAdmin || session.isTherapist }

    var body: some View {
        NavigationStack {
            Group {
                if canEdit, !isLoading, let profile {
                    TherapistBentoPageView(
                        professionalID: profile.id,
                        fallbackName: profile.fullName,
                        fallbackCredentials: profile.credentials,
                        feed: feed,
                        isEmbedded: true
                    )
                    .id(reloadID)
                    .environment(session)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            header

                            if isLoading {
                                ProgressView().tint(CatharsiaStyle.violet)
                                    .frame(maxWidth: .infinity).padding(.vertical, 54)
                            } else if let profile {
                                profileContent(profile)
                            } else {
                                ContentCard {
                                    Label(session.isSignedIn ? "Your profile is ready" : "Welcome to Catharsia", systemImage: "person.crop.circle")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(CatharsiaStyle.ink)
                                    Text(session.isSignedIn
                                         ? "Your account settings and preferences are here."
                                         : "Explore freely. Sign in only when you want to save, like, or comment.")
                                        .font(.subheadline)
                                        .foregroundStyle(CatharsiaStyle.muted)
                                        .padding(.top, 4)
                                    if !session.isSignedIn {
                                        Button("Sign in or create account") { showSettings = true }
                                            .font(.subheadline.weight(.bold))
                                            .padding(.top, 8)
                                    }
                                }
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(CatharsiaStyle.coral)
                            }
                        }
                        .padding(18)
                        .padding(.bottom, 28)
                    }
                    .background(CatharsiaStyle.canvas.ignoresSafeArea())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if canEdit {
                        Button { showBentoEditor = true } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit public profile")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                AccountSettingsView()
                    .environment(session)
            }
            .sheet(isPresented: $showBentoEditor, onDismiss: { reloadID = UUID() }) {
                BentoPageEditorView()
                    .environment(session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPublicProfile) {
                if let profile {
                    TherapistBentoPageView(
                        professionalID: profile.id,
                        fallbackName: profile.fullName,
                        fallbackCredentials: profile.credentials,
                        feed: feed
                    )
                    .environment(session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .task(id: "\(session.isSignedIn)-\(reloadID.uuidString)") { await loadProfile() }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrainMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("CATHARSIA")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(CatharsiaStyle.aqua)
                Text(profile?.isOfficialProfile == true ? "OFFICIAL PROFILE" : "YOUR SPACE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(CatharsiaStyle.muted)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func profileContent(_ profile: BentoProfessionalRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .bottomLeading) {
                if let imageURL = SupabaseServices.shared.publicMediaURL(for: profile.photoURL) {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { profileCoverFallback }
                    }
                } else {
                    profileCoverFallback
                }
                LinearGradient(colors: [.clear, CatharsiaStyle.ink.opacity(0.4)], startPoint: .center, endPoint: .bottom)
                Label(profile.isOfficialProfile ? "Official profile" : "Verified therapist", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.black.opacity(0.2), in: Capsule())
                    .padding(14)
            }
            .frame(height: 248)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(profile.fullName)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .foregroundStyle(CatharsiaStyle.ink)
                    if profile.isOfficialProfile {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(CatharsiaStyle.aqua)
                    }
                }
                if !profile.isOfficialProfile {
                    Text(profile.credentials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.violet)
                }
            }

            Button { showPublicProfile = true } label: {
                Label("View public posts and profile", systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(CatharsiaStyle.panel, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("See published posts and the public Bento profile.")

            if let bio = profile.description {
                Text(bio)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(CatharsiaStyle.ink.opacity(0.88))
            }

            if let values = profile.coreValues?.trimmingCharacters(in: .whitespacesAndNewlines), !values.isEmpty {
                ContentCard {
                    Eyebrow(text: "What we stand for")
                    Text(values)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(CatharsiaStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                }
            }

            if !profile.publicLinks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Helpful resources")
                    ForEach(profile.publicLinks) { link in
                        if let url = link.destinationURL {
                            Link(destination: url) {
                                HStack(spacing: 12) {
                                    Image(systemName: link.kind.symbol)
                                        .foregroundStyle(CatharsiaStyle.violet)
                                        .frame(width: 40, height: 40)
                                        .background(CatharsiaStyle.violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(link.title).font(.subheadline.weight(.semibold)).foregroundStyle(CatharsiaStyle.ink)
                                        if let detail = link.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                                            Text(detail).font(.caption).foregroundStyle(CatharsiaStyle.muted).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(CatharsiaStyle.muted)
                                }
                                .padding(12)
                                .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var profileCoverFallback: some View {
        ZStack {
            CatharsiaStyle.atmosphere
            Circle().fill(CatharsiaStyle.violet.opacity(0.09)).frame(width: 190, height: 190)
            BrainMark(size: 100)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 248)
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if session.isAdmin || session.isTherapist {
                profile = try await service.fetchMyBentoProfile()
            } else {
                profile = try await service.fetchOfficialBentoProfile()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AccountSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var showAccess = false
    @State private var showSafety = false
    @State private var showPrivacy = false
    @State private var showModeration = false
    @State private var showTherapistAccess = false
    @State private var showTherapistReview = false
    @State private var showBetaPublisherCode = false
    @State private var showAnnouncementCenter = false
    @State private var showNotificationSettings = false
    @State private var showBentoEditor = false
    @State private var showMemberProfileEditor = false
    @State private var confirmAccountDeletion = false
    @State private var accountDeletionComplete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileHeader

                    if session.isAdmin || session.isTherapist {
                        settingsSection(title: session.isAdmin ? "Public profile" : "Your profile") {
                            settingsRow(
                                title: session.isAdmin ? "Edit Catharsia profile" : "Edit your profile",
                                subtitle: session.isAdmin ? "Change the name people see on posts" : "Add appointments and helpful links",
                                symbol: "person.crop.rectangle",
                                tint: CatharsiaStyle.violet,
                                showsChevron: true
                            ) { showBentoEditor = true }
                        }
                    }

                    if needsAdminVerification {
                        verificationCard
                    }

                    if session.isSignedIn {
                        settingsSection(title: "Personal profile") {
                            settingsRow(
                                title: "Edit personal profile",
                                subtitle: "Name, username, and photo",
                                symbol: "person.crop.circle",
                                tint: CatharsiaStyle.violet,
                                showsChevron: true
                            ) { showMemberProfileEditor = true }
                        }

                        settingsSection(title: "Notifications") {
                            settingsRow(
                                title: "Push alerts",
                                subtitle: "Choose what reaches your phone",
                                symbol: "bell.badge",
                                tint: CatharsiaStyle.violet,
                                showsChevron: true
                            ) { showNotificationSettings = true }
                        }

                        if !session.canPublish && !session.isAdmin {
                            settingsSection(title: "Professional access") {
                                settingsRow(
                                    title: "Request therapist access",
                                    subtitle: "Share your credentials for review",
                                    symbol: "checkmark.seal",
                                    showsChevron: true
                                ) { showTherapistAccess = true }
                            }
                        }

                        if session.isAdmin {
                            adminToolsSection
                        }

                        if !session.blockedUsers.isEmpty {
                            settingsSection(title: "Blocked accounts") {
                                VStack(spacing: 0) {
                                    ForEach(session.blockedUsers) { user in
                                        HStack {
                                            Text(user.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(CatharsiaStyle.ink)
                                            Spacer()
                                            Button("Unblock") {
                                                Task { await unblock(user) }
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            .frame(minHeight: 44)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }

                        helpAndPrivacySection

                        settingsSection(title: "Account") {
                            VStack(spacing: 0) {
                                settingsRow(
                                    title: "Sign out",
                                    symbol: "rectangle.portrait.and.arrow.right",
                                    showsChevron: false
                                ) { Task { await session.signOut() } }
                                settingsDivider
                                settingsRow(
                                    title: "Delete account and data",
                                    symbol: "trash",
                                    tint: CatharsiaStyle.coral,
                                    isDestructive: true,
                                    showsChevron: false
                                ) { confirmAccountDeletion = true }
                                .disabled(session.isWorking)
                            }
                        }
                    } else {
                        ContentCard {
                            Text("Make this space yours")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(CatharsiaStyle.ink)
                            Text("Read Explore freely. Sign in only to like, comment, or save posts.")
                                .font(.subheadline)
                                .foregroundStyle(CatharsiaStyle.muted)
                                .padding(.top, 5)
                            Button { showAccess = true } label: {
                                Text("Sign in or create account")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(CatharsiaStyle.canvas)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 13)
                        }

                        helpAndPrivacySection
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .sheet(isPresented: $showAccess) { AccountAccessView().environment(session) }
            .sheet(isPresented: $showBentoEditor) {
                BentoPageEditorView()
                    .environment(session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: $showSafety) { SafetySupportView() }
            .navigationDestination(isPresented: $showPrivacy) { PrivacyPolicyView() }
            .navigationDestination(isPresented: $showModeration) { ModerationQueueView() }
            .navigationDestination(isPresented: $showTherapistAccess) { TherapistAccessView().environment(session) }
            .navigationDestination(isPresented: $showTherapistReview) { TherapistReviewView().environment(session) }
            .navigationDestination(isPresented: $showBetaPublisherCode) { BetaPublisherCodeSettingsView().environment(session) }
            .navigationDestination(isPresented: $showAnnouncementCenter) { AdminAnnouncementView().environment(session) }
            .navigationDestination(isPresented: $showNotificationSettings) { NotificationSettingsView().environment(session) }
            .navigationDestination(isPresented: $showMemberProfileEditor) {
                MemberProfileEditorView().environment(session)
            }
            .task(id: session.isSignedIn) {
                await session.refreshBlockedUsers()
            }
            .confirmationDialog("Delete your Catharsia account?", isPresented: $confirmAccountDeletion, titleVisibility: .visible) {
                Button("Delete account and data", role: .destructive) {
                    Task {
                        await session.deleteAccount()
                        accountDeletionComplete = !session.isSignedIn
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your Catharsia profile, therapist access requests and license details, saved posts, likes, comments, reports, and posts and media you published. Your shared Nexus sign-in stays available to other apps.")
            }
            .alert("Account deleted", isPresented: $accountDeletionComplete) {
                Button("Done", role: .cancel) {}
            } message: {
                Text(session.accountMessage ?? "Your account and associated Catharsia data were deleted.")
            }
        }
        .preferredColorScheme(.light)
    }

    private var helpAndPrivacySection: some View {
        settingsSection(title: "Help & privacy") {
            VStack(spacing: 0) {
                settingsRow(
                    title: "Support and safety",
                    subtitle: "Find help when you need it",
                    symbol: "heart.text.square.fill",
                    tint: CatharsiaStyle.aqua,
                    showsChevron: true
                ) { showSafety = true }
                settingsDivider
                settingsRow(
                    title: "Privacy and account data",
                    subtitle: "Privacy policy and your information",
                    symbol: "lock.shield.fill",
                    showsChevron: true
                ) { showPrivacy = true }
            }
        }
    }

    private var adminToolsSection: some View {
        settingsSection(title: "Admin tools") {
            VStack(spacing: 0) {
                settingsRow(
                    title: "Therapist access requests",
                    symbol: "person.text.rectangle",
                    showsChevron: true
                ) { showTherapistReview = true }
                settingsDivider
                settingsRow(
                    title: "Beta publisher code",
                    subtitle: "Share one code to unlock contributor posting",
                    symbol: "person.2.badge.key",
                    tint: CatharsiaStyle.violet,
                    showsChevron: true
                ) { showBetaPublisherCode = true }
                settingsDivider
                settingsRow(
                    title: "Official announcements",
                    subtitle: "Send an official update to the community",
                    symbol: "megaphone",
                    showsChevron: true
                ) { showAnnouncementCenter = true }
                settingsDivider
                settingsRow(
                    title: "Safety review",
                    symbol: "checkmark.shield",
                    showsChevron: true
                ) { showModeration = true }
            }
        }
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(CatharsiaStyle.ink.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 38)
            .accessibilityHidden(true)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(CatharsiaStyle.muted)
                .padding(.leading, 4)
                .accessibilityLabel(title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func settingsRow(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color = CatharsiaStyle.ink,
        isDestructive: Bool = false,
        showsChevron: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            settingsRowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint, showsChevron: showsChevron)
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLabel(title: String, subtitle: String?, symbol: String, tint: Color, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.muted.opacity(0.75))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, subtitle == nil ? 12 : 10)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BrainMark(size: 31)
                Text("CATHARSIA")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(CatharsiaStyle.aqua)
                Spacer()
            }

            if session.isSignedIn {
                HStack(spacing: 15) {
                    Group {
                        if session.isAdmin {
                            ZStack {
                                CatharsiaStyle.panelRaised
                                BrainMark(size: 40)
                            }
                        } else {
                            Text(initials)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(CatharsiaStyle.canvas)
                                .background(LinearGradient(colors: [CatharsiaStyle.aqua, CatharsiaStyle.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.isAdmin ? "Catharsia" : (session.displayName.isEmpty ? "Your account" : session.displayName))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Text(session.userEmail)
                            .font(.caption)
                            .foregroundStyle(CatharsiaStyle.muted)
                        if session.isAdmin || session.isTherapist || session.isBetaPublisher {
                            Text(session.isAdmin ? "OFFICIAL PROFILE" : (session.isTherapist ? "VERIFIED THERAPIST" : "BETA PUBLISHER"))
                                .font(.caption2.weight(.bold))
                                .tracking(1)
                                .foregroundStyle(CatharsiaStyle.canvas)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(session.isBetaPublisher && !session.isTherapist && !session.isAdmin ? CatharsiaStyle.violet : CatharsiaStyle.aqua, in: Capsule())
                        }
                    }
                }
            } else {
                Text("Your space")
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("Save what helps. Keep the conversation kind.")
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
            }
        }
        .padding(.vertical, 7)
    }

    private var initials: String {
        if session.isAdmin { return "C" }
        return session.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var needsAdminVerification: Bool {
        session.needsAdminVerification
    }

    private func unblock(_ user: BlockedUser) async {
        do {
            try await session.setBlockedUser(user, blocked: false)
        } catch {
            session.accountMessage = error.localizedDescription
        }
    }

    private var verificationCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Verify your email", systemImage: "envelope.badge.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("Confirm your account email to publish as the Catharsia administrator. Use the confirmation link sent by Supabase, then refresh your account here.")
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)

                Button {
                    Task { try? await session.refreshIdentity() }
                } label: {
                    Text("Refresh account access")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.canvas)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                if let message = session.accountMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
            }
        }
    }
}
