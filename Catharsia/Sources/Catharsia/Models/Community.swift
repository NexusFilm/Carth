import Foundation

struct CatharsiaCommunity: Identifiable, Decodable, Hashable, Sendable {
    let id: UUID
    let name: String
    let topic: String
    let description: String?
    let coverURL: String?
    let members: Int
    let memberLimit: Int
    let professionalID: UUID?
    let ownerUserID: UUID?
    let guidelines: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, topic, description, members, guidelines
        case coverURL = "cover_url"
        case memberLimit = "member_limit"
        case professionalID = "professional_id"
        case ownerUserID = "owner_user_id"
        case createdAt = "created_at"
    }
}

struct CommunityMembership: Identifiable, Decodable, Hashable, Sendable {
    let id: UUID
    let communityID: UUID
    let userID: UUID
    let displayName: String?
    let role: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, role, status
        case communityID = "community_id"
        case userID = "user_id"
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct CommunityDiscussionPost: Identifiable, Decodable, Hashable, Sendable {
    let id: UUID
    let communityID: UUID
    let parentID: UUID?
    let kind: String
    let title: String?
    let format: String?
    let mediaURL: String?
    let linkURL: String?
    let authorUserID: UUID?
    let authorName: String?
    let authorCredentials: String?
    let body: String
    let pinned: Bool
    let replies: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, format, body, pinned, replies
        case communityID = "community_id"
        case parentID = "parent_id"
        case mediaURL = "media_url"
        case linkURL = "link_url"
        case authorUserID = "author_user_id"
        case authorName = "author_name"
        case authorCredentials = "author_credentials"
        case createdAt = "created_at"
    }
}
