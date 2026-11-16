import Foundation
import Observation
import SwiftUI

extension Error {
    var isCatharsiaCancellation: Bool {
        if self is CancellationError { return true }

        var current: NSError? = self as NSError
        for _ in 0..<8 {
            guard let candidate = current else { break }
            if candidate.domain == "Swift.CancellationError"
                || (candidate.domain == NSURLErrorDomain && candidate.code == URLError.cancelled.rawValue) {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

@MainActor
@Observable
final class ExploreFeedStore {
    private let feedService = SupabaseInteractionService()
    private let interactions = SupabaseInteractionService()
    private(set) var posts: [PublishedPost] = []
    private(set) var likedPostIDs: Set<String> = []
    private(set) var savedPostIDs: Set<String> = []
    private(set) var blockedUserIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isPullRefreshing = false
    private(set) var errorMessage: String?
    private(set) var actionMessage: String?
    private(set) var nextCursor: String?
    private(set) var hasLoaded = false
    private(set) var pendingLikePostIDs: Set<String> = []
    private(set) var pendingSavePostIDs: Set<String> = []
    private var lastLoadedAt: Date?
    private var selectedTopicID: String?
    private var refreshAfterCurrentLoad = false
    private var pullRefreshTask: Task<Bool?, Never>?
    private var pullRefreshTaskID: UUID?
    private var profilePostSnapshots: [String: PublishedPost] = [:]

    var availableTopics: [(id: String, name: String)] {
        var seen = Set<String>()
        return posts.compactMap { post in
            guard !post.topicID.isEmpty, seen.insert(post.topicID).inserted else { return nil }
            return (post.topicID, post.topicName)
        }
    }

    func load(isSignedIn: Bool, forceRefresh: Bool = false) async {
        if !isSignedIn {
            likedPostIDs = []
            savedPostIDs = []
            blockedUserIDs = []
        }
        if isLoading {
            if forceRefresh { refreshAfterCurrentLoad = true }
            return
        }
        if !forceRefresh, hasLoaded, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 300 {
            posts.removeAll { blockedUserIDs.contains($0.authorUserID) }
            if isSignedIn { await loadInteractions(for: posts.map(\.id), replacing: true) }
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            var page = try await feedService.fetchPublishedPosts(topicID: selectedTopicID, ttl: forceRefresh ? 0 : 300)
            if page.posts.isEmpty, !hasLoaded, selectedTopicID == nil {
                // A transient empty first response should not leave Explore blank until
                // the user navigates away and returns. Retry once before showing empty state.
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                page = try await feedService.fetchPublishedPosts(topicID: nil, ttl: 0)
            }
            posts = page.posts.filter { !blockedUserIDs.contains($0.authorUserID) }
            nextCursor = page.nextCursor
            hasLoaded = true
            lastLoadedAt = Date()
            if isSignedIn { await loadInteractions(for: page.posts.map(\.id), replacing: true) }
        } catch {
            if !isCancellation(error) { errorMessage = error.localizedDescription }
        }
        isLoading = false
        if refreshAfterCurrentLoad {
            refreshAfterCurrentLoad = false
            await load(isSignedIn: isSignedIn, forceRefresh: true)
        }
    }

    /// Returns nil when SwiftUI cancels the refresh, so a cancelled request is not
    /// presented as a failed refresh to the user.
    func refreshFeed(isSignedIn: Bool, showsPullIndicator: Bool = true) async -> Bool? {
        if let pullRefreshTask { return await pullRefreshTask.value }
        let previousLoad = lastLoadedAt
        let refreshID = UUID()
        let refreshTask = Task<Bool?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            if showsPullIndicator {
                withAnimation(.easeOut(duration: 0.18)) { self.isPullRefreshing = true }
            }
            defer {
                if showsPullIndicator {
                    withAnimation(.easeOut(duration: 0.18)) { self.isPullRefreshing = false }
                }
            }

            await self.load(isSignedIn: isSignedIn, forceRefresh: true)
            // If a load was already in progress, load() queues a fresh pass. Keep the
            // native refresh control active until both passes have actually finished.
            while self.isLoading || self.refreshAfterCurrentLoad {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if self.lastLoadedAt == previousLoad && self.errorMessage == nil {
                return nil
            }
            return self.lastLoadedAt != previousLoad && self.errorMessage == nil
        }
        pullRefreshTask = refreshTask
        pullRefreshTaskID = refreshID
        let didRefresh = await refreshTask.value
        if pullRefreshTaskID == refreshID {
            pullRefreshTask = nil
            pullRefreshTaskID = nil
        }
        return didRefresh
    }

    func refreshIfStale(isSignedIn: Bool, olderThan age: TimeInterval = 30) async {
        guard hasLoaded,
              let lastLoadedAt,
              Date().timeIntervalSince(lastLoadedAt) >= age else { return }
        _ = await refreshFeed(isSignedIn: isSignedIn)
    }

    func loadMore(isSignedIn: Bool) async {
        guard !isLoadingMore, let nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await feedService.fetchPublishedPosts(after: nextCursor, topicID: selectedTopicID)
            posts.append(contentsOf: page.posts.filter { post in
                !blockedUserIDs.contains(post.authorUserID) && !posts.contains(where: { $0.id == post.id })
            })
            self.nextCursor = page.nextCursor
            if isSignedIn { await loadInteractions(for: page.posts.map(\.id), replacing: false) }
        } catch is CancellationError {
            // Pagination can be cancelled when its post leaves the viewport.
        } catch {
            if !isCancellation(error) { errorMessage = error.localizedDescription }
        }
    }

    func selectTopic(_ topicID: String?, isSignedIn: Bool) async {
        guard selectedTopicID != topicID else { return }
        selectedTopicID = topicID
        posts = []
        nextCursor = nil
        hasLoaded = false
        await load(isSignedIn: isSignedIn, forceRefresh: true)
    }

    func toggleLike(postID: String) async {
        guard !pendingLikePostIDs.contains(postID) else { return }
        let wasLiked = likedPostIDs.contains(postID)
        let shouldBeLiked = !wasLiked
        pendingLikePostIDs.insert(postID)
        withAnimation(.easeOut(duration: 0.16)) {
            if shouldBeLiked { likedPostIDs.insert(postID) } else { likedPostIDs.remove(postID) }
            adjustCount(for: postID, keyPath: \.likeCount, by: shouldBeLiked ? 1 : -1)
            actionMessage = nil
        }

        do {
            let active = try await interactions.toggleLike(postID: postID, currentlyLiked: wasLiked)
            if active != shouldBeLiked {
                withAnimation(.easeOut(duration: 0.16)) {
                    if active { likedPostIDs.insert(postID) } else { likedPostIDs.remove(postID) }
                    adjustCount(for: postID, keyPath: \.likeCount, by: active ? 1 : -1)
                }
            }
            actionMessage = nil
            pendingLikePostIDs.remove(postID)
            Task { await refreshCounters(postID: postID) }
        } catch {
            withAnimation(.easeOut(duration: 0.16)) {
                if wasLiked { likedPostIDs.insert(postID) } else { likedPostIDs.remove(postID) }
                adjustCount(for: postID, keyPath: \.likeCount, by: wasLiked ? 1 : -1)
            }
            pendingLikePostIDs.remove(postID)
            setActionError(error)
        }
    }

    func toggleSave(postID: String) async {
        guard !pendingSavePostIDs.contains(postID) else { return }

        let wasSaved = savedPostIDs.contains(postID)
        let shouldBeSaved = !wasSaved
        pendingSavePostIDs.insert(postID)
        withAnimation(.easeOut(duration: 0.18)) {
            if shouldBeSaved { savedPostIDs.insert(postID) } else { savedPostIDs.remove(postID) }
            adjustCount(for: postID, keyPath: \.saveCount, by: shouldBeSaved ? 1 : -1)
            actionMessage = nil
        }

        do {
            let active = try await interactions.toggleSave(postID: postID, currentlySaved: wasSaved)
            if active != shouldBeSaved {
                withAnimation(.easeOut(duration: 0.18)) {
                    if active { savedPostIDs.insert(postID) } else { savedPostIDs.remove(postID) }
                    adjustCount(for: postID, keyPath: \.saveCount, by: active ? 1 : -1)
                }
            }
            pendingSavePostIDs.remove(postID)
            actionMessage = nil
            Task { await refreshCounters(postID: postID) }
        } catch {
            withAnimation(.easeOut(duration: 0.18)) {
                if wasSaved { savedPostIDs.insert(postID) } else { savedPostIDs.remove(postID) }
                adjustCount(for: postID, keyPath: \.saveCount, by: wasSaved ? 1 : -1)
            }
            pendingSavePostIDs.remove(postID)
            setActionError(error)
        }
    }

    func recordCompletedShare(postID: String) async {
        do {
            let shareCount = try await interactions.recordPostShare(postID: postID)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index].shareCount = max(0, shareCount)
            } else if var snapshot = profilePostSnapshots[postID] {
                snapshot.shareCount = max(0, shareCount)
                profilePostSnapshots[postID] = snapshot
            }
        } catch {
            setActionError(error)
        }
    }

    func loadComments(postID: String) async throws -> [Comment] {
        try await interactions.listComments(postID: postID)
    }

    func postComment(postID: String, body: String) async throws -> Comment {
        let comment = try await interactions.createComment(postID: postID, body: body)
        adjustCount(for: postID, keyPath: \.commentCount, by: 1)
        await refreshCounters(postID: postID)
        return comment
    }

    func deleteComment(postID: String, commentID: String) async throws {
        try await interactions.deleteComment(postID: postID, commentID: commentID)
        adjustCount(for: postID, keyPath: \.commentCount, by: -1)
        await refreshCounters(postID: postID)
    }

    func deletePost(postID: String) async {
        do {
            let mediaCleanupSucceeded = try await interactions.deletePost(postID: postID)
            withAnimation(.easeOut(duration: 0.2)) {
                posts.removeAll { $0.id == postID }
                likedPostIDs.remove(postID)
                savedPostIDs.remove(postID)
            }
            actionMessage = mediaCleanupSucceeded
                ? "Post deleted."
                : "Post deleted. Some media files could not be cleaned up."
        } catch {
            setActionError(error)
        }
    }

    func report(postID: String, reason: String) async throws {
        try await interactions.reportPost(postID: postID, reason: reason)
    }

    func presentError(_ error: Error) {
        setActionError(error)
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    func setBlockedUserIDs(_ ids: Set<String>) {
        blockedUserIDs = ids
        posts.removeAll { ids.contains($0.authorUserID) }
    }

    func refreshInteractionState(postIDs: [String]) async {
        await loadInteractions(for: postIDs, replacing: true)
    }

    func publish(caption: String, topicID: String, media: [PostMediaUpload], externalURL: String?) async throws {
        _ = try await interactions.publishPost(caption: caption, topicID: topicID, media: media, externalURL: externalURL)
        hasLoaded = false
        await load(isSignedIn: true, forceRefresh: true)
    }

    func updatePost(
        postID: String,
        caption: String,
        retainedMedia: [PostMedia],
        newMedia: [PostMediaUpload],
        externalURL: String?
    ) async throws {
        let removedMediaCleaned = try await interactions.updatePost(
            postID: postID,
            caption: caption,
            retainedMedia: retainedMedia,
            newMedia: newMedia,
            externalURL: externalURL
        )
        hasLoaded = false
        await load(isSignedIn: true, forceRefresh: true)
        actionMessage = removedMediaCleaned ? nil : "Post updated. Some replaced media could not be cleaned up."
    }

    private func loadInteractions(for postIDs: [String], replacing: Bool) async {
        do {
            let state = try await interactions.interactionState(postIDs: postIDs)
            if replacing {
                likedPostIDs = Set(state.likedPostIDs)
                savedPostIDs = Set(state.savedPostIDs)
            } else {
                likedPostIDs.formUnion(state.likedPostIDs)
                savedPostIDs.formUnion(state.savedPostIDs)
            }
        } catch {
            setActionError(error)
        }
    }

    private func setActionError(_ error: Error) {
        guard !isCancellation(error) else { return }
        actionMessage = error.localizedDescription
    }

    private func isCancellation(_ error: Error) -> Bool {
        // Foundation bridges Swift.CancellationError into NSError, and the SDK can
        // wrap transport cancellation as an underlying error.
        Task.isCancelled || error.isCatharsiaCancellation
    }

    func post(withID id: String) -> PublishedPost? {
        posts.first(where: { $0.id == id }) ?? profilePostSnapshots[id]
    }

    func cacheProfilePosts(_ profilePosts: [PublishedPost]) {
        profilePostSnapshots = Dictionary(uniqueKeysWithValues: profilePosts.map { ($0.id, $0) })
    }

    private func adjustCount(for postID: String, keyPath: WritableKeyPath<PublishedPost, Int>, by delta: Int) {
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            posts[index][keyPath: keyPath] = max(0, posts[index][keyPath: keyPath] + delta)
        } else if var snapshot = profilePostSnapshots[postID] {
            snapshot[keyPath: keyPath] = max(0, snapshot[keyPath: keyPath] + delta)
            profilePostSnapshots[postID] = snapshot
        }
    }

    private func refreshCounters(postID: String) async {
        do {
            let counts = try await interactions.fetchPostEngagementCounts(postID: postID)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index].likeCount = counts.likes
                posts[index].commentCount = counts.comments
                posts[index].saveCount = counts.saves
                posts[index].shareCount = counts.shares
            } else if var snapshot = profilePostSnapshots[postID] {
                snapshot.likeCount = counts.likes
                snapshot.commentCount = counts.comments
                snapshot.saveCount = counts.saves
                snapshot.shareCount = counts.shares
                profilePostSnapshots[postID] = snapshot
            }
        } catch {
            // The optimistic local count remains visible until the next feed refresh.
        }
    }
}
