import SwiftUI

struct PostDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let post: PublishedPost
    let feed: ExploreFeedStore
    let onOpenBento: () -> Void
    @State private var showAccess = false
    @State private var showComments = false
    @State private var showSafety = false
    @State private var selectedMediaIndex = 0
    private var currentPost: PublishedPost { feed.post(withID: post.id) ?? post }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !currentPost.mediaItems.isEmpty {
                    TabView(selection: $selectedMediaIndex) {
                        ForEach(Array(currentPost.mediaItems.enumerated()), id: \.offset) { index, item in
                            PostMediaBackdrop(
                                item: item,
                                isActive: selectedMediaIndex == index,
                                isPausedByUser: false
                            )
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(alignment: .bottom) {
                        if currentPost.mediaItems.count > 1 {
                            CarouselPageIndicator(count: currentPost.mediaItems.count, selectedIndex: selectedMediaIndex)
                                .padding(.bottom, 12)
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                Eyebrow(text: currentPost.topicName.isEmpty ? "Explore" : currentPost.topicName)
                Text(currentPost.caption)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(CatharsiaStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if currentPost.body != currentPost.caption {
                    Text(currentPost.body)
                        .font(.body)
                        .lineSpacing(5)
                        .foregroundStyle(CatharsiaStyle.ink.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let externalLink = currentPost.externalLink {
                    externalLinkAction(externalLink)
                }

                author
                actions

                ContentCard {
                    Label("Education, with care", systemImage: "heart.text.square.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.aqua)
                    Text("Posts offer general education and are not individualized care. If you need immediate support in the U.S., call or text 988.")
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .padding(.top, 8)
                    Button("Support and crisis resources") { showSafety = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.violet)
                        .padding(.top, 12)
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .sheet(isPresented: $showAccess) { AccountAccessView().environment(session) }
        .sheet(isPresented: $showComments) { CommentsSheet(post: currentPost, feed: feed, isSignedIn: session.isSignedIn) { showAccess = true }.environment(session) }
        .navigationDestination(isPresented: $showSafety) { SafetySupportView() }
    }

    @ViewBuilder
    private var author: some View {
        if currentPost.authorVerified, currentPost.professionalID != nil {
            Button(action: onOpenBento) {
                authorContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Open this profile, links, and resources")
        } else {
            authorContent
        }
    }

    private var authorContent: some View {
        HStack(spacing: 12) {
            Group {
                if currentPost.authorLabel == "Official profile" {
                    BrainMark(size: 27)
                        .padding(8)
                        .background(CatharsiaStyle.panelRaised, in: Circle())
                } else {
                    Text(currentPost.authorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.canvas)
                        .background(LinearGradient(colors: [CatharsiaStyle.aqua, CatharsiaStyle.violet], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(currentPost.authorName).font(.subheadline.weight(.bold)).foregroundStyle(CatharsiaStyle.ink)
                    if currentPost.authorVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(CatharsiaStyle.aqua) }
                }
                Text(currentPost.authorLabel.isEmpty ? "Catharsia contributor" : currentPost.authorLabel)
                    .font(.caption)
                    .foregroundStyle(CatharsiaStyle.muted)
            }
            Spacer()
            if !currentPost.publishedLabel.isEmpty {
                Text(currentPost.publishedLabel).font(.caption2).foregroundStyle(CatharsiaStyle.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private func externalLinkAction(_ externalLink: PostExternalLink) -> some View {
        Link(destination: externalLink.url) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .frame(width: 42, height: 42)
                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text(externalLink.displayHost)
                        .font(.caption)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .accessibilityHidden(true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open external link to \(externalLink.displayHost)")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            actionButton(symbol: feed.likedPostIDs.contains(currentPost.id) ? "heart.fill" : "heart", title: "Like \(currentPost.likeCount.formatted())", tint: feed.likedPostIDs.contains(currentPost.id) ? CatharsiaStyle.coral : CatharsiaStyle.ink) {
                if session.isSignedIn { Task { await feed.toggleLike(postID: currentPost.id) } } else { showAccess = true }
            }
            actionButton(symbol: "bubble.right", title: "Comment \(currentPost.commentCount.formatted())", tint: CatharsiaStyle.ink) { showComments = true }
            actionButton(symbol: feed.savedPostIDs.contains(currentPost.id) ? "bookmark.fill" : "bookmark", title: "Save \(currentPost.saveCount.formatted())", tint: feed.savedPostIDs.contains(currentPost.id) ? CatharsiaStyle.violet : CatharsiaStyle.ink) {
                if session.isSignedIn { Task { await feed.toggleSave(postID: currentPost.id) } } else { showAccess = true }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(CatharsiaStyle.panel, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct NeuralDetailArtwork: View {
    var body: some View {
        ZStack {
            CatharsiaStyle.atmosphere
            Circle().fill(CatharsiaStyle.violet.opacity(0.18)).frame(width: 190, height: 190).blur(radius: 36).offset(x: 90, y: -50)
            BrainMark(size: 120).opacity(0.32)
        }
    }
}
