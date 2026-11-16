import SwiftUI

struct CommunityView: View {
    @Environment(SessionStore.self) private var session
    @State private var service = SupabaseCommunityService()
    @State private var communities: [CatharsiaCommunity] = []
    @State private var myMemberships: [CommunityMembership] = []
    @State private var selectedFilter: CommunityFilter = .discover
    @State private var searchText = ""
    @State private var isCreatePresented = false
    @State private var isSignInPresented = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var message: String?

    private var visibleCommunities: [CatharsiaCommunity] {
        let joined = Set(myMemberships.map(\.communityID))
        let owned = UUID(uuidString: session.userID)
        return communities.filter { community in
            let matchesSearch = searchText.isEmpty
                || community.name.localizedCaseInsensitiveContains(searchText)
                || community.topic.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch selectedFilter {
            case .discover: matchesFilter = true
            case .joined: matchesFilter = joined.contains(community.id) || community.ownerUserID == owned
            case .hosting: matchesFilter = session.canPublish && community.ownerUserID == owned
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CatharsiaStyle.atmosphere.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        valueStatement
                        filterPicker
                        if isLoading && communities.isEmpty {
                            ProgressView("Finding communities")
                                .frame(maxWidth: .infinity, minHeight: 180)
                                .tint(CatharsiaStyle.violet)
                        } else if communities.isEmpty, let loadError {
                            loadErrorState(loadError)
                        } else if visibleCommunities.isEmpty {
                            emptyState
                        } else {
                            if let loadError {
                                Label("Couldn’t refresh communities: \(loadError)", systemImage: "wifi.exclamationmark")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(CatharsiaStyle.coral)
                                    .padding(.horizontal, 4)
                            }
                            LazyVStack(spacing: 12) {
                                ForEach(visibleCommunities) { community in
                                    NavigationLink {
                                        CommunityDetailView(community: community)
                                    } label: {
                                        CommunityCard(
                                            community: community,
                                            badge: badge(for: community)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable { await load() }
            }
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.canPublish {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isCreatePresented = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(CatharsiaStyle.violet, in: Circle())
                        }
                        .accessibilityLabel("Create a community")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Find a community")
            .task { await load() }
            .sheet(isPresented: $isCreatePresented) {
                CreateCommunitySheet { name, topic, description, guidelines, limit in
                    try await service.createCommunity(
                        name: name,
                        topic: topic,
                        description: description,
                        guidelines: guidelines,
                        memberLimit: limit,
                        userID: UUID(uuidString: session.userID) ?? UUID()
                    )
                    await load()
                }
                .environment(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isSignInPresented) {
                AccountAccessView().environment(session)
            }
            .alert("Communities", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
        .tint(CatharsiaStyle.violet)
    }

    private var valueStatement: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(CatharsiaStyle.violet)
                .frame(width: 44, height: 44)
                .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Support, with people who get it")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("Therapist-guided spaces for shared support and useful resources.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.83), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(CatharsiaStyle.violet.opacity(0.10), lineWidth: 1))
    }

    private var filterPicker: some View {
        HStack(spacing: 6) {
            ForEach(CommunityFilter.allCases) { filter in
                Button { selectedFilter = filter } label: {
                    Text(filter.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedFilter == filter ? .white : CatharsiaStyle.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selectedFilter == filter {
                                Capsule().fill(CatharsiaStyle.violet)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.66), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            BrainGlowMark(size: 58)
            Text(emptyTitle)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(CatharsiaStyle.ink)
            Text(emptyDescription)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CatharsiaStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
            if selectedFilter == .hosting, session.canPublish {
                Button { isCreatePresented = true } label: {
                    Label("Create a community", systemImage: "plus")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(CatharsiaStyle.violet, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.vertical, 18)
    }

    private func loadErrorState(_ error: String) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Communities didn’t load", systemImage: "wifi.exclamationmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
                Button {
                    Task { await load() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(CatharsiaStyle.violet, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.top, 28)
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .discover: "A new kind of support is taking shape"
        case .joined: "Your circles will live here"
        case .hosting: "Start a space for your people"
        }
    }

    private var emptyDescription: String {
        switch selectedFilter {
        case .discover: "Browse groups led by verified therapists as they open."
        case .joined: "Join a therapist-led group to find its conversations and resources here."
        case .hosting: "Bring people together around a shared need, with resources and conversation in one place."
        }
    }

    private func badge(for community: CatharsiaCommunity) -> String? {
        if let userID = UUID(uuidString: session.userID), community.ownerUserID == userID { return "Your group" }
        if myMemberships.contains(where: { $0.communityID == community.id }) { return "Joined" }
        return nil
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            communities = try await service.communities()
            if session.isSignedIn, let userID = UUID(uuidString: session.userID) {
                myMemberships = try await service.memberships(userID: userID)
            } else {
                myMemberships = []
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private enum CommunityFilter: String, CaseIterable, Identifiable {
    case discover, joined, hosting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: "Discover"
        case .joined: "Your groups"
        case .hosting: "Hosting"
        }
    }
}

private struct CommunityCard: View {
    let community: CatharsiaCommunity
    let badge: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CatharsiaStyle.communityColor(for: community.topic).opacity(0.22))
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CatharsiaStyle.communityColor(for: community.topic))
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(community.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.ink)
                        .lineLimit(1)
                    if let badge {
                        Text(badge.uppercased())
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(CatharsiaStyle.aqua)
                    }
                }
                Text(community.topic)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(community.members) members")
                    Text("·")
                    Text("Therapist-led")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CatharsiaStyle.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CatharsiaStyle.muted.opacity(0.65))
        }
        .padding(14)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
    }
}

private extension CatharsiaStyle {
    static func communityColor(for topic: String) -> Color {
        let palette = [violet, aqua, Color(red: 0.55, green: 0.42, blue: 0.75), Color(red: 0.44, green: 0.60, blue: 0.72)]
        let index = topic.lowercased().unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[index]
    }
}

private struct CreateCommunitySheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let create: (String, String, String, String, Int) async throws -> Void
    @State private var name = ""
    @State private var topic = ""
    @State private var description = ""
    @State private var guidelines = ""
    @State private var memberLimit = 50
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: CommunityField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Community")
                        Text("Create a support space")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Text("Give it a clear name and focus. You can add resources and guidelines later.")
                            .font(.subheadline)
                            .foregroundStyle(CatharsiaStyle.muted)
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 8)

                    ContentCard {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack(spacing: 7) {
                                Image(systemName: session.isAdmin ? "sparkles" : "checkmark.seal.fill")
                                    .foregroundStyle(session.isAdmin ? CatharsiaStyle.violet : CatharsiaStyle.aqua)
                                Text(session.isAdmin ? "Creating as Catharsia" : (session.isTherapist ? "Verified therapist" : "Beta publisher"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.ink)
                            }
                            inputField("Community name", placeholder: "A name people can find", text: $name, field: .name)
                            inputField("Topic", placeholder: "What brings people together?", text: $topic, field: .topic)
                            multiLineField("Short description", placeholder: "What members will find here · optional", text: $description, minLines: 2, maxLines: 3, field: .description)
                            multiLineField("Guidelines", placeholder: "A few words about keeping this space supportive · optional", text: $guidelines, minLines: 3, maxLines: 5, field: .guidelines)
                        }
                    }

                    ContentCard {
                        DisclosureGroup {
                            Stepper(value: $memberLimit, in: 2...500, step: 2) {
                                Text("Up to \(memberLimit) members")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(CatharsiaStyle.ink)
                            }
                            .accessibilityLabel("Community member limit")
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Label("Member limit", systemImage: "person.2")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.ink)
                                Spacer()
                                Text("\(memberLimit)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(CatharsiaStyle.violet)
                            }
                            .contentShape(Rectangle())
                        }
                        .tint(CatharsiaStyle.violet)
                    }

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.aqua)
                        Text("Members sign in to join. Your profile hosts the space.")
                            .font(.footnote)
                            .foregroundStyle(CatharsiaStyle.muted)
                    }
                    .padding(.horizontal, 3)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(CatharsiaStyle.coral)
                            .padding(.horizontal, 3)
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CatharsiaStyle.atmosphere.ignoresSafeArea())
            .navigationTitle("New community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        focusedField = nil
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(CatharsiaStyle.violet) }
                        else { Text("Create").fontWeight(.semibold) }
                    }
                    .disabled(!canCreate || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .tint(CatharsiaStyle.violet)
        .preferredColorScheme(.light)
    }

    private var canCreate: Bool {
        name.communityTrimmedNonempty != nil && topic.communityTrimmedNonempty != nil
    }

    private func inputField(_ title: String, placeholder: String, text: Binding<String>, field: CommunityField) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.ink)
            TextField(placeholder, text: text)
                .font(.body)
                .foregroundStyle(CatharsiaStyle.ink)
                .tint(CatharsiaStyle.violet)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: field)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityLabel(title)
        }
    }

    private func multiLineField(_ title: String, placeholder: String, text: Binding<String>, minLines: Int, maxLines: Int, field: CommunityField) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.ink)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.body)
                .foregroundStyle(CatharsiaStyle.ink)
                .tint(CatharsiaStyle.violet)
                .lineLimit(minLines...maxLines)
                .focused($focusedField, equals: field)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: CGFloat(minLines * 24 + 28), alignment: .topLeading)
                .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityLabel(title)
        }
    }

    private func save() async {
        guard canCreate else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await create(name, topic, description, guidelines, memberLimit)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum CommunityField: Hashable {
        case name, topic, description, guidelines
    }
}

