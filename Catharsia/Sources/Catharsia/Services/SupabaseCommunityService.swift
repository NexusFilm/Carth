import Foundation
import Supabase

final class SupabaseCommunityService: @unchecked Sendable {
    private let services: SupabaseServices
    private var client: SupabaseClient { services.client }
    private var tenantID: UUID? { services.configuration.tenantID }

    init(services: SupabaseServices = .shared) {
        self.services = services
    }

    func communities() async throws -> [CatharsiaCommunity] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        return try await client.from("kathar_communities")
            .select("id,name,topic,description,cover_url,members,member_limit,professional_id,owner_user_id,guidelines,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .order("members", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func memberships(userID: UUID) async throws -> [CommunityMembership] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        return try await client.from("kathar_community_members")
            .select("id,community_id,user_id,display_name,role,status,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .eq("status", value: "active")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func members(communityID: UUID) async throws -> [CommunityMembership] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        return try await client.from("kathar_community_members")
            .select("id,community_id,user_id,display_name,role,status,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("community_id", value: communityID.uuidString)
            .eq("status", value: "active")
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func posts(communityID: UUID) async throws -> [CommunityDiscussionPost] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        return try await client.from("kathar_community_posts")
            .select("id,community_id,parent_id,kind,title,format,media_url,link_url,author_user_id,author_name,author_credentials,body,pinned,replies,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("community_id", value: communityID.uuidString)
            .order("pinned", ascending: false)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func join(_ community: CatharsiaCommunity, userID: UUID, email: String, displayName: String) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let _: UUID = try await client.rpc("kathar_ensure_current_user").execute().value

        let existing: [CommunityMembership] = try await client.from("kathar_community_members")
            .select("id,community_id,user_id,display_name,role,status,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("community_id", value: community.id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        if let existing = existing.first {
            if existing.status == "active" { return }
            try await client.from("kathar_community_members")
                .update(["status": "active", "updated_at": ISO8601DateFormatter().string(from: Date())])
                .eq("tenant_id", value: tenantID.uuidString)
                .eq("id", value: existing.id.uuidString)
                .execute()
            return
        }

        let membership = CommunityMembershipInsert(
            tenantID: tenantID,
            communityID: community.id,
            communityOwnerID: community.ownerUserID,
            userID: userID,
            email: email.lowercased(),
            displayName: displayName,
            role: "member",
            status: "active"
        )
        try await client.from("kathar_community_members").insert(membership).execute()
    }

    func leave(_ community: CatharsiaCommunity, userID: UUID) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        try await client.from("kathar_community_members").delete()
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("community_id", value: community.id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    func createCommunity(
        name: String,
        topic: String,
        description: String,
        guidelines: String,
        memberLimit: Int,
        userID: UUID
    ) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let _: UUID = try await client.rpc("kathar_ensure_current_user").execute().value
        let identity = try await SupabaseAccountService(services: services).currentIdentity()
        guard identity.emailVerified else { throw FeedServiceError.verifiedEmailRequired }
        guard UUID(uuidString: identity.id) == userID else { throw FeedServiceError.signInRequired }
        let publisherCapabilities = try await SupabaseInteractionService(services: services).publisherCapabilities()
        guard publisherCapabilities.canPublish else {
            throw CommunityServiceError.therapistVerificationRequired
        }
        let professionals: [CommunityProfessional] = try await client.from("kathar_professionals")
            .select("id,credentials")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .eq("verified", value: true)
            .eq("verification_status", value: "verified")
            .in("verification_tier", values: ["verified_clinician", "verified_professional"])
            .limit(1)
            .execute()
            .value
        let row = CommunityCreateInsert(
            tenantID: tenantID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            guidelines: guidelines.trimmingCharacters(in: .whitespacesAndNewlines),
            memberLimit: max(2, min(memberLimit, 500)),
            ownerUserID: userID,
            professionalID: professionals.first?.id,
            isMock: false
        )
        try await client.from("kathar_communities").insert(row).execute()
    }

    func publishPost(
        communityID: UUID,
        kind: String,
        format: String?,
        title: String?,
        body: String,
        linkURL: String?,
        userID: UUID,
        authorName: String
    ) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let row = CommunityPostInsert(
            tenantID: tenantID,
            communityID: communityID,
            kind: kind,
            format: format,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            linkURL: linkURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            authorUserID: userID,
            authorName: authorName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Community member",
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try await client.from("kathar_community_posts").insert(row).execute()
    }

    func removeMember(_ membership: CommunityMembership) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        try await client.from("kathar_community_members")
            .update(["status": "removed", "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: membership.id.uuidString)
            .execute()
    }
}

enum CommunityServiceError: LocalizedError {
    case therapistVerificationRequired

    var errorDescription: String? {
        switch self {
        case .therapistVerificationRequired:
            "A verified therapist, Catharsia administrator, or invited beta publisher can host a community."
        }
    }
}

private struct CommunityProfessional: Decodable, Sendable {
    let id: UUID
    let credentials: String?
}

private struct CommunityMembershipInsert: Encodable, Sendable {
    let tenantID: UUID
    let communityID: UUID
    let communityOwnerID: UUID?
    let userID: UUID
    let email: String
    let displayName: String
    let role: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case email, role, status
        case tenantID = "tenant_id"
        case communityID = "community_id"
        case communityOwnerID = "community_owner_id"
        case userID = "user_id"
        case displayName = "display_name"
    }
}

private struct CommunityCreateInsert: Encodable, Sendable {
    let tenantID: UUID
    let name: String
    let topic: String
    let description: String
    let guidelines: String
    let memberLimit: Int
    let ownerUserID: UUID
    let professionalID: UUID?
    let isMock: Bool

    enum CodingKeys: String, CodingKey {
        case name, topic, description, guidelines
        case tenantID = "tenant_id"
        case memberLimit = "member_limit"
        case ownerUserID = "owner_user_id"
        case professionalID = "professional_id"
        case isMock = "is_mock"
    }
}

private struct CommunityPostInsert: Encodable, Sendable {
    let tenantID: UUID
    let communityID: UUID
    let kind: String
    let format: String?
    let title: String?
    let linkURL: String?
    let authorUserID: UUID
    let authorName: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case kind, format, title, body
        case tenantID = "tenant_id"
        case communityID = "community_id"
        case linkURL = "link_url"
        case authorUserID = "author_user_id"
        case authorName = "author_name"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
