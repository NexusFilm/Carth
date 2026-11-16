import SwiftUI

struct ActivityNotificationCenterView: View {
    @Binding var unreadCount: Int

    let onOpenNotification: (ActivityNotification) -> Void

    @State private var notifications: [ActivityNotification] = []
    @State private var isLoading = true
    @State private var hasError = false
    @State private var actionError: String?
    @State private var isPushSettingsPresented = false
    @State private var isClearAllConfirmationPresented = false

    var body: some View {
        ZStack {
            CatharsiaStyle.canvas.ignoresSafeArea()

            if isLoading && notifications.isEmpty {
                ProgressView()
                    .tint(CatharsiaStyle.violet)
                    .accessibilityLabel("Loading notifications")
            } else if hasError && notifications.isEmpty {
                emptyState(
                    title: "Couldn’t load activity",
                    message: "Pull down to try again.",
                    symbol: "bell.slash",
                    actionTitle: "Try again"
                ) { Task { await load() } }
            } else if notifications.isEmpty {
                emptyState(
                    title: "No activity yet",
                    message: "New likes and comments on your posts will show up here.",
                    symbol: "bell"
                )
            } else {
                notificationList
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !notifications.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPushSettingsPresented = true
                        } label: {
                            Label("Manage alert types", systemImage: "slider.horizontal.3")
                        }
                        Divider()
                        Button(role: .destructive) {
                            isClearAllConfirmationPresented = true
                        } label: {
                            Label("Clear all notifications", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.violet)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Notification options")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $isPushSettingsPresented) {
            NavigationStack {
                NotificationSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isPushSettingsPresented = false }
                                .foregroundStyle(CatharsiaStyle.violet)
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "Clear all notifications?",
            isPresented: $isClearAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear all notifications", role: .destructive) {
                Task { await deleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all activity from your notification center.")
        }
        .tint(CatharsiaStyle.violet)
        .preferredColorScheme(.light)
    }

    private var notificationList: some View {
        List {
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(CatharsiaStyle.coral)
                    .listRowBackground(CatharsiaStyle.canvas)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ForEach(notifications) { notification in
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        Task {
                            await markSeen(notification)
                            onOpenNotification(notification)
                        }
                    } label: {
                        notificationRow(notification)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(notification.isRead ? "Seen" : "New")
                    .accessibilityHint(notification.entityID != nil || notification.destination != nil
                        ? "Opens the related Catharsia page."
                        : "Opens this activity.")

                    Menu {
                        Button {
                            isPushSettingsPresented = true
                        } label: {
                            Label("Manage alert types", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) {
                            Task { await delete(notification) }
                        } label: {
                            Label("Delete notification", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.muted)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More notification actions")
                    .accessibilityHint("Manage alert types or delete this notification.")
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await delete(notification) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        isPushSettingsPresented = true
                    } label: {
                        Label("Alerts", systemImage: "slider.horizontal.3")
                    }
                    .tint(CatharsiaStyle.aqua)
                }
                .listRowInsets(EdgeInsets(top: 11, leading: 18, bottom: 11, trailing: 18))
                .listRowBackground(CatharsiaStyle.canvas)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func emptyState(
        title: String,
        message: String,
        symbol: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
                    .accessibilityAddTraits(.isHeader)
            } description: {
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(CatharsiaStyle.violet)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        }
        .refreshable { await load() }
    }

    private func notificationRow(_ notification: ActivityNotification) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: notification.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(notification.kind == "like" ? CatharsiaStyle.coral : CatharsiaStyle.violet)
                .frame(width: 44, height: 44)
                .background(
                    (notification.kind == "like" ? CatharsiaStyle.coral : CatharsiaStyle.violet).opacity(0.10),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(notification.title)
                    .font(.body.weight(notification.isRead ? .medium : .bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = notification.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(notification.createdAt.formatted(.relative(presentation: .named)))
                    .font(.footnote)
                    .foregroundStyle(CatharsiaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if !notification.isRead {
                Circle()
                    .fill(CatharsiaStyle.violet)
                    .frame(width: 9, height: 9)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await SupabaseNotificationService.shared.listNotifications()
            unreadCount = notifications.filter { !$0.isRead }.count
            hasError = false
        } catch is CancellationError {
            // Navigation can cancel the request; preserve the current screen.
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation { hasError = true }
        }
    }

    private func markSeen(_ notification: ActivityNotification) async {
        guard !notification.isRead else { return }
        do {
            try await SupabaseNotificationService.shared.markRead(notificationID: notification.id)
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index] = replacing(notification, isRead: true)
            }
            actionError = nil
            unreadCount = notifications.filter { !$0.isRead }.count
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                actionError = "Couldn’t update this notification. Try again."
            }
        }
    }

    private func delete(_ notification: ActivityNotification) async {
        do {
            try await SupabaseNotificationService.shared.deleteNotification(notificationID: notification.id)
            withAnimation(.easeOut(duration: 0.2)) {
                notifications.removeAll { $0.id == notification.id }
                unreadCount = notifications.filter { !$0.isRead }.count
            }
            actionError = nil
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                actionError = "Couldn’t delete this notification. Try again."
            }
        }
    }

    private func deleteAll() async {
        do {
            try await SupabaseNotificationService.shared.deleteAllNotifications()
            withAnimation(.easeOut(duration: 0.2)) {
                notifications = []
                unreadCount = 0
            }
            actionError = nil
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                actionError = "Couldn’t clear notifications. Try again."
            }
        }
    }

    private func replacing(_ notification: ActivityNotification, isRead: Bool) -> ActivityNotification {
        ActivityNotification(
            id: notification.id,
            kind: notification.kind,
            title: notification.title,
            detail: notification.detail,
            link: notification.link,
            entityID: notification.entityID,
            isRead: isRead,
            createdAt: notification.createdAt
        )
    }
}
