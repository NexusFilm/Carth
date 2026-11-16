import SwiftUI

struct CommentsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let post: PublishedPost
    let feed: ExploreFeedStore
    let isSignedIn: Bool
    let onSignIn: () -> Void
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var commentToDelete: Comment?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if isLoading {
                            ProgressView().tint(CatharsiaStyle.violet).frame(maxWidth: .infinity).padding(.top, 36)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(CatharsiaStyle.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 36)
                        } else if comments.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 27, weight: .light))
                                    .foregroundStyle(CatharsiaStyle.violet)
                                Text("Start the conversation")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.ink)
                                Text("Be kind, curious, and respectful.")
                                    .font(.subheadline)
                                    .foregroundStyle(CatharsiaStyle.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                        }
                    }
                    .padding(20)
                }

                composerBar
            }
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(CatharsiaStyle.violet) }
            }
            .task { await loadComments() }
            .alert("Comment updated", isPresented: Binding(
                get: { actionMessage != nil },
                set: { if !$0 { actionMessage = nil } }
            )) {
                Button("Done", role: .cancel) { actionMessage = nil }
            } message: {
                Text(actionMessage ?? "")
            }
            .confirmationDialog("Delete this comment?", isPresented: Binding(
                get: { commentToDelete != nil },
                set: { if !$0 { commentToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete comment", role: .destructive) {
                    guard let comment = commentToDelete else { return }
                    Task {
                        do {
                            try await feed.deleteComment(postID: post.id, commentID: comment.id)
                            comments.removeAll { $0.id == comment.id }
                            actionMessage = "Comment deleted."
                        } catch {
                            if !Task.isCancelled && !error.isCatharsiaCancellation {
                                actionMessage = error.localizedDescription
                            }
                        }
                        commentToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { commentToDelete = nil }
            } message: {
                Text("This removes your comment from the post.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(CatharsiaStyle.canvas)
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            commentAvatar(comment)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.ink)
                    if let username = comment.authorUsername, !username.isEmpty {
                        Text("@\(username)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CatharsiaStyle.muted)
                    }
                }
                Text(comment.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .lineSpacing(3)
                    .foregroundStyle(CatharsiaStyle.ink.opacity(0.88))
                Text(relativeDate(comment.createdAt))
                    .font(.caption2)
                    .foregroundStyle(CatharsiaStyle.muted)
            }
            Spacer(minLength: 0)
            if comment.authorUserID == session.userID {
                Menu {
                    Button("Delete comment", systemImage: "trash", role: .destructive) {
                        commentToDelete = comment
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CatharsiaStyle.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Comment actions")
            } else {
                Menu {
                    if isSignedIn {
                        Button("Report comment", systemImage: "flag") {
                            Task { await report(comment) }
                        }
                        if session.blockedUserIDs.contains(comment.authorUserID) {
                            Button("Unblock member", systemImage: "person.crop.circle.badge.checkmark") {
                                Task { await toggleBlock(comment) }
                            }
                        } else {
                            Button("Block member", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                                Task { await toggleBlock(comment) }
                            }
                        }
                    } else {
                        Button("Sign in to report or block", systemImage: "person.crop.circle") { onSignIn() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CatharsiaStyle.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Comment safety options")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func commentAvatar(_ comment: Comment) -> some View {
        if let url = SupabaseServices.shared.publicMediaURL(for: comment.authorPhotoURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    commentAvatarFallback(comment.authorName)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            commentAvatarFallback(comment.authorName)
        }
    }

    private func commentAvatarFallback(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(CatharsiaStyle.canvas)
            .frame(width: 36, height: 36)
            .background(CatharsiaStyle.violet, in: Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var composerBar: some View {
        HStack(spacing: 10) {
            if isSignedIn {
                TextField("Add a thoughtful comment…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Write a comment")
                Button(action: send) {
                    if isSending { ProgressView().tint(CatharsiaStyle.canvas) }
                    else { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)) }
                }
                .foregroundStyle(CatharsiaStyle.canvas)
                .frame(width: 44, height: 44)
                .background(CatharsiaStyle.violet, in: Circle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Send comment")
            } else {
                Button(action: onSignIn) {
                    Text("Sign in to join the conversation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.violet)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(CatharsiaStyle.panel, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(CatharsiaStyle.canvas)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if isSignedIn {
                await session.refreshBlockedUsers()
            }
            comments = try await feed.loadComments(postID: post.id)
                .filter { !session.blockedUserIDs.contains($0.authorUserID) }
        }
        catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func report(_ comment: Comment) async {
        do {
            try await SupabaseInteractionService().reportComment(postID: post.id, commentID: comment.id, reason: "inappropriate")
            actionMessage = "Thanks. This comment was sent for review."
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func toggleBlock(_ comment: Comment) async {
        let isBlocked = session.blockedUserIDs.contains(comment.authorUserID)
        let blockedUser = BlockedUser(userID: comment.authorUserID, name: comment.authorName)
        do {
            try await session.setBlockedUser(blockedUser, blocked: !isBlocked)
            if isBlocked {
                actionMessage = "You can see this member’s comments again."
            } else {
                comments.removeAll { $0.authorUserID == comment.authorUserID }
                actionMessage = "This member’s posts and comments are hidden from your view."
            }
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 600 else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let comment = try await feed.postComment(postID: post.id, body: body)
                comments.append(comment)
                draft = ""
            } catch {
                if !Task.isCancelled && !error.isCatharsiaCancellation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func relativeDate(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}
