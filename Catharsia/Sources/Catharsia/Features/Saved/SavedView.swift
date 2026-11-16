import SwiftUI

private enum SavedCollection: String, CaseIterable, Identifiable {
    case saved
    case liked

    var id: String { rawValue }
    var title: String { self == .saved ? "Saved" : "Likes" }
    var emptyTitle: String { self == .saved ? "Keep what speaks to you" : "Your likes, in one place" }
    var emptyMessage: String {
        self == .saved
            ? "Save a post in Explore and find it here when you need it."
            : "Like a post in Explore to keep it close."
    }
    var actionSymbol: String { self == .saved ? "bookmark.fill" : "heart.fill" }
    var actionLabel: String { self == .saved ? "Remove from saved posts" : "Unlike this post" }
}

struct SavedView: View {
    let onExplore: () -> Void
    @Environment(SessionStore.self) private var session
    @State private var posts: [PublishedPost] = []
    @State private var postsCollection: SavedCollection?
    @State private var selectedCollection: SavedCollection = .saved
    @State private var feed = ExploreFeedStore()
    @State private var showAccess = false
    @State private var selectedBentoPost: PublishedPost?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = SupabaseInteractionService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.isSignedIn {
                    HStack(spacing: 8) {
                        collectionTab(.saved, symbol: "bookmark.fill")
                        collectionTab(.liked, symbol: "heart.fill")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }

                collectionContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
            .navigationTitle(selectedCollection.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAccess) { AccountAccessView().environment(session) }
            .sheet(item: $selectedBentoPost) { post in
                if let professionalID = post.professionalID {
                    TherapistBentoPageView(
                        professionalID: professionalID,
                        fallbackName: post.authorName,
                        fallbackCredentials: post.authorLabel,
                        feed: feed
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .task(id: "\(session.isSignedIn)-\(selectedCollection.rawValue)") {
                if session.isSignedIn {
                    await loadCollection()
                } else {
                    posts = []
                    postsCollection = nil
                    errorMessage = nil
                    isLoading = false
                }
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var collectionContent: some View {
        if !session.isSignedIn {
            emptyState(
                symbol: "bookmark.circle",
                title: "Keep what speaks to you",
                message: "Sign in to save or like posts and find them again here.",
                actionTitle: "Sign in"
            ) { showAccess = true }
        } else if isLoading && posts.isEmpty {
            ProgressView().tint(CatharsiaStyle.violet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if posts.isEmpty {
            if let errorMessage {
                emptyState(symbol: "arrow.clockwise", title: "Let’s try again", message: errorMessage, actionTitle: "Refresh") {
                    Task { await loadCollection() }
                }
            } else {
                emptyState(
                    symbol: selectedCollection == .saved ? "bookmark" : "heart",
                    title: selectedCollection.emptyTitle,
                    message: selectedCollection.emptyMessage,
                    actionTitle: "Explore"
                ) { onExplore() }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .center, spacing: 14) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(CatharsiaStyle.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(2)
                    }
                    ForEach(posts) { post in
                        SavedPostTile(
                            post: post,
                            actionSymbol: selectedCollection.actionSymbol,
                            actionLabel: selectedCollection.actionLabel,
                            destination: {
                                PostDetailView(post: post, feed: feed) {
                                    selectedBentoPost = post
                                }
                            },
                            onRemove: { Task { await removeFromCollection(postID: post.id) } }
                        )
                    }
                }
                .padding(16)
            }
            .refreshable { await loadCollection() }
        }
    }

    private func collectionTab(_ collection: SavedCollection, symbol: String) -> some View {
        let isSelected = selectedCollection == collection
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedCollection = collection }
        } label: {
            Label(collection.title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : CatharsiaStyle.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? CatharsiaStyle.violet : CatharsiaStyle.panel.opacity(0.76),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func emptyState(symbol: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CatharsiaStyle.panelRaised)
                    .frame(width: 78, height: 92)
                    .rotationEffect(.degrees(8))
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(CatharsiaStyle.coral.opacity(0.8))
                            .rotationEffect(.degrees(8))
                    }
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CatharsiaStyle.panel)
                    .frame(width: 78, height: 92)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(CatharsiaStyle.violet)
                    }
                    .rotationEffect(.degrees(-7))
            }
            .padding(.bottom, 8)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(CatharsiaStyle.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(CatharsiaStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CatharsiaStyle.canvas)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(CatharsiaStyle.violet, in: Capsule())
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadCollection() async {
        guard session.isSignedIn else { return }
        let requestedCollection = selectedCollection
        isLoading = true
        errorMessage = nil
        if postsCollection != requestedCollection {
            posts = []
        }
        defer {
            if selectedCollection == requestedCollection { isLoading = false }
        }
        do {
            let ids: [String]
            if requestedCollection == .saved {
                ids = try await service.savedPostIDs()
            } else {
                ids = try await service.likedPostIDs()
            }
            let loadedPosts = try await service.fetchPosts(ids: ids)
            guard selectedCollection == requestedCollection else { return }
            posts = loadedPosts
            postsCollection = requestedCollection
            await feed.refreshInteractionState(postIDs: loadedPosts.map(\.id))
        } catch {
            if !Task.isCancelled, selectedCollection == requestedCollection {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeFromCollection(postID: String) async {
        let requestedCollection = selectedCollection
        if requestedCollection == .saved {
            await feed.toggleSave(postID: postID)
            guard !feed.savedPostIDs.contains(postID) else {
                errorMessage = feed.actionMessage ?? "Couldn’t remove this post yet. Try again."
                return
            }
        } else {
            await feed.toggleLike(postID: postID)
            guard !feed.likedPostIDs.contains(postID) else {
                errorMessage = feed.actionMessage ?? "Couldn’t remove this post yet. Try again."
                return
            }
        }
        guard selectedCollection == requestedCollection else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            posts.removeAll { $0.id == postID }
        }
    }
}

private struct SavedPostTile<Destination: View>: View {
    let post: PublishedPost
    let actionSymbol: String
    let actionLabel: String
    @ViewBuilder let destination: () -> Destination
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                destination()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnail
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.82, contentMode: .fit)
                        .clipped()
                        .overlay(alignment: .topLeading) {
                            if !post.topicName.isEmpty {
                                Text(post.topicName.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.9)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(CatharsiaStyle.ink.opacity(0.72), in: Capsule())
                                    .padding(10)
                            }
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.caption.isEmpty ? (post.mediaItems.isEmpty ? "Shared resource" : "Media post") : post.caption)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .tracking(-0.15)
                            .foregroundStyle(CatharsiaStyle.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            authorAvatar
                            Text([post.authorName, post.publishedLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(CatharsiaStyle.muted)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                        }

                        HStack(spacing: 12) {
                            Label(post.likeCount.formatted(), systemImage: "heart.fill")
                                .foregroundStyle(CatharsiaStyle.coral)
                            Label(post.commentCount.formatted(), systemImage: "bubble.right.fill")
                                .foregroundStyle(CatharsiaStyle.muted)
                            Spacer(minLength: 0)
                        }
                        .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Open the full post")

            Button(action: onRemove) {
                Image(systemName: actionSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(CatharsiaStyle.ink.opacity(0.78), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(9)
            .accessibilityLabel(actionLabel)
        }
        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let firstPhoto = post.mediaItems.first(where: { $0.kind == .photo }),
           let url = SupabaseServices.shared.publicMediaURL(for: firstPhoto.path) {
            PostPhotoView(url: url, contentMode: .fill)
                .overlay(alignment: .bottomTrailing) {
                    if post.mediaItems.count > 1 {
                        Label("\(post.mediaItems.count)", systemImage: "square.stack.3d.up.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(CatharsiaStyle.ink.opacity(0.72), in: Capsule())
                            .padding(10)
                    }
                }
        } else if post.mediaItems.contains(where: { $0.kind == .video }) {
            ZStack {
                CatharsiaStyle.atmosphere
                Image(systemName: "play.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(CatharsiaStyle.ink.opacity(0.66), in: Circle())
                Text("VIDEO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(CatharsiaStyle.aqua)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(12)
            }
        } else {
            ZStack(alignment: .topLeading) {
                CatharsiaStyle.atmosphere
                Circle()
                    .stroke(CatharsiaStyle.aqua.opacity(0.24), lineWidth: 1)
                    .frame(width: 112, height: 112)
                    .offset(x: 88, y: -36)
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: post.externalLink == nil ? "text.quote" : "link")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CatharsiaStyle.violet)
                    Text(post.caption.isEmpty ? post.body : post.caption)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.ink)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(15)
            }
        }
    }

    private var authorAvatar: some View {
        Group {
            if post.authorLabel == "Official profile" {
                BrainMark(size: 15)
                    .padding(3)
                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(post.authorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 21)
                    .background(CatharsiaStyle.aqua, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .frame(width: 21, height: 21)
    }
}
