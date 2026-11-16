import Foundation
import Supabase

final class SupabaseNotificationService: @unchecked Sendable {
    static let shared = SupabaseNotificationService()

    private let services = SupabaseServices.shared

    func listNotifications() async throws -> [ActivityNotification] {
        guard let tenantID = services.configuration.tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await services.client.auth.session.user.id
        return try await services.client.from("kathar_notifications")
            .select("id,kind,title,detail,link,entity_id,read,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("recipient_user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func markRead(notificationID: String) async throws {
        guard let tenantID = services.configuration.tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await services.client.auth.session.user.id
        try await services.client.from("kathar_notifications")
            .update(NotificationReadUpdate(readAt: Date()))
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("recipient_user_id", value: userID.uuidString)
            .eq("id", value: notificationID)
            .eq("read", value: false)
            .execute()
    }

    func deleteNotification(notificationID: String) async throws {
        guard let tenantID = services.configuration.tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await services.client.auth.session.user.id
        try await services.client.from("kathar_notifications")
            .delete()
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("recipient_user_id", value: userID.uuidString)
            .eq("id", value: notificationID)
            .execute()
    }

    func deleteAllNotifications() async throws {
        guard let tenantID = services.configuration.tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await services.client.auth.session.user.id
        try await services.client.from("kathar_notifications")
            .delete()
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("recipient_user_id", value: userID.uuidString)
            .execute()
    }

    func loadPushPreferences() async throws -> PushPreferenceSettings? {
        let userID = try await services.client.auth.session.user.id
        return try await services.client.from("catharsia_push_preferences")
            .select("manual_push_enabled,auto_push_enabled")
            .eq("user_id", value: userID.uuidString)
            .maybeSingle()
            .execute()
            .value
    }

    func savePushPreferences(_ preferences: PushPreferenceSettings) async throws {
        let userID = try await services.client.auth.session.user.id
        let existing = try await loadPushPreferences()
        if existing != nil {
            try await services.client.from("catharsia_push_preferences")
                .update(PushPreferenceUpdate(
                    manualPushEnabled: preferences.manualPushEnabled,
                    autoPushEnabled: preferences.autoPushEnabled
                ))
                .eq("user_id", value: userID.uuidString)
                .execute()
        } else {
            try await services.client.from("catharsia_push_preferences")
                .insert(PushPreferenceInsert(
                    userID: userID,
                    manualPushEnabled: preferences.manualPushEnabled,
                    autoPushEnabled: preferences.autoPushEnabled
                ))
                .execute()
        }
    }
}

struct PushPreferenceSettings: Codable, Sendable, Equatable {
    var manualPushEnabled = false
    var autoPushEnabled = false

    enum CodingKeys: String, CodingKey {
        case manualPushEnabled = "manual_push_enabled"
        case autoPushEnabled = "auto_push_enabled"
    }
}

private struct PushPreferenceUpdate: Encodable, Sendable {
    let manualPushEnabled: Bool
    let autoPushEnabled: Bool
    let updatedAt = Date()

    enum CodingKeys: String, CodingKey {
        case manualPushEnabled = "manual_push_enabled"
        case autoPushEnabled = "auto_push_enabled"
        case updatedAt = "updated_at"
    }
}

private struct PushPreferenceInsert: Encodable, Sendable {
    let userID: UUID
    let manualPushEnabled: Bool
    let autoPushEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case manualPushEnabled = "manual_push_enabled"
        case autoPushEnabled = "auto_push_enabled"
    }
}

private struct NotificationReadUpdate: Encodable, Sendable {
    let read = true
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case read
        case readAt = "read_at"
    }
}
