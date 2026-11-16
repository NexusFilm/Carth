import PhotosUI
import SwiftUI
import UIKit

struct TherapistBentoPageView: View {
    let professionalID: String
    let fallbackName: String
    let fallbackCredentials: String
    let feed: ExploreFeedStore
    var isEmbedded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var profile: BentoProfessionalRecord?
    @State private var profilePosts: [PublishedPost] = []
    @State private var selectedSection: TherapistProfileSection = .posts
    @State private var isLoadingPosts = false
    @State private var errorMessage: String?

    private let service = SupabaseInteractionService()

    init(
        professionalID: String,
        fallbackName: String,
        fallbackCredentials: String,
        feed: ExploreFeedStore,
        isEmbedded: Bool = false
    ) {
        self.professionalID = professionalID
        self.fallbackName = fallbackName
        self.fallbackCredentials = fallbackCredentials
        self.feed = feed
        self.isEmbedded = isEmbedded
    }

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(profilePosts.count.formatted())
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.muted)
                Text(profilePosts.count == 1 ? "post" : "posts")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CatharsiaStyle.muted)
                Spacer()
            }

            if isLoadingPosts && profilePosts.isEmpty {
                ProgressView().tint(CatharsiaStyle.violet)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if profilePosts.isEmpty {
                BrainGlowMark(size: 68)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(profilePosts) { post in
                        NavigationLink {
                            PostDetailView(post: post, feed: feed) {
                                selectedSection = .bento
                            }
                        } label: {
                            TherapistPostTile(post: feed.post(withID: post.id) ?? post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var bentoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let bio = profile?.description {
                BentoSurfaceCard(surface: .lilac) {
                    Eyebrow(text: "About")
                    Text(bio)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(CatharsiaStyle.ink.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                }
            }

            if let values = profile?.coreValues?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                BentoSurfaceCard(surface: .aqua) {
                    Eyebrow(text: "What we stand for")
                    Text(values)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(CatharsiaStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                }
            }

            profileDetails
            primaryAction
            linkSection
        }
    }

    var body: some View {
        Group {
            if isEmbedded {
                profilePage
            } else {
                NavigationStack {
                    profilePage
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var profilePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileImage
                identity
                Picker("Profile section", selection: $selectedSection) {
                    ForEach(TherapistProfileSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .tint(CatharsiaStyle.violet)

                if selectedSection == .posts {
                    postsSection
                } else {
                    bentoSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle(isEmbedded ? "Profile" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                            .frame(width: 40, height: 40)
                            .background(CatharsiaStyle.panel, in: Circle())
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .task {
            await loadProfile()
            await loadPosts()
        }
        .alert("Couldn’t load this page", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Done", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var profileImage: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageURL = SupabaseServices.shared.publicMediaURL(for: profile?.photoURL) {
                PostPhotoView(url: imageURL, contentMode: .fill)
                .frame(height: 164)
                .clipped()
            } else {
                profileImageFallback
            }

            Label(profile?.isOfficialProfile == true ? "Official profile" : "Verified therapist", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(CatharsiaStyle.ink.opacity(0.78), in: Capsule())
                .padding(16)
        }
        .frame(height: 164)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("\(displayName)’s profile photo")
    }

    private var profileImageFallback: some View {
        ZStack {
            CatharsiaStyle.atmosphere
            Circle()
                .fill(CatharsiaStyle.violet.opacity(0.10))
                .frame(width: 210, height: 210)
            BrainMark(size: 104)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 164)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(displayName)
        .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(CatharsiaStyle.ink)

            if profile?.isOfficialProfile != true {
                Text(displayCredentials)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var profileDetails: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let tiles = profileDetailTiles
        if !tiles.isEmpty {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { tile in
                    BentoProfileInfoTile(tile: tile)
                }
            }
        }
    }

    private var profileDetailTiles: [BentoProfileTile] {
        guard let profile else { return [] }
        var tiles: [BentoProfileTile] = []
        if !profile.specialties.isEmpty {
            tiles.append(.init(title: "Focus", value: profile.specialties.prefix(2).joined(separator: " · "), symbol: "sparkles", tint: CatharsiaStyle.violet, palette: .lilac))
        }
        if let location = profile.officeLocation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            tiles.append(.init(title: "Location", value: location, symbol: "mappin.and.ellipse", tint: CatharsiaStyle.aqua, palette: .aqua))
        }
        if let years = profile.yearsExperience, years > 0 {
            tiles.append(.init(title: "Experience", value: "\(years) years", symbol: "seal", tint: CatharsiaStyle.violet, palette: .periwinkle))
        }
        if profile.telehealth {
            tiles.append(.init(title: "Sessions", value: "Online available", symbol: "video", tint: CatharsiaStyle.aqua, palette: .mint))
        }
        if !profile.languages.isEmpty {
            tiles.append(.init(title: "Languages", value: profile.languages.prefix(3).joined(separator: " · "), symbol: "character.bubble", tint: CatharsiaStyle.violet, palette: .paper))
        }
        if !profile.insuranceAccepted.isEmpty {
            tiles.append(.init(title: "Insurance", value: profile.insuranceAccepted.prefix(2).joined(separator: " · "), symbol: "cross.case", tint: CatharsiaStyle.aqua, palette: .aqua))
        }
        return tiles
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let destination = primaryActionURL {
            Link(destination: destination) {
                HStack(spacing: 9) {
                    Text(bookingURL == nil ? "Visit practice website" : "Connect now")
                        .font(.subheadline.weight(.bold))
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(CatharsiaStyle.violet, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var bookingURL: URL? {
        guard let bookingLink = profile?.bookingLink else { return nil }
        return ExternalURLPolicy.url(from: bookingLink)
    }

    private var primaryActionURL: URL? {
        if let bookingURL { return bookingURL }
        guard let website = profile?.website else { return nil }
        return ExternalURLPolicy.url(from: website)
    }

    private var additionalPublicLinks: [BentoLink] {
        (profile?.publicLinks ?? []).filter { $0.destinationURL != primaryActionURL }
    }

    private var displayName: String {
        profile?.fullName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? fallbackName
    }

    private var displayCredentials: String {
        profile?.credentials.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? fallbackCredentials
    }

    @ViewBuilder
    private var linkSection: some View {
        if !additionalPublicLinks.isEmpty || primaryActionURL == nil {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Find a next step")
                if !additionalPublicLinks.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(additionalPublicLinks.enumerated()), id: \.element.id) { index, link in
                            publicLink(link, palette: BentoPalette.cycle(index))
                        }
                    }
                } else {
                    BentoSurfaceCard(surface: .paper) {
                        Label("No public links yet", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Text("Practice details and resources will appear here when available.")
                            .font(.footnote)
                            .foregroundStyle(CatharsiaStyle.muted)
                            .padding(.top, 5)
                    }
                }
                Text("Events, appointments, and resources open on their external websites.")
                    .font(.caption)
                    .foregroundStyle(CatharsiaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func publicLink(_ link: BentoLink, palette: BentoPalette) -> some View {
        if let url = link.destinationURL {
            BentoPublicLinkRow(link: link, url: url, palette: palette)
        }
    }

    private func loadProfile() async {
        do {
            profile = try await service.fetchBentoProfile(professionalID: professionalID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPosts() async {
        isLoadingPosts = true
        defer { isLoadingPosts = false }
        do {
            profilePosts = try await service.fetchProfessionalPosts(professionalID: professionalID)
            feed.cacheProfilePosts(profilePosts)
            if session.isSignedIn {
                await feed.refreshInteractionState(postIDs: profilePosts.map(\.id))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum TherapistProfileSection: String, CaseIterable, Identifiable {
    case posts
    case bento

    var id: String { rawValue }
    var title: String { self == .posts ? "Posts" : "Profile" }
}

private struct TherapistPostTile: View {
    let post: PublishedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                if let first = post.mediaItems.first,
                   first.kind == .photo,
                   let url = SupabaseServices.shared.publicMediaURL(for: first.path) {
                    PostPhotoView(url: url, contentMode: .fill)
                } else {
                    ZStack {
                        CatharsiaStyle.panelRaised
                        VStack(spacing: 8) {
                            Image(systemName: post.mediaItems.first?.kind == .video ? "play.rectangle.fill" : "text.alignleft")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(CatharsiaStyle.violet)
                            if post.mediaItems.first?.kind == .video {
                                Text("Video")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.muted)
                            } else {
                                Text(post.caption)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(5)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(CatharsiaStyle.ink)
                                    .padding(.horizontal, 13)
                            }
                        }
                    }
                }

                if post.mediaItems.count > 1 {
                    Label("\(post.mediaItems.count)", systemImage: "square.stack.3d.up.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(CatharsiaStyle.ink.opacity(0.78), in: Capsule())
                        .padding(9)
                }
            }
            .frame(height: 205)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 8) {
                Label(post.likeCount.formatted(), systemImage: "heart")
                Label(post.commentCount.formatted(), systemImage: "bubble.right")
                Label(post.saveCount.formatted(), systemImage: "bookmark")
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(CatharsiaStyle.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if !post.publishedLabel.isEmpty {
                Text(post.publishedLabel)
                    .font(.caption2)
                    .foregroundStyle(CatharsiaStyle.muted)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.caption.isEmpty ? "Post" : post.caption). \(post.likeCount) likes, \(post.commentCount) comments, \(post.saveCount) saves.")
    }
}

private enum BentoPalette {
    case paper
    case lilac
    case periwinkle
    case aqua
    case mint

    var surface: Color {
        switch self {
        case .paper: .white
        case .lilac: Color(red: 0.944, green: 0.916, blue: 0.980)
        case .periwinkle: Color(red: 0.908, green: 0.916, blue: 0.982)
        case .aqua: Color(red: 0.884, green: 0.953, blue: 0.940)
        case .mint: Color(red: 0.858, green: 0.938, blue: 0.919)
        }
    }

    var iconSurface: Color {
        switch self {
        case .paper: CatharsiaStyle.panelRaised
        case .lilac: Color(red: 0.875, green: 0.816, blue: 0.955)
        case .periwinkle: Color(red: 0.820, green: 0.847, blue: 0.964)
        case .aqua: Color(red: 0.760, green: 0.900, blue: 0.868)
        case .mint: Color(red: 0.722, green: 0.879, blue: 0.838)
        }
    }

    var accent: Color {
        switch self {
        case .aqua, .mint: CatharsiaStyle.aqua
        case .paper, .lilac, .periwinkle: CatharsiaStyle.violet
        }
    }

    static func cycle(_ index: Int) -> BentoPalette {
        [.lilac, .aqua, .periwinkle, .mint, .paper][index % 5]
    }
}

private struct BentoSurfaceCard<Content: View>: View {
    let surface: BentoPalette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
    }
}

private struct BentoProfileTile: Identifiable {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    let palette: BentoPalette
    var id: String { title }
}

private struct BentoProfileInfoTile: View {
    let tile: BentoProfileTile

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: tile.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tile.tint)
                .frame(width: 36, height: 36)
                .background(tile.palette.iconSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(tile.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(CatharsiaStyle.muted)
                Text(tile.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(15)
        .background(tile.palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
    }
}

private struct BentoPublicLinkRow: View {
    let link: BentoLink
    let url: URL
    let palette: BentoPalette

    private var detail: String? {
        link.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 13) {
                Image(systemName: link.kind.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 42, height: 42)
                    .background(palette.iconSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(CatharsiaStyle.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .accessibilityHidden(true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(link.title), opens external website")
        .accessibilityHint(link.detail ?? url.host ?? "")
    }
}

struct BentoPageEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var links: [BentoLink] = []
    @State private var profileName = ""
    @State private var profileBio = ""
    @State private var profileCoreValues = ""
    @State private var profilePhotoURL: String?
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var isPlatformProfile = false
    @State private var isLoading = true
    @State private var isSavingProfileName = false
    @State private var isSavingProfilePhoto = false
    @State private var profileNameSaved = false
    @State private var profilePhotoSaved = false
    @State private var profileContentSaved = false
    @State private var isSavingProfileContent = false
    @State private var isEditorPresented = false
    @State private var editingLink: BentoLink?
    @State private var errorMessage: String?

    private let service = SupabaseInteractionService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if session.isAdmin && isPlatformProfile {
                        profilePhotoCard

                        ContentCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Public profile name")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(CatharsiaStyle.ink)
                                Text("People see this name on your profile and posts. Your sign-in email stays private.")
                                    .font(.subheadline)
                                    .lineSpacing(3)
                                    .foregroundStyle(CatharsiaStyle.muted)
                                TextField("Catharsia", text: $profileName)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 14)
                                    .frame(height: 48)
                                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .accessibilityLabel("Public profile name")

                                HStack {
                                    if profileNameSaved {
                                        Label("Saved", systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(CatharsiaStyle.aqua)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await saveProfileName() }
                                    } label: {
                                        if isSavingProfileName {
                                            ProgressView().tint(.white)
                                                .frame(minWidth: 104, minHeight: 42)
                                        } else {
                                            Text("Save name")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)
                                                .frame(minWidth: 104, minHeight: 42)
                                        }
                                    }
                                    .background(CatharsiaStyle.violet, in: Capsule())
                                    .buttonStyle(.plain)
                                    .disabled(isSavingProfileName || profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }

                        ContentCard {
                            VStack(alignment: .leading, spacing: 11) {
                                Text("About Catharsia")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(CatharsiaStyle.ink)
                                Text("This appears on the official profile. Keep it clear and welcoming; you can change it any time.")
                                    .font(.subheadline)
                                    .foregroundStyle(CatharsiaStyle.muted)
                                TextField("Profile description", text: $profileBio, axis: .vertical)
                                    .lineLimit(3...6)
                                    .padding(13)
                                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .accessibilityLabel("Official profile description")
                                TextField("Core values", text: $profileCoreValues, axis: .vertical)
                                    .lineLimit(3...6)
                                    .padding(13)
                                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .accessibilityLabel("Catharsia core values")
                                HStack {
                                    if profileContentSaved {
                                        Label("Saved", systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(CatharsiaStyle.aqua)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await saveProfileContent() }
                                    } label: {
                                        if isSavingProfileContent {
                                            ProgressView().tint(.white).frame(minWidth: 104, minHeight: 42)
                                        } else {
                                            Text("Save details")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)
                                                .frame(minWidth: 104, minHeight: 42)
                                        }
                                    }
                                    .background(CatharsiaStyle.violet, in: Capsule())
                                    .buttonStyle(.plain)
                                    .disabled(isSavingProfileContent)
                                }
                            }
                        }
                    }

                    ContentCard {
                        HStack(alignment: .top, spacing: 13) {
                            BrainMark(size: 42)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Give people a next step")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(CatharsiaStyle.ink)
                                Text("Add appointments, groups, and helpful links.")
                                    .font(.subheadline)
                                    .lineSpacing(3)
                                    .foregroundStyle(CatharsiaStyle.muted)
                            }
                        }
                    }

                    if isLoading {
                        ProgressView().tint(CatharsiaStyle.violet).frame(maxWidth: .infinity).padding(.top, 18)
                    } else if links.isEmpty {
                        ContentCard {
                            Label("Your profile is ready", systemImage: "person.crop.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CatharsiaStyle.ink)
                            Text("Add your first link. People can open your profile from one of your posts.")
                                .font(.footnote)
                                .lineSpacing(3)
                                .foregroundStyle(CatharsiaStyle.muted)
                                .padding(.top, 5)
                            addLinkButton
                                .padding(.top, 12)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Eyebrow(text: "Your links")
                                Spacer()
                                Text("\(links.count)/6")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.muted)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(links.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { index, link in
                                    linkRow(link)
                                    if index < links.count - 1 {
                                        Rectangle()
                                            .fill(CatharsiaStyle.ink.opacity(0.08))
                                            .frame(height: 1)
                                            .padding(.leading, 57)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                            addLinkButton
                                .disabled(links.count >= 6)
                        }
                    }

                    if let message = session.accountMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(CatharsiaStyle.muted)
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
            .navigationTitle(session.isAdmin ? "Public profile" : "Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismissEditor() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        beginEditing(nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a profile link")
                    .disabled(isLoading || links.count >= 6)
                }
            }
            .task { await loadLinks() }
            .onChange(of: selectedProfilePhoto) { _, item in
                guard let item else { return }
                Task { await importProfilePhoto(item) }
            }
            .sheet(isPresented: $isEditorPresented) {
                BentoLinkEditor(initialLink: editingLink) { link in
                    try await save(link)
                }
            }
            .alert("Profile update", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Done", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var addLinkButton: some View {
        Button { beginEditing(nil) } label: {
            Label("Add a link", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.violet)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || links.count >= 6)
    }

    private var profilePhotoCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Official profile image")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("Shown on your public profile. Replace it whenever the logo changes, or remove it to use the Catharsia mark.")
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(CatharsiaStyle.muted)

                HStack(spacing: 13) {
                    profilePhotoPreview

                    VStack(alignment: .leading, spacing: 8) {
                        if isSavingProfilePhoto {
                            HStack(spacing: 8) {
                                ProgressView().tint(CatharsiaStyle.violet)
                                Text("Saving image…")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(CatharsiaStyle.muted)
                            }
                        } else {
                            PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                                Label("Choose or replace image", systemImage: "photo")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.violet)
                            }
                            .accessibilityHint("Choose a logo or photo for the public official profile.")

                            if profilePhotoURL != nil {
                                Button(role: .destructive) {
                                    Task { await removeProfilePhoto() }
                                } label: {
                                    Label("Remove image", systemImage: "trash")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }

                        if profilePhotoSaved {
                            Label("Image saved", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CatharsiaStyle.aqua)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var profilePhotoPreview: some View {
        Group {
            if let imageURL = SupabaseServices.shared.publicMediaURL(for: profilePhotoURL) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        profilePhotoFallback
                    }
                }
            } else {
                profilePhotoFallback
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityLabel("Official profile image preview")
    }

    private var profilePhotoFallback: some View {
        ZStack {
            CatharsiaStyle.panelRaised
            BrainMark(size: 42)
        }
        .frame(width: 76, height: 76)
    }

    private func linkRow(_ link: BentoLink) -> some View {
        HStack(spacing: 12) {
            Image(systemName: link.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CatharsiaStyle.violet)
                .frame(width: 34, height: 34)
                .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { beginEditing(link) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text(link.detail?.nilIfBlank ?? link.host ?? "External link")
                        .font(.caption)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit link", systemImage: "pencil") { beginEditing(link) }
                Button("Remove link", systemImage: "trash", role: .destructive) {
                    Task { await remove(link) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(link.title) actions")
        }
        .padding(.vertical, 7)
    }

    private func beginEditing(_ link: BentoLink?) {
        editingLink = link
        isEditorPresented = true
    }

    private func save(_ link: BentoLink) async throws {
        var updatedLinks = links
        if let index = updatedLinks.firstIndex(where: { $0.id == link.id }) {
            updatedLinks[index] = link
        } else {
            updatedLinks.append(link)
        }
        updatedLinks = updatedLinks.enumerated().map { index, item in
            BentoLink(id: item.id, title: item.title, detail: item.detail, url: item.url, kind: item.kind, position: index)
        }
        try await service.updateMyBentoLinks(updatedLinks)
        links = updatedLinks
        editingLink = nil
    }

    private func remove(_ link: BentoLink) async {
        let updatedLinks = links.filter { $0.id != link.id }.enumerated().map { index, item in
            BentoLink(id: item.id, title: item.title, detail: item.detail, url: item.url, kind: item.kind, position: index)
        }
        do {
            try await service.updateMyBentoLinks(updatedLinks)
            links = updatedLinks
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLinks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await service.fetchMyBentoProfile()
            links = profile?.customLinks.sorted { $0.position < $1.position } ?? []
            profileName = profile?.fullName ?? ""
            profileBio = profile?.bio ?? ""
            profileCoreValues = profile?.coreValues ?? ""
            profilePhotoURL = profile?.photoURL
            isPlatformProfile = profile?.isOfficialProfile == true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importProfilePhoto(_ item: PhotosPickerItem) async {
        isSavingProfilePhoto = true
        profilePhotoSaved = false
        defer {
            isSavingProfilePhoto = false
            selectedProfilePhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpegData = optimizedProfileJPEG(image) else {
                throw FeedServiceError.invalidProfileImage
            }
            profilePhotoURL = try await service.updateMyPlatformProfilePhoto(jpegData)
            profilePhotoSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeProfilePhoto() async {
        isSavingProfilePhoto = true
        profilePhotoSaved = false
        defer { isSavingProfilePhoto = false }
        do {
            profilePhotoURL = try await service.updateMyPlatformProfilePhoto(nil)
            profilePhotoSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optimizedProfileJPEG(_ image: UIImage) -> Data? {
        let maximumDimension: CGFloat = 1600
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let renderedImage = renderer.image { context in
            UIColor(red: 0.976, green: 0.965, blue: 0.992, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in stride(from: 0.88, through: 0.32, by: -0.08) {
            if let data = renderedImage.jpegData(compressionQuality: quality), data.count <= 8_000_000 {
                return data
            }
        }
        return nil
    }

    private func saveProfileName() async {
        isSavingProfileName = true
        profileNameSaved = false
        defer { isSavingProfileName = false }
        do {
            try await service.updateMyPlatformProfileName(profileName)
            profileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            profileNameSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfileContent() async {
        isSavingProfileContent = true
        profileContentSaved = false
        defer { isSavingProfileContent = false }
        do {
            try await service.updateMyPlatformProfileContent(bio: profileBio, coreValues: profileCoreValues)
            profileContentSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissEditor() {
        dismiss()
    }
}

private struct BentoLinkEditor: View {
    @Environment(\.dismiss) private var dismiss

    let initialLink: BentoLink?
    let onSave: (BentoLink) async throws -> Void

    @State private var title: String
    @State private var detail: String
    @State private var urlText: String
    @State private var kind: BentoLinkKind
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialLink: BentoLink?, onSave: @escaping (BentoLink) async throws -> Void) {
        self.initialLink = initialLink
        self.onSave = onSave
        _title = State(initialValue: initialLink?.title ?? "")
        _detail = State(initialValue: initialLink?.detail ?? "")
        _urlText = State(initialValue: initialLink?.url ?? "")
        _kind = State(initialValue: initialLink?.kind ?? .resource)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    Picker("Type", selection: $kind) {
                        ForEach(BentoLinkKind.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Link title")
                    TextField("Event details or a short note", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Optional link details")
                }

                Section("Destination") {
                    TextField("https://…", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("External destination URL")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(CatharsiaStyle.coral)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CatharsiaStyle.canvas)
            .navigationTitle(initialLink == nil ? "Add a link" : "Edit link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= 60,
              cleanDetail.count <= 140,
              let url = ExternalURLPolicy.url(from: urlText) else {
            errorMessage = FeedServiceError.invalidBentoLink.localizedDescription
            return
        }

        let link = BentoLink(
            id: initialLink?.id ?? UUID().uuidString,
            title: cleanTitle,
            detail: cleanDetail.isEmpty ? nil : cleanDetail,
            url: url.absoluteString,
            kind: kind,
            position: initialLink?.position ?? 0
        )
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await onSave(link)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
