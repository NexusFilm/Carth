import Foundation

struct ActivityNotification: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let title: String
    let detail: String?
    let link: String?
    let entityID: String?
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title, detail, link
        case entityID = "entity_id"
        case isRead = "read"
        case createdAt = "created_at"
    }

    var destination: CatharsiaAnnouncementDestination? {
        CatharsiaAnnouncementDestination.allCases.first { $0.deepLink == link }
    }

    var symbol: String {
        switch kind {
        case "like": "heart.fill"
        case "comment", "reply": "bubble.left.fill"
        case "verification": "checkmark.seal.fill"
        default: "sparkle"
        }
    }
}

enum CatharsiaAnnouncementDestination: String, CaseIterable, Identifiable, Sendable {
    case explore
    case saved
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: "Explore"
        case .saved: "Saved posts"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .explore: "brain.head.profile"
        case .saved: "bookmark"
        case .profile: "person.crop.circle"
        }
    }

    var deepLink: String { "catharsia://\(rawValue)" }
}
