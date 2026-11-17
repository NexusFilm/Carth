import SwiftUI

enum CatharsiaTab: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case communities = "Communities"
    case saved = "Saved"
    case profile = "Profile"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .explore: "brain.head.profile"
        case .communities: "person.3"
        case .saved: "bookmark"
        case .profile: "person.crop.circle"
        }
    }
}

struct RootTabView: View {
    @AppStorage("hasCompletedWelcomeOnboarding") private var hasCompletedWelcomeOnboarding = false
    @State private var selection: CatharsiaTab = .explore
    @State private var inAppBanner: InAppNotificationBanner?
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if hasCompletedWelcomeOnboarding {
                    mainTabs
                } else {
                    WelcomeOnboardingView {
                        hasCompletedWelcomeOnboarding = true
                    }
                }
            }
            if let inAppBanner {
                Button { open(inAppBanner) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.17), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CATHARSIA")
                                .font(.caption.weight(.bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.82))
                            Text(inAppBanner.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(inAppBanner.body)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .accessibilityHidden(true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [CatharsiaStyle.violet, CatharsiaStyle.aqua],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: CatharsiaStyle.ink.opacity(0.22), radius: 18, y: 8)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(inAppBanner.title). \(inAppBanner.body)")
                .accessibilityHint("Opens the linked Catharsia page or notification inbox.")
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .task { await session.restoreSession() }
        .onReceive(NotificationCenter.default.publisher(for: .catharsiaOpenNotificationCenter)) { _ in
            selection = .explore
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                NotificationCenter.default.post(name: .catharsiaPresentNotificationCenter, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .catharsiaShowInAppNotificationBanner)) { notification in
            guard let title = notification.userInfo?["title"] as? String,
                  let body = notification.userInfo?["body"] as? String else { return }
            showInAppBanner(title: title, body: body, destination: notification.userInfo?["destination"] as? String)
        }
        .onReceive(NotificationCenter.default.publisher(for: .catharsiaNavigateToTab)) { notification in
            guard let rawDestination = notification.userInfo?["destination"] as? String,
                  let destination = CatharsiaAnnouncementDestination(rawValue: rawDestination) else { return }
            switch destination {
            case .explore: selection = .explore
            case .saved: selection = .saved
            case .profile: selection = .profile
            }
        }
        .onChange(of: selection) { _, selectedTab in
            guard selectedTab == .explore else { return }
            NotificationCenter.default.post(name: .catharsiaExploreTabSelected, object: nil)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            ExploreView()
                .tabItem { Label(CatharsiaTab.explore.rawValue, systemImage: CatharsiaTab.explore.symbol) }
                .tag(CatharsiaTab.explore)
            CommunityView()
                .tabItem { Label(CatharsiaTab.communities.rawValue, systemImage: "person.3") }
                .tag(CatharsiaTab.communities)
            SavedView(onExplore: { selection = .explore })
                .tabItem { Label(CatharsiaTab.saved.rawValue, systemImage: "bookmark") }
                .tag(CatharsiaTab.saved)
            AccountView()
                .tabItem { Label(CatharsiaTab.profile.rawValue, systemImage: "person.crop.circle") }
                .tag(CatharsiaTab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CatharsiaBottomDock(
                selection: $selection
            )
        }
    }

    private func showInAppBanner(title: String, body: String, destination: String?) {
        if let current = inAppBanner,
           current.title == title,
           current.body == body,
           Date().timeIntervalSince(current.createdAt) < 8 {
            return
        }
        let banner = InAppNotificationBanner(title: title, body: body, destination: destination)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            inAppBanner = banner
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard inAppBanner?.id == banner.id else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                inAppBanner = nil
            }
        }
    }

    private func open(_ banner: InAppNotificationBanner) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            inAppBanner = nil
        }
        if let destination = banner.destination,
           CatharsiaAnnouncementDestination(rawValue: destination) != nil {
            NotificationCenter.default.post(
                name: .catharsiaNavigateToTab,
                object: nil,
                userInfo: ["destination": destination]
            )
        } else {
            NotificationCenter.default.post(name: .catharsiaOpenNotificationCenter, object: nil)
        }
    }
}

extension Notification.Name {
    static let catharsiaExploreTabSelected = Notification.Name("catharsia.exploreTabSelected")
}

private struct CatharsiaBottomDock: View {
    @Binding var selection: CatharsiaTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.explore)
            tabButton(.communities)
            tabButton(.saved)
            tabButton(.profile)
        }
        .padding(7)
        .frame(maxWidth: 380)
        .background(CatharsiaStyle.canvas, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.95), lineWidth: 1.2))
        .shadow(color: CatharsiaStyle.ink.opacity(0.14), radius: 14, y: 5)
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabButton(_ tab: CatharsiaTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.rawValue)
                        .font(.caption2.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(isSelected ? .white : CatharsiaStyle.violet.opacity(0.82))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if isSelected {
                    Capsule().fill(CatharsiaStyle.violet)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct InAppNotificationBanner: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let destination: String?
    let createdAt = Date()
}