private struct CommunityDetailView: View {
    @Environment(SessionStore.self) private var session
    let community: CatharsiaCommunity
    @State private var service = SupabaseCommunityService()
    @State private var posts: [CommunityDiscussionPost] = []
    @State private var memberships: [CommunityMembership] = []
    @State private var roster: [CommunityMembership] = []
    @State private var isMember = false
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var isSignInPresented = false
    @State private var message: String?
    @State private var draft = ""
    @State private var resourceTitle = ""
    @State private var resourceURL = ""
    @State private var hostPostMode = CommunityHostPostMode.note
    @State private var isPublishing = false

    private var isHost: Bool {
        (UUID(uuidString: session.userID).map { community.ownerUserID == $0 } ?? false) || session.isAdmin
    }

    var body: some View {
        ZStack {
            CatharsiaStyle.atmosphere.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    groupHeader
                    if isHost {
                        hostSnapshot
                    }
                    if isMember || isHost {
                        if isHost { rosterSection }
                        discussionSection
                    } else {
                        joinPrompt
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
        }
        .navigationTitle(community.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isMember || isHost {
                composer
            }
        }
        .task { await load() }
        .onChange(of: session.isSignedIn) { _, _ in Task { await load() } }
        .sheet(isPresented: $isSignInPresented) { AccountAccessView().environment(session) }
        .alert("Community", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(community.topic.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(CatharsiaStyle.aqua)
                    Text(community.name)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.ink)
                }
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .frame(width: 46, height: 46)
                    .background(CatharsiaStyle.panelRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(community.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                 ?? "A therapist-led space to share support, reflection, and practical resources.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(CatharsiaStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label("\(community.members) members", systemImage: "person.2")
                Text("·")
                Label("\(community.memberLimit) max", systemImage: "person.3")
                Spacer()
                Text("THERAPIST LED")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CatharsiaStyle.aqua)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CatharsiaStyle.muted)
            if let guidelines = community.guidelines?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                Label(guidelines, systemImage: "heart.text.square")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.aqua)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
    }

