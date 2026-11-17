import AVFoundation
import SwiftUI
import UIKit

struct ExploreView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var feed = ExploreFeedStore()
    @State private var activeSheet: ExploreSheet?
    @State private var isNotificationCenterPresented = false
    @State private var reportPost: PublishedPost?
    @State private var deletePost: PublishedPost?
    @State private var selectedTopicID: String?
    @State private var unreadNotificationCount = 0
    @State private var isComposerActionsPresented = false
    @State private var wasBackgrounded = false
    @State private var pullRefreshStatus: String?
    @State private var pullRefreshFeedbackID = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CatharsiaStyle.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    topChrome
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 12) {
                            if feed.posts.isEmpty {
                                emptyFeed
                                    .frame(minHeight: 560)
                                    .id("empty-explore-feed")
                            } else {
                                ForEach(feed.posts) { post in
                                    FeedPostPage(
                                        post: post,
                                        engagementActions: engagementActions(for: post),
                                        onOpen: { activeSheet = .detail(post) },
                                        onOpenBento: { activeSheet = .bento(post) },
                                        onDoubleTapLike: {
                                            guard session.isSignedIn else { activeSheet = .signIn; return }
                                            Task { await feed.toggleLike(postID: post.id) }
                                        }
                                    )
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: post.mediaItems.first?.kind == .video ? 500 : 640)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .id(post.id)
                                    .onAppear {
                                        if post.id == feed.posts.last?.id {
                                            Task { await feed.loadMore(isSignedIn: session.isSignedIn) }
                                        }
                                    }
                                }
                            }
                        }
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.always, axes: .vertical)
                        .scrollDismissesKeyboard(.interactively)
                        .refreshable {
                            guard let refreshed = await feed.refreshFeed(isSignedIn: session.isSignedIn) else {
                                return
                            }
                            if refreshed {
                                CatharsiaRefreshChime.play()
                                scrollToLatest(using: scrollProxy)
                            }
                            showPullRefreshFeedback(refreshed ? "You're up to date" : "Couldn’t refresh. Pull to try again.")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .catharsiaExploreTabSelected)) { _ in
                            Task { await refreshLatestAndReturnToTop(using: scrollProxy) }
                        }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .background {
                                wasBackgrounded = true
                                return
                            }
                            guard phase == .active, wasBackgrounded else { return }
                            wasBackgrounded = false
                            Task { await refreshLatestAndReturnToTop(using: scrollProxy) }
                        }
                    }
                }

                if feed.isPullRefreshing || pullRefreshStatus != nil {
                    HStack(spacing: 8) {
                        if feed.isPullRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(CatharsiaStyle.violet)
                        } else {
                            Image(systemName: pullRefreshStatus == "You're up to date" ? "checkmark.circle.fill" : "arrow.clockwise.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pullRefreshStatus == "You're up to date" ? CatharsiaStyle.aqua : CatharsiaStyle.coral)
                        }
                        Text(feed.isPullRefreshing ? "Refreshing Explore" : (pullRefreshStatus ?? ""))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(CatharsiaStyle.panel.opacity(0.96), in: Capsule())
                    .overlay(Capsule().stroke(CatharsiaStyle.violet.opacity(0.14), lineWidth: 1))
                    .shadow(color: CatharsiaStyle.ink.opacity(0.1), radius: 10, y: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 76)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Refreshing Explore")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
                }

                if isComposerActionsPresented {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                isComposerActionsPresented = false
                            }
                        }
                        .accessibilityHidden(true)
                        .zIndex(2)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if session.canPublish {
                    ComposePostView(isComposerActionsPresented: $isComposerActionsPresented) { caption, topicID, media, externalURL in
                        try await feed.publish(caption: caption, topicID: topicID, media: media, externalURL: externalURL)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                feed.setBlockedUserIDs(session.blockedUserIDs)
                // Keep this task alive while session restoration updates the user ID.
                await feed.load(isSignedIn: session.isSignedIn, forceRefresh: true)
                if session.isSignedIn {
                    await feed.refreshInteractionState(postIDs: feed.posts.map(\.id))
                }
                if feed.posts.isEmpty, feed.errorMessage != nil, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(550))
                    if !Task.isCancelled {
                        await feed.load(isSignedIn: session.isSignedIn, forceRefresh: true)
                        if session.isSignedIn {
                            await feed.refreshInteractionState(postIDs: feed.posts.map(\.id))
                        }
                    }
                }
                await refreshUnreadNotificationCount()
            }
            .onChange(of: session.userID) { _, _ in
                guard session.isSignedIn else { return }
                Task { await feed.refreshInteractionState(postIDs: feed.posts.map(\.id)) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .catharsiaPresentNotificationCenter)) { _ in
                if session.isSignedIn { isNotificationCenterPresented = true }
                else { activeSheet = .signIn }
            }
            .navigationDestination(isPresented: $isNotificationCenterPresented) {
                ActivityNotificationCenterView(unreadCount: $unreadNotificationCount) { notification in
                    if let destination = notification.destination {
                        isNotificationCenterPresented = false
                        NotificationCenter.default.post(
                            name: .catharsiaNavigateToTab,
                            object: nil,
                            userInfo: ["destination": destination.rawValue]
                        )
                        return
                    }
                    guard let postID = notification.entityID else { return }
                    Task {
                        if !feed.posts.contains(where: { $0.id == postID }) {
                            await feed.load(isSignedIn: session.isSignedIn, forceRefresh: true)
                        }
                        if let post = feed.posts.first(where: { $0.id == postID }) {
                            activeSheet = .detail(post)
                        }
                    }
                }
                .environment(session)
                .toolbar(.visible, for: .navigationBar)
            }
            .onChange(of: session.blockedUserIDs) { previous, current in
                feed.setBlockedUserIDs(current)
                if session.isSignedIn && !current.isSuperset(of: previous) {
                    Task { await feed.load(isSignedIn: true, forceRefresh: true) }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .signIn:
                    AccountAccessView()
                case let .comments(post):
                    CommentsSheet(post: post, feed: feed, isSignedIn: session.isSignedIn) {
                        activeSheet = .signIn
                    }
                    .environment(session)
                case let .detail(post):
                    NavigationStack {
                        PostDetailView(post: post, feed: feed) {
                            activeSheet = .bento(post)
                        }
                            .environment(session)
                    }
                case let .bento(post):
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
                case let .share(post):
                    ActivityShareSheet(items: shareItems(for: post)) { completed in
                        guard completed else { return }
                        Task { await feed.recordCompletedShare(postID: post.id) }
                    }
                case let .edit(post):
                    ComposePostView(editing: post, isComposerActionsPresented: $isComposerActionsPresented) { postID, caption, retainedMedia, newMedia, externalURL in
                        try await feed.updatePost(
                            postID: postID,
                            caption: caption,
                            retainedMedia: retainedMedia,
                            newMedia: newMedia,
                            externalURL: externalURL
                        )
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .confirmationDialog(deletePost == nil ? "Report this post" : "Delete this post?", isPresented: Binding(
                get: { reportPost != nil || deletePost != nil },
                set: { if !$0 { reportPost = nil; deletePost = nil } }
            ), titleVisibility: .visible) {
                if let post = deletePost {
                    Button("Delete post", role: .destructive) {
                        Task { await feed.deletePost(postID: post.id) }
                        deletePost = nil
                    }
                    Button("Cancel", role: .cancel) { deletePost = nil }
                } else if let post = reportPost {
                    Button("Report for review", role: .destructive) {
                        Task {
                            do { try await feed.report(postID: post.id, reason: "inappropriate") }
                            catch { feed.presentError(error) }
                        }
                        reportPost = nil
                    }
                    Button("Cancel", role: .cancel) { reportPost = nil }
                }
            } message: {
                Text(deletePost == nil ? "Reports are reviewed by the Catharsia team." : "This removes the post and its comments from Explore.")
            }
            .alert("", isPresented: Binding(
                get: { feed.actionMessage != nil },
                set: { if !$0 { feed.clearActionMessage() } }
            )) {
                Button("OK", role: .cancel) { feed.clearActionMessage() }
            } message: {
                Text(feed.actionMessage ?? "")
            }
        }
    }

    @MainActor
    private func refreshLatestAndReturnToTop(using scrollProxy: ScrollViewProxy) async {
        _ = await feed.refreshFeed(isSignedIn: session.isSignedIn, showsPullIndicator: false)
        scrollToLatest(using: scrollProxy)
    }

    private func scrollToLatest(using scrollProxy: ScrollViewProxy) {
        let targetID: String = feed.posts.first?.id ?? "empty-explore-feed"
        if reduceMotion {
            scrollProxy.scrollTo(targetID, anchor: .top)
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                scrollProxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func engagementActions(for post: PublishedPost) -> some View {
        HStack(spacing: 2) {
            FeedActionButton(
                symbol: feed.likedPostIDs.contains(post.id) ? "heart.fill" : "heart",
                label: feed.likedPostIDs.contains(post.id) ? "Unlike" : "Like",
                count: post.likeCount,
                isActive: feed.likedPostIDs.contains(post.id),
                activeColor: CatharsiaStyle.coral
            ) {
                guard session.isSignedIn else { activeSheet = .signIn; return }
                Task { await feed.toggleLike(postID: post.id) }
            }
            FeedActionButton(symbol: "bubble.right", label: "Comments", count: post.commentCount) {
                activeSheet = session.isSignedIn ? .comments(post) : .signIn
            }
            FeedActionButton(
                symbol: "arrowshape.turn.up.right",
                label: "Share",
                count: post.shareCount
            ) {
                activeSheet = .share(post)
            }
            FeedActionButton(
                symbol: feed.savedPostIDs.contains(post.id) ? "bookmark.fill" : "bookmark",
                label: feed.savedPostIDs.contains(post.id) ? "Unsave" : "Save",
                count: post.saveCount,
                isActive: feed.savedPostIDs.contains(post.id),
                activeColor: CatharsiaStyle.violet
            ) {
                guard session.isSignedIn else { activeSheet = .signIn; return }
                Task { await feed.toggleSave(postID: post.id) }
            }
            Menu {
                if session.isSignedIn && post.authorUserID == session.userID {
                    Button { activeSheet = .edit(post) } label: { Label("Edit post", systemImage: "pencil") }
                    Button(role: .destructive) { deletePost = post } label: { Label("Delete post", systemImage: "trash") }
                }
                Button(role: .destructive) {
                    if session.isSignedIn { reportPost = post }
                    else { activeSheet = .signIn }
                } label: {
                    Label("Report post", systemImage: "exclamationmark.bubble")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("More post actions")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(CatharsiaStyle.panel)
        .overlay(alignment: .top) { Rectangle().fill(CatharsiaStyle.ink.opacity(0.07)).frame(height: 1) }
    }

    private var topChrome: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                BrainMark(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Catharsia")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("EXPLORE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(CatharsiaStyle.aqua)
                }
                Spacer()
                Button {
                    if session.isSignedIn { isNotificationCenterPresented = true }
                    else { activeSheet = .signIn }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.78), in: Circle())
                        if unreadNotificationCount > 0 {
                            Circle()
                                .fill(CatharsiaStyle.coral)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(CatharsiaStyle.canvas, lineWidth: 1.5))
                                .offset(x: -2, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unreadNotificationCount > 0
                    ? "Notifications, \(unreadNotificationCount) unread"
                    : "Notifications")
                if !session.isSignedIn {
                    Button { activeSheet = .signIn } label: {
                        Text("Sign in")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(CatharsiaStyle.ink)
                            .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                            .background(.white.opacity(0.11), in: Capsule())
                    }
                }
            }

            Text("Therapist-led ideas and support for everyday wellbeing.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CatharsiaStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !feed.availableTopics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        topicChip(id: nil, title: "For you")
                        ForEach(feed.availableTopics, id: \.id) { topic in
                            topicChip(id: topic.id, title: topic.name)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 11)
        .padding(.bottom, 18)
        .background(LinearGradient(colors: [CatharsiaStyle.canvas.opacity(0.98), CatharsiaStyle.canvas.opacity(0.80), .clear], startPoint: .top, endPoint: .bottom))
    }

    private func topicChip(id: String?, title: String) -> some View {
        let selected = selectedTopicID == id
        return Button {
            selectedTopicID = id
            Task { await feed.selectTopic(id, isSignedIn: session.isSignedIn) }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? CatharsiaStyle.canvas : CatharsiaStyle.ink.opacity(0.9))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(selected ? CatharsiaStyle.violet : CatharsiaStyle.ink.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shareItems(for post: PublishedPost) -> [Any] {
        var items: [Any] = []
        if !post.caption.isEmpty { items.append(post.caption) }
        if let externalLink = post.externalLink { items.append(externalLink.url) }
        for media in post.mediaItems {
            if let url = SupabaseServices.shared.publicMediaURL(for: media.path) { items.append(url) }
        }
        return items.isEmpty ? ["Catharsia"] : items
    }

    private func refreshUnreadNotificationCount() async {
        guard session.isSignedIn else {
            unreadNotificationCount = 0
            return
        }
        let notifications = (try? await SupabaseNotificationService.shared.listNotifications()) ?? []
        unreadNotificationCount = notifications.filter { !$0.isRead }.count
    }

    private func showPullRefreshFeedback(_ message: String) {
        let feedbackID = UUID()
        pullRefreshFeedbackID = feedbackID
        withAnimation(.easeOut(duration: 0.18)) {
            pullRefreshStatus = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.7))
            guard pullRefreshFeedbackID == feedbackID else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                pullRefreshStatus = nil
            }
        }
    }

    @ViewBuilder
    private var emptyFeed: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            BrainGlowMark(size: 116)

            if let error = feed.errorMessage, !feed.isLoading {
                Text("Let’s reconnect")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button("Try again") { Task { await feed.load(isSignedIn: session.isSignedIn, forceRefresh: true) } }
                    .buttonStyle(.borderedProminent)
                    .tint(CatharsiaStyle.violet)
                    .foregroundStyle(CatharsiaStyle.canvas)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .background(CatharsiaStyle.atmosphere)
        .accessibilityElement(children: .contain)
    }
}

private enum ExploreSheet: Identifiable {
    case signIn
    case comments(PublishedPost)
    case detail(PublishedPost)
    case bento(PublishedPost)
    case share(PublishedPost)
    case edit(PublishedPost)

    var id: String {
        switch self {
        case .signIn: "sign-in"
        case let .comments(post): "comments-\(post.id)"
        case let .detail(post): "detail-\(post.id)"
        case let .bento(post): "bento-\(post.id)"
        case let .share(post): "share-\(post.id)"
        case let .edit(post): "edit-\(post.id)"
        }
    }
}

private struct FeedPostPage<Actions: View>: View {
    let post: PublishedPost
    let engagementActions: Actions
    let onOpen: () -> Void
    let onOpenBento: () -> Void
    let onDoubleTapLike: () -> Void
    @State private var selectedMediaPageID: Int? = 0
    @State private var isVisible = false
    @State private var isVideoPausedByUser = false

    private var selectedMediaIndex: Int { selectedMediaPageID ?? 0 }
    private var mediaAspectRatio: CGFloat { post.mediaItems.first?.kind == .video ? 9.0 / 16.0 : 4.0 / 5.0 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                postBackdrop
                if post.mediaItems.isEmpty {
                    CatharsiaStyle.atmosphere.opacity(0.42)
                }

                VStack(alignment: .leading, spacing: 8) {
                    authorIdentity
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.88), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.82), lineWidth: 1))
                    if let conversationSignal {
                        Label(conversationSignal, systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(CatharsiaStyle.aqua)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.90), in: Capsule())
                            .overlay(Capsule().stroke(CatharsiaStyle.aqua.opacity(0.18), lineWidth: 1))
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 14) {
                    Spacer(minLength: 170)
                    if !post.topicName.isEmpty {
                        Text(post.topicName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(CatharsiaStyle.ink.opacity(0.82), in: Capsule())
                    }
                    if !post.caption.isEmpty {
                        Button(action: onOpen) {
                            Text(post.caption)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .tracking(-0.35)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.white)
                                .lineLimit(6)
                                .shadow(color: .black.opacity(0.35), radius: 18, y: 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open the full post")
                    }

                    if let externalLink = post.externalLink {
                        Link(destination: externalLink.url) {
                            Label("Open link", systemImage: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(CatharsiaStyle.ink.opacity(0.82), in: Capsule())
                        }
                        .accessibilityLabel("Open external link to \(externalLink.displayHost)")
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(mediaAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            engagementActions
        }
        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: selectedMediaPageID) { _, _ in isVideoPausedByUser = false }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    @ViewBuilder
    private var postBackdrop: some View {
        if !post.mediaItems.isEmpty {
            GeometryReader { proxy in
                ZStack {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(post.mediaItems.prefix(5).enumerated()), id: \.offset) { entry in
                                let item = entry.element
                                PostMediaBackdrop(
                                    item: item,
                                    isActive: isVisible && selectedMediaIndex == entry.offset,
                                    isPausedByUser: isVideoPausedByUser,
                                    onSingleTap: {
                                        guard item.kind == .video else { return }
                                        isVideoPausedByUser.toggle()
                                    },
                                    onDoubleTap: onDoubleTapLike
                                )
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(entry.offset)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $selectedMediaPageID)
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)

                    if post.mediaItems.count > 1 {
                        VStack {
                            Spacer()
                            CarouselPageIndicator(count: min(post.mediaItems.count, 5), selectedIndex: selectedMediaIndex)
                                .padding(.bottom, 14)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            NeuralBackdrop()
        }
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var conversationSignal: String? {
        guard post.mediaItems.contains(where: { $0.kind == .video }) else { return nil }
        let comments = post.commentCount
        let discussionScore = comments * 4 + post.likeCount
        if discussionScore >= 5_000 { return "Many voices" }
        if discussionScore >= 1_000 { return "Active discussion" }
        if discussionScore >= 250 { return "Growing conversation" }
        if comments >= 5 && discussionScore >= 50 { return "People are talking" }
        return nil
    }

    @ViewBuilder
    private var authorIdentity: some View {
        if post.authorVerified, post.professionalID != nil {
            Button(action: onOpenBento) {
                authorIdentityContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Open this profile, links, and resources")
        } else {
            authorIdentityContent
        }
    }

    private var authorIdentityContent: some View {
        HStack(spacing: 6) {
            Group {
                if post.authorLabel == "Official profile" {
                    BrainMark(size: 16)
                        .padding(5)
                        .background(CatharsiaStyle.panel, in: Circle())
                } else {
                    Text(initials(for: post.authorName))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.canvas)
                        .frame(width: 26, height: 26)
                        .background(
                            LinearGradient(
                                colors: [CatharsiaStyle.aqua, CatharsiaStyle.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(post.authorName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.ink)
                        .lineLimit(1)
                    if post.authorVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(CatharsiaStyle.aqua)
                            .accessibilityLabel(post.authorLabel == "Official profile" ? "Official profile" : "Verified therapist")
                    }
                }
                let subtitle = [
                    post.authorLabel == "Official profile" ? "" : post.authorLabel,
                    post.publishedLabel
                ].filter { !$0.isEmpty }.joined(separator: " · ")
                Text(subtitle.isEmpty ? "Catharsia contributor" : subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .lineLimit(1)
            }
        }
    }
}

struct CarouselPageIndicator: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(count, 5), id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color.white : Color(red: 0.58, green: 0.84, blue: 0.80))
                    .frame(width: count > 3 ? 12 : 18, height: 5)
                    .animation(.easeOut(duration: 0.16), value: selectedIndex)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(CatharsiaStyle.ink.opacity(0.56), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.26), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Media \(selectedIndex + 1) of \(count)")
        .accessibilityHint("Swipe horizontally to move through the post.")
    }
}

struct PostMediaBackdrop: View {
    let item: PostMedia
    let isActive: Bool
    let isPausedByUser: Bool
    var onSingleTap: () -> Void = {}
    var onDoubleTap: () -> Void = {}
    @State private var isFocused = false

    var body: some View {
        Group {
            if let url = SupabaseServices.shared.publicMediaURL(for: item.path) {
                if item.kind == .video {
                    LoopingVideoBackdrop(
                        url: url,
                        isActive: isActive,
                        isPausedByUser: isPausedByUser,
                        onTap: onSingleTap
                    )
                } else {
                    PostPhotoBackdrop(url: url)
                }
            } else {
                NeuralBackdrop()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .scaleEffect(isFocused ? 1.035 : 1)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onLongPressGesture(minimumDuration: 0.32, pressing: { isFocused = $0 }, perform: {})
    }
}

private struct LoopingVideoBackdrop: View {
    let url: URL
    let isActive: Bool
    let isPausedByUser: Bool
    let onTap: () -> Void
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player {
                PlayerLayerView(player: player)
            } else {
                CatharsiaStyle.ink
            }
        }
        .overlay {
            if isPausedByUser && isActive {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(CatharsiaStyle.ink.opacity(0.64), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .onAppear { updatePlayback() }
        .onChange(of: isActive) { _, _ in updatePlayback() }
        .onChange(of: isPausedByUser) { _, _ in updatePlayback() }
        .onTapGesture(perform: onTap)
        .onDisappear { stopPlayback() }
    }

    private func updatePlayback() {
        guard isActive else {
            player?.pause()
            return
        }
        if player == nil {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
        }
        if isPausedByUser {
            player?.pause()
        } else {
            player?.play()
        }
    }

    private func stopPlayback() {
        player?.pause()
        looper = nil
        player?.removeAllItems()
        player = nil
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct NeuralBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CatharsiaStyle.atmosphere
                Circle().fill(CatharsiaStyle.violet.opacity(0.12)).frame(width: 310, height: 310).blur(radius: 55).offset(x: 100, y: -170)
                Circle().fill(CatharsiaStyle.aqua.opacity(0.11)).frame(width: 260, height: 260).blur(radius: 58).offset(x: -120, y: 90)
                BrainMark(size: min(proxy.size.width * 0.8, 310)).opacity(0.15).offset(x: 38, y: -48)
                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.14, y: proxy.size.height * 0.32))
                    path.addCurve(to: CGPoint(x: proxy.size.width * 0.93, y: proxy.size.height * 0.52), control1: CGPoint(x: proxy.size.width * 0.28, y: proxy.size.height * 0.18), control2: CGPoint(x: proxy.size.width * 0.74, y: proxy.size.height * 0.73))
                }
                .stroke(LinearGradient(colors: [CatharsiaStyle.aqua.opacity(0.2), CatharsiaStyle.violet.opacity(0.1)], startPoint: .leading, endPoint: .trailing), lineWidth: 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct FeedActionButton: View {
    let symbol: String
    let label: String
    let count: Int
    var isActive = false
    var activeColor = CatharsiaStyle.violet
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(count.formatted())
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isActive ? activeColor : CatharsiaStyle.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count.formatted())")
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: @MainActor (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onComplete(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