    private var hostSnapshot: some View {
        HStack(spacing: 0) {
            metric(value: "\(community.members)", title: "members")
            Rectangle().fill(CatharsiaStyle.ink.opacity(0.08)).frame(width: 1, height: 38)
            metric(value: "\(posts.count)", title: "conversations")
            Rectangle().fill(CatharsiaStyle.ink.opacity(0.08)).frame(width: 1, height: 38)
            metric(value: "\(max(0, community.memberLimit - community.members))", title: "open spots")
        }
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CatharsiaStyle.violet.opacity(0.10), lineWidth: 1))
    }

    private func metric(value: String, title: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(CatharsiaStyle.ink)
            Text(title).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(CatharsiaStyle.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PEOPLE IN YOUR GROUP")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(CatharsiaStyle.muted)
                Spacer()
                Text("\(roster.count) active")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.aqua)
            }
            if roster.isEmpty {
                Text("Your group roster will appear here as people join.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .padding(.vertical, 8)
            } else {
                ForEach(roster) { member in
                    HStack(spacing: 10) {
                        Text(member.displayName?.first.map { String($0) } ?? "•")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CatharsiaStyle.violet)
                            .frame(width: 34, height: 34)
                            .background(CatharsiaStyle.panelRaised, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName?.nilIfEmpty ?? "Community member")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(CatharsiaStyle.ink)
                            Text(member.role.capitalized)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(CatharsiaStyle.muted)
                        }
                        Spacer()
                        if member.userID != UUID(uuidString: session.userID) && member.role == "member" {
                            Button("Remove", role: .destructive) {
                                Task { await remove(member) }
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(15)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var joinPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A place to keep the conversation going")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CatharsiaStyle.ink)
            Text("Join to take part in therapist-guided conversations and access resources shared with the group.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(CatharsiaStyle.muted)
            Button {
                if session.isSignedIn { Task { await join() } }
                else { isSignInPresented = true }
            } label: {
                HStack {
                    Spacer()
                    if isJoining { ProgressView().tint(.white) }
                    else { Text(session.isSignedIn ? "Join this community" : "Sign in to join") }
                    Spacer()
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.vertical, 13)
                .background(CatharsiaStyle.violet, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isJoining || community.members >= community.memberLimit)
            if community.members >= community.memberLimit {
                Text("This community is currently full.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CatharsiaStyle.coral)
            }
        }
        .padding(18)
        .background(.white.opacity(0.87), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var discussionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSIDE THE COMMUNITY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(CatharsiaStyle.muted)
                Spacer()
                Text("\(posts.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.violet)
            }
            if isLoading {
                ProgressView().tint(CatharsiaStyle.violet).frame(maxWidth: .infinity).padding(.vertical, 22)
            } else if posts.isEmpty {
                Text(isHost ? "Post a welcome note or share your first resource." : "No conversations yet. Share a thought to get started.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .padding(.vertical, 12)
            } else {
                ForEach(posts) { post in
                    CommunityPostCard(post: post, isHost: isHost)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if isHost {
                Picker("Host post type", selection: $hostPostMode) {
                    ForEach(CommunityHostPostMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                if hostPostMode == .resource {
                    TextField("Resource title", text: $resourceTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Secure link (https://)", text: $resourceURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(isHost ? "Share with your group" : "Add to the conversation", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .accessibilityLabel("Community message")
                Button { Task { await publish() } } label: {
                    Image(systemName: isPublishing ? "hourglass" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(draft.communityTrimmedNonempty == nil ? CatharsiaStyle.muted.opacity(0.25) : CatharsiaStyle.violet, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.communityTrimmedNonempty == nil || isPublishing)
                .accessibilityLabel(isHost ? "Publish to the community" : "Post comment")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if session.isSignedIn, let userID = UUID(uuidString: session.userID) {
                memberships = try await service.memberships(userID: userID)
            } else { memberships = [] }
            isMember = memberships.contains { $0.communityID == community.id }
                || (UUID(uuidString: session.userID).map { community.ownerUserID == $0 } ?? false)
                || session.isAdmin
            if isMember {
                posts = try await service.posts(communityID: community.id)
            } else { posts = [] }
            if isHost { roster = try await service.members(communityID: community.id) }
            else { roster = [] }
        } catch {
            posts = []
            message = error.localizedDescription
        }
    }

    private func join() async {
        guard let userID = UUID(uuidString: session.userID) else { isSignInPresented = true; return }
        isJoining = true
        defer { isJoining = false }
        do {
            try await service.join(community, userID: userID, email: session.userEmail, displayName: session.displayName)
            await load()
        } catch { message = error.localizedDescription }
    }

    private func publish() async {
        guard let userID = UUID(uuidString: session.userID), let body = draft.communityTrimmedNonempty else { return }
        if isHost && hostPostMode == .resource {
            guard resourceTitle.communityTrimmedNonempty != nil, let url = URL(string: resourceURL), url.scheme == "https", url.host != nil else {
                message = "Add a title and a valid secure https link for this resource."
                return
            }
        }
        isPublishing = true
        defer { isPublishing = false }
        do {
            try await service.publishPost(
                communityID: community.id,
                kind: isHost ? "group_post" : "comment",
                format: isHost ? hostPostMode.rawValue : nil,
                title: isHost ? (hostPostMode == .resource ? resourceTitle : nil) : nil,
                body: body,
                linkURL: isHost && hostPostMode == .resource ? resourceURL : nil,
                userID: userID,
                authorName: session.displayName
            )
            draft = ""
            resourceTitle = ""
            resourceURL = ""
            await load()
        } catch { message = error.localizedDescription }
    }

    private func remove(_ membership: CommunityMembership) async {
        do { try await service.removeMember(membership); await load() }
        catch { message = error.localizedDescription }
    }
}

private struct CommunityPostCard: View {
    let post: CommunityDiscussionPost
    let isHost: Bool

    private var isResource: Bool { post.format == "resource" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: isResource ? "link" : (post.kind == "group_post" ? "sparkles" : "bubble.left"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isResource ? CatharsiaStyle.aqua : CatharsiaStyle.violet)
                Text(post.title?.nilIfEmpty ?? (isResource ? "A resource for the group" : (post.kind == "group_post" ? "From your therapist" : (post.authorName ?? "Community member"))))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CatharsiaStyle.ink)
                if isResource || post.kind == "group_post" {
                    Text(isResource ? "RESOURCE" : "GUIDANCE")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(CatharsiaStyle.aqua)
                }
                Spacer()
                if post.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(CatharsiaStyle.violet)
                }
            }
            Text(post.body)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(CatharsiaStyle.ink.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            if let link = post.linkURL, let url = URL(string: link), url.scheme == "https" {
                Link(destination: url) {
                    Label("Open resource", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CatharsiaStyle.aqua)
                }
            }
            Text(post.createdAt)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(CatharsiaStyle.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isResource ? CatharsiaStyle.panelRaised.opacity(0.65) : .white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.05), lineWidth: 1))
    }
}

private enum CommunityHostPostMode: String, CaseIterable, Identifiable {
    case note
    case resource
    var id: String { rawValue }
    var title: String { self == .note ? "Guidance" : "Resource" }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var communityTrimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
