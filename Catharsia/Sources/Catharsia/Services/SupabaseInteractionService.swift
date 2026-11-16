import Foundation
import Supabase

final class SupabaseInteractionService: @unchecked Sendable {
    private static let feedPageSize = 10
    private static let profileAvatarBucketID = "kathar-profile-avatars"
    private let services: SupabaseServices
    private var client: SupabaseClient { services.client }
    private var tenantID: UUID? { services.configuration.tenantID }

    init(services: SupabaseServices = .shared) {
        self.services = services
    }

    func fetchPublishedPosts(after cursor: String? = nil, topicID: String? = nil, ttl _: Int = 300) async throws -> FeedPage {
        guard services.configuration.isConfigured, let tenantID else { throw FeedServiceError.notConfigured }
        let after: FeedCursor?
        if let cursor { after = try FeedCursor(cursor) } else { after = nil }
        var query = client.from("kathar_posts")
            .select("id,title,summary,body,format,topics,link_url,cover_url,media_url,file_url,media_items,professional_id,author_user_id,author_name,author_credentials,created_at,is_mock,is_test,likes,saves,comment_count,share_count")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("is_mock", value: false)
            .eq("is_test", value: false)
        if let topicID, !topicID.isEmpty { query = query.contains("topics", value: [topicID]) }
        if let after {
            query = query.or("created_at.lt.\(after.createdAt),and(created_at.eq.\(after.createdAt),id.lt.\(after.id))")
        }
        let records: [SupabasePostRecord] = try await query
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(Self.feedPageSize + 1)
            .execute()
            .value
        let pageRecords = Array(records.prefix(Self.feedPageSize))
        let posts = try await hydrate(pageRecords)
        let nextCursor = records.count > Self.feedPageSize
            ? pageRecords.last.map { FeedCursor(record: $0).encoded }
            : nil
        return FeedPage(posts: posts, nextCursor: nextCursor)
    }

    func fetchPosts(ids: [String]) async throws -> [PublishedPost] {
        guard services.configuration.isConfigured, let tenantID, !ids.isEmpty else { return [] }
        let records: [SupabasePostRecord] = try await client.from("kathar_posts")
            .select("id,title,summary,body,format,topics,link_url,cover_url,media_url,file_url,media_items,professional_id,author_user_id,author_name,author_credentials,created_at,is_mock,is_test,likes,saves,comment_count,share_count")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("is_mock", value: false)
            .eq("is_test", value: false)
            .in("id", values: ids)
            .order("created_at", ascending: false)
            .execute()
            .value
        let hydrated = try await hydrate(records)
        let byID = Dictionary(uniqueKeysWithValues: hydrated.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    func fetchProfessionalPosts(professionalID: String) async throws -> [PublishedPost] {
        guard services.configuration.isConfigured,
              let tenantID,
              UUID(uuidString: professionalID) != nil else { return [] }
        let records: [SupabasePostRecord] = try await client.from("kathar_posts")
            .select("id,title,summary,body,format,topics,link_url,cover_url,media_url,file_url,media_items,professional_id,author_user_id,author_name,author_credentials,created_at,is_mock,is_test,likes,saves,comment_count,share_count")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("professional_id", value: professionalID)
            .eq("is_mock", value: false)
            .eq("is_test", value: false)
            .order("created_at", ascending: false)
            .limit(60)
            .execute()
            .value
        return try await hydrate(records)
    }

    func interactionState(postIDs: [String]) async throws -> InteractionState {
        guard let tenantID, !postIDs.isEmpty else { return .empty }
        let userID = try await currentUserID()
        let likes: [PostLikeRow] = try await client.from("kathar_post_likes")
            .select("post_id")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .in("post_id", values: postIDs)
            .execute()
            .value
        let saves: [SavedItemRow] = try await client.from("kathar_saved_items")
            .select("target_id")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("viewer_id", value: userID.uuidString)
            .eq("kind", value: "post")
            .in("target_id", values: postIDs)
            .execute()
            .value
        return InteractionState(likedPostIDs: likes.map(\.postID), savedPostIDs: saves.map(\.targetID))
    }

    func fetchPostEngagementCounts(postID: String) async throws -> PostEngagementCounts {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let rows: [PostEngagementCounts] = try await client.from("kathar_posts")
            .select("likes,saves,comment_count,share_count")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: postID)
            .limit(1)
            .execute()
            .value
        guard let counts = rows.first else { throw FeedServiceError.actionFailed }
        return counts
    }

    func recordPostShare(postID: String) async throws -> Int {
        try await client.rpc(
            "kathar_record_post_share",
            params: RecordPostShareParameters(pPostID: try uuid(postID))
        ).execute().value
    }

    func publisherCapabilities() async throws -> PublisherCapabilities {
        guard services.configuration.isConfigured, let tenantID else { throw FeedServiceError.notConfigured }
        let identity = try await SupabaseAccountService(services: services).currentIdentity()
        let userID = try uuid(identity.id)
        let _: UUID = try await client.rpc("kathar_ensure_current_user").execute().value
        let isAdmin: Bool = try await client.rpc("kathar_is_admin").execute().value
        let professionals: [SupabaseProfessionalRecord] = try await client.from("kathar_professionals")
            .select("id,credentials,verified,verification_status,verification_tier")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .eq("verified", value: true)
            .eq("verification_status", value: "verified")
            .in("verification_tier", values: ["verified_clinician", "verified_professional"])
            .limit(5)
            .execute()
            .value
        let isTherapist = professionals.contains(where: \.isTrustedPublisher)
        let isBetaPublisher: Bool = try await client.rpc("kathar_has_beta_publisher_access").execute().value
        let canPublish = identity.emailVerified && (isAdmin || isTherapist || isBetaPublisher)
        return PublisherCapabilities(
            canPublish: canPublish,
            isAdmin: isAdmin,
            isTherapist: isTherapist,
            isBetaPublisher: isBetaPublisher,
            needsAdminVerification: isAdmin && !identity.emailVerified
        )
    }

    func betaPublisherCodeIsActive() async throws -> Bool {
        try await client.rpc("kathar_beta_publisher_code_is_active").execute().value
    }

    func rotateBetaPublisherCode() async throws -> String {
        try await client.rpc("kathar_rotate_beta_publisher_code").execute().value
    }

    func redeemBetaPublisherCode(_ code: String) async throws -> Bool {
        try await client.rpc(
            "kathar_redeem_beta_publisher_code",
            params: BetaPublisherCodeParameters(pCode: code)
        ).execute().value
    }

    func fetchMyMemberProfile() async throws -> CatharsiaMemberProfile {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let _: UUID = try await client.rpc("kathar_ensure_current_user").execute().value
        let userID = try await currentUserID()
        let rows: [CatharsiaMemberProfile] = try await client.from("kathar_profiles")
            .select("full_name,display_name,username,photo_url")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let profile = rows.first else { throw FeedServiceError.actionFailed }
        return profile
    }

    func updateMyMemberProfile(
        displayName: String,
        username: String,
        photoJPEGData: Data?,
        removePhoto: Bool
    ) async throws -> CatharsiaMemberProfile {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 60 else { throw FeedServiceError.invalidProfileName }

        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let normalizedUsername = cleanedUsername.isEmpty ? nil : cleanedUsername
        if let normalizedUsername,
           normalizedUsername.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) == nil {
            throw FeedServiceError.invalidUsername
        }
        if let photoJPEGData, photoJPEGData.isEmpty || photoJPEGData.count > 4_000_000 {
            throw FeedServiceError.invalidProfileImage
        }

        let _: UUID = try await client.rpc("kathar_ensure_current_user").execute().value
        let userID = try await currentUserID()
        let currentProfile = try await fetchMyMemberProfile()
        let currentPhotoPath = ownedMediaPath(
            for: currentProfile.photoURL,
            tenantID: tenantID,
            userID: userID,
            bucketID: Self.profileAvatarBucketID
        )

        var uploadedPath: String?
        var photoURL = removePhoto ? nil : currentProfile.photoURL
        if let photoJPEGData {
            let path = "\(tenantID.uuidString.lowercased())/\(userID.uuidString.lowercased())/profile-\(UUID().uuidString.lowercased()).jpg"
            try await client.storage.from(Self.profileAvatarBucketID).upload(
                path,
                data: photoJPEGData,
                options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false)
            )
            uploadedPath = path
            guard let publicURL = services.publicMediaURL(for: path, bucketID: Self.profileAvatarBucketID)?.absoluteString else {
                _ = try? await client.storage.from(Self.profileAvatarBucketID).remove(paths: [path])
                throw FeedServiceError.actionFailed
            }
            photoURL = publicURL
        }

        do {
            let updated: [MemberProfileUpdatedRow] = try await client.from("kathar_profiles")
                .update(MemberProfileUpdate(
                    fullName: cleanedName,
                    displayName: cleanedName,
                    username: normalizedUsername,
                    photoURL: photoURL,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                ))
                .eq("tenant_id", value: tenantID.uuidString)
                .eq("id", value: userID.uuidString)
                .select("id")
                .execute()
                .value
            guard !updated.isEmpty else { throw FeedServiceError.actionFailed }
        } catch {
            if let uploadedPath {
                _ = try? await client.storage.from(Self.profileAvatarBucketID).remove(paths: [uploadedPath])
            }
            if error.localizedDescription.localizedCaseInsensitiveContains("kathar_profiles_tenant_username_key") {
                throw FeedServiceError.usernameAlreadyTaken
            }
            throw error
        }

        if (photoJPEGData != nil || removePhoto), let currentPhotoPath, currentPhotoPath != uploadedPath {
            _ = try? await client.storage.from(Self.profileAvatarBucketID).remove(paths: [currentPhotoPath])
        }
        return try await fetchMyMemberProfile()
    }

    func myTherapistApplication() async throws -> TherapistApplication? {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let rows: [TherapistApplication] = try await client.from("kathar_verification_applications")
            .select("id,applicant_user_id,full_name,email,credentials,license_number,license_state,specialties,status,verification_status,verification_notes,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("applicant_user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func submitTherapistApplication(fullName: String, credentials: String, licenseNumber: String, licenseState: String, specialties: [String]) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let identity = try await SupabaseAccountService(services: services).currentIdentity()
        guard identity.emailVerified else { throw FeedServiceError.verifiedEmailRequired }
        let cleanedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCredentials = credentials.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLicense = licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedState = licenseState.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleanedName.count >= 2, cleanedCredentials.count >= 2,
              !cleanedLicense.isEmpty,
              cleanedState.range(of: #"^[A-Z]{2}(-[A-Z0-9]{1,8})?$"#, options: .regularExpression) != nil else {
            throw FeedServiceError.applicationFieldsRequired
        }
        let insert = TherapistApplicationInsert(
            tenantID: tenantID,
            applicantUserID: try uuid(identity.id),
            fullName: cleanedName,
            email: identity.email,
            credentials: cleanedCredentials,
            licenseNumber: cleanedLicense,
            licenseState: cleanedState,
            specialties: specialties
        )
        try await client.from("kathar_verification_applications").insert(insert).execute()
    }

    func pendingTherapistApplications() async throws -> [TherapistApplication] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        return try await client.from("kathar_verification_applications")
            .select("id,applicant_user_id,full_name,email,credentials,license_number,license_state,specialties,status,verification_status,verification_notes,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .in("status", values: ["submitted", "in_review"])
            .order("created_at", ascending: true)
            .limit(100)
            .execute()
            .value
    }

    func reviewTherapistApplication(id: String, decision: String, verificationSource: String?, notes: String?) async throws {
        guard decision == "verified" || decision == "rejected" else { throw FeedServiceError.actionFailed }
        try await client.rpc(
            "kathar_review_verification_application",
            params: ReviewTherapistApplicationParameters(
                pApplicationID: try uuid(id),
                pDecision: decision,
                pVerificationSource: verificationSource,
                pNotes: notes
            )
        ).execute()
    }

    func toggleLike(postID: String, currentlyLiked: Bool) async throws -> Bool {
        guard let _ = tenantID else { throw FeedServiceError.notConfigured }
        let postUUID = try uuid(postID)
        let _: Int = try await client.rpc(
            "kathar_toggle_post_like",
            params: ToggleLikeParameters(pPostID: postUUID, pLiked: currentlyLiked)
        ).execute().value
        if !currentlyLiked {
            // The database records the in-app notification; push delivery must not
            // hold the like interaction open after the user has received confirmation.
            Task { await dispatchSocialNotification(action: "like", entityID: postUUID) }
        }
        return !currentlyLiked
    }

    func toggleSave(postID: String, currentlySaved: Bool) async throws -> Bool {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let postUUID = try uuid(postID)
        if currentlySaved {
            try await client.from("kathar_saved_items")
                .delete()
                .eq("tenant_id", value: tenantID.uuidString)
                .eq("viewer_id", value: userID.uuidString)
                .eq("kind", value: "post")
                .eq("target_id", value: postUUID.uuidString)
                .execute()
        } else {
            try await client.from("kathar_saved_items")
                // A save is keyed by the viewer/post pair. Ignore a duplicate row
                // so retries or a stale client state behave like an idempotent save.
                .upsert(
                    SavedItemInsert(tenantID: tenantID, viewerID: userID, targetID: postUUID),
                    onConflict: "viewer_id,kind,target_id",
                    ignoreDuplicates: true
                )
                .execute()
        }
        return !currentlySaved
    }

    func listComments(postID: String) async throws -> [Comment] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let rows: [Comment] = try await client.from("kathar_comments")
            .select("id,author_id,author_name,body,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("post_id", value: try uuid(postID).uuidString)
            .order("created_at", ascending: true)
            .limit(100)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }
        let authorIDs = Array(Set(rows.map(\.authorUserID)))
        let profiles: [SupabaseProfileName] = try await client.from("kathar_profiles")
            .select("id,full_name,display_name,photo_url")
            .eq("tenant_id", value: tenantID.uuidString)
            .in("id", values: authorIDs)
            .execute()
            .value
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return rows.map { row in
            var comment = row
            if let profile = profilesByID[row.authorUserID] {
                comment.authorName = profile.displayName ?? profile.fullName ?? row.authorName
                comment.authorPhotoURL = profile.photoURL
                comment.authorUsername = profile.username
            }
            return comment
        }
    }

    func createComment(postID: String, body: String) async throws -> Comment {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 600 else { throw FeedServiceError.actionFailed }
        let identity = try await SupabaseAccountService(services: services).currentIdentity()
        let userID = try uuid(identity.id)
        let capabilities = try await publisherCapabilities()
        let memberProfile = try await fetchMyMemberProfile()
        let insert = CommentInsert(
            tenantID: tenantID,
            postID: try uuid(postID),
            authorID: userID,
            authorName: memberProfile.displayName ?? memberProfile.fullName ?? identity.name,
            isProfessional: capabilities.isTherapist,
            body: text
        )
        try await client.from("kathar_comments").insert(insert).execute()
        let rows: [Comment] = try await client.from("kathar_comments")
            .select("id,author_id,author_name,body,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("post_id", value: try uuid(postID).uuidString)
            .eq("author_id", value: userID.uuidString)
            .eq("body", value: text)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard var comment = rows.first else { throw FeedServiceError.actionFailed }
        comment.authorPhotoURL = memberProfile.photoURL
        comment.authorUsername = memberProfile.username
        await dispatchSocialNotification(action: "comment", entityID: try uuid(comment.id))
        return comment
    }

    private func dispatchSocialNotification(action: String, entityID: UUID) async {
        struct Request: Encodable, Sendable {
            let action: String
            let entityID: String
            enum CodingKeys: String, CodingKey {
                case action
                case entityID = "entity_id"
            }
        }
        struct Response: Decodable, Sendable { let ok: Bool? }
        do {
            let _: Response = try await client.functions.invoke(
                "catharsia-push",
                options: FunctionInvokeOptions(method: .post, body: Request(action: action, entityID: entityID.uuidString))
            )
        } catch {
            // The database trigger already saved the in-app notification; push delivery can retry later.
        }
    }

    func deleteComment(postID: String, commentID: String) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let postUUID = try uuid(postID)
        let commentUUID = try uuid(commentID)
        let existing: [Comment] = try await client.from("kathar_comments")
            .select("id,author_id,author_name,body,created_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("post_id", value: postUUID.uuidString)
            .eq("id", value: commentUUID.uuidString)
            .eq("author_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard !existing.isEmpty else { throw FeedServiceError.actionFailed }
        try await client.from("kathar_comments").delete()
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("post_id", value: postUUID.uuidString)
            .eq("id", value: commentUUID.uuidString)
            .eq("author_id", value: userID.uuidString)
            .execute()
    }

    /// Deletes the signed-in author's post and then removes objects in that author's tenant folder.
    /// A false result means the post is gone but one or more storage objects could not be cleaned up.
    func deletePost(postID: String) async throws -> Bool {
        guard services.configuration.isConfigured, let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let postUUID = try uuid(postID)
        let matches: [PostDeleteRecord] = try await client.from("kathar_posts")
            .select("media_items,cover_url,media_url,file_url")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: postUUID.uuidString)
            .eq("author_user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let record = matches.first else { throw FeedServiceError.actionFailed }

        try await client.from("kathar_posts").delete()
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: postUUID.uuidString)
            .eq("author_user_id", value: userID.uuidString)
            .execute()

        let prefix = "\(tenantID.uuidString.lowercased())/\(userID.uuidString.lowercased())/"
        let paths = Set((record.mediaItems ?? []).map(\.path) + [record.coverURL, record.mediaURL, record.fileURL].compactMap { $0 })
            .filter { $0.hasPrefix(prefix) }
        guard !paths.isEmpty else { return true }
        do {
            _ = try await client.storage.from(services.configuration.mediaBucketID).remove(paths: Array(paths))
            return true
        } catch {
            return false
        }
    }

    /// Updates the signed-in author's post, uploading replacements before the row changes and
    /// deleting removed objects only after the database update succeeds.
    func updatePost(
        postID: String,
        caption: String,
        retainedMedia: [PostMedia],
        newMedia: [PostMediaUpload],
        externalURL: String?
    ) async throws -> Bool {
        guard services.configuration.isConfigured, let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let postUUID = try uuid(postID)
        let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExternalURL: String?
        if let externalURL, !externalURL.isEmpty {
            guard let url = ExternalURLPolicy.url(from: externalURL) else { throw FeedServiceError.invalidExternalURL }
            cleanExternalURL = url.absoluteString
        } else {
            cleanExternalURL = nil
        }
        guard retainedMedia.count + newMedia.count <= 5,
              !cleanCaption.isEmpty || !retainedMedia.isEmpty || !newMedia.isEmpty || cleanExternalURL != nil else {
            throw FeedServiceError.mediaSelectionInvalid
        }

        let matches: [PostEditRecord] = try await client.from("kathar_posts")
            .select("media_items,cover_url,media_url,file_url,topics,updated_at")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: postUUID.uuidString)
            .eq("author_user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let record = matches.first else { throw FeedServiceError.actionFailed }

        let originalMedia = existingMediaItems(from: record)
        let originalPaths = Set(originalMedia.map(\.path) + [record.coverURL, record.mediaURL, record.fileURL].compactMap { $0 })
        let retainedPaths = retainedMedia.map(\.path)
        guard Set(retainedPaths).count == retainedPaths.count,
              retainedPaths.allSatisfy(originalPaths.contains) else {
            throw FeedServiceError.mediaSelectionInvalid
        }
        let originalMediaByPath = Dictionary(uniqueKeysWithValues: originalMedia.map { ($0.path, $0) })
        let safeRetainedMedia = retainedPaths.compactMap { originalMediaByPath[$0] }

        if !newMedia.isEmpty, !(try await publisherCapabilities()).canPublish {
            throw FeedServiceError.publishingNotAllowed
        }

        let uploadedMedia = try await uploadMedia(newMedia, tenantID: tenantID, userID: userID)
        let combinedMedia = safeRetainedMedia + uploadedMedia
        let firstPath = combinedMedia.first?.path
        let update = PostUpdate(
            caption: cleanCaption,
            format: postFormat(for: combinedMedia),
            topics: record.topics ?? [],
            mediaItems: combinedMedia,
            firstMediaPath: firstPath,
            externalURL: cleanExternalURL
        )

        do {
            let updatedRows: [PostUpdatedRow] = try await client.from("kathar_posts")
                .update(update)
                .eq("tenant_id", value: tenantID.uuidString)
                .eq("id", value: postUUID.uuidString)
                .eq("author_user_id", value: userID.uuidString)
                .eq("updated_at", value: record.updatedAt)
                .select("id")
                .execute()
                .value
            guard !updatedRows.isEmpty else {
                throw FeedServiceError.actionFailed
            }
        } catch {
            let newPaths = uploadedMedia.map(\.path)
            if !newPaths.isEmpty {
                _ = try? await client.storage.from(services.configuration.mediaBucketID).remove(paths: newPaths)
            }
            throw error
        }

        let retainedPathSet = Set(combinedMedia.map(\.path))
        let ownedPrefix = "\(tenantID.uuidString.lowercased())/\(userID.uuidString.lowercased())/"
        let removedPaths = originalPaths
            .subtracting(retainedPathSet)
            .filter { $0.hasPrefix(ownedPrefix) }
        guard !removedPaths.isEmpty else { return true }
        do {
            _ = try await client.storage.from(services.configuration.mediaBucketID).remove(paths: Array(removedPaths))
            return true
        } catch {
            return false
        }
    }

    func savedPostIDs() async throws -> [String] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let rows: [SavedItemRow] = try await client.from("kathar_saved_items")
            .select("target_id")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("viewer_id", value: userID.uuidString)
            .eq("kind", value: "post")
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map(\.targetID)
    }

    func likedPostIDs() async throws -> [String] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let rows: [PostLikeRow] = try await client.from("kathar_post_likes")
            .select("post_id")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map(\.postID)
    }

    func publishPost(caption: String, topicID: String, media: [PostMediaUpload], externalURL: String?) async throws -> String {
        guard services.configuration.isConfigured, let tenantID else { throw FeedServiceError.notConfigured }
        let identity = try await SupabaseAccountService(services: services).currentIdentity()
        let userID = try uuid(identity.id)
        let capabilities = try await publisherCapabilities()
        guard capabilities.canPublish else { throw FeedServiceError.publishingNotAllowed }
        let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExternalURL: String?
        if let externalURL, !externalURL.isEmpty {
            guard let url = ExternalURLPolicy.url(from: externalURL) else { throw FeedServiceError.invalidExternalURL }
            cleanExternalURL = url.absoluteString
        } else {
            cleanExternalURL = nil
        }
        guard media.count <= 5, !media.isEmpty || !cleanCaption.isEmpty || cleanExternalURL != nil else { throw FeedServiceError.mediaSelectionInvalid }

        let professionals = try await verifiedProfessionals(for: userID, tenantID: tenantID)
        let professional = professionals.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile })
            ?? professionals.first(where: \.isTrustedPublisher)
        let storedMedia = try await uploadMedia(media, tenantID: tenantID, userID: userID)

        let postID = UUID()
        let cleanTopic = topicID.trimmingCharacters(in: .whitespacesAndNewlines)
        let officialName = professional?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let insert = PostInsert(
            tenantID: tenantID,
            id: postID,
            title: cleanCaption,
            summary: cleanCaption,
            body: cleanCaption,
            topics: cleanTopic.isEmpty ? [] : [cleanTopic],
            mediaItems: storedMedia,
            externalURL: cleanExternalURL,
            professionalID: professional.flatMap { UUID(uuidString: $0.id) },
            authorUserID: userID,
            authorName: professional?.isOfficialProfile == true
                ? (officialName?.isEmpty == false ? officialName! : "Catharsia")
                : (capabilities.isAdmin ? "Catharsia" : identity.name),
            authorCredentials: professional?.isOfficialProfile == true
                ? "Official profile"
                : professional?.credentials ?? (capabilities.isAdmin ? "Official profile" : (capabilities.isBetaPublisher ? "Beta publisher" : nil))
        )
        do {
            try await client.from("kathar_posts").insert(insert).execute()
        } catch {
            let uploadedPaths = storedMedia.map(\.path)
            if !uploadedPaths.isEmpty {
                _ = try? await client.storage.from(services.configuration.mediaBucketID).remove(paths: uploadedPaths)
            }
            throw error
        }
        return postID.uuidString.lowercased()
    }

    func fetchBentoProfile(professionalID: String) async throws -> BentoProfessionalRecord? {
        guard let tenantID, let professionalUUID = UUID(uuidString: professionalID) else { return nil }
        let rows: [BentoProfessionalRecord] = try await client.from("kathar_professionals")
            .select("id,full_name,credentials,is_platform,photo_url,verified,verification_status,verification_tier,bio,core_values,specialties,years_experience,languages,insurance_accepted,telehealth,office_location,website,booking_link,custom_links")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: professionalUUID.uuidString)
            .eq("verified", value: true)
            .eq("verification_status", value: "verified")
            .in("verification_tier", values: ["verified_clinician", "verified_professional"])
            .limit(1)
            .execute()
            .value
        return rows.first(where: \.isTrustedPublisher)
    }

    func fetchMyBentoProfile() async throws -> BentoProfessionalRecord? {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let professionals = try await verifiedProfessionals(for: userID, tenantID: tenantID)
        guard let professional = professionals.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile })
            ?? professionals.first(where: \.isTrustedPublisher) else { return nil }
        return try await fetchBentoProfile(professionalID: professional.id)
    }

    func fetchOfficialBentoProfile() async throws -> BentoProfessionalRecord? {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let rows: [BentoProfessionalRecord] = try await client.from("kathar_professionals")
            .select("id,full_name,credentials,is_platform,photo_url,verified,verification_status,verification_tier,bio,core_values,specialties,years_experience,languages,insurance_accepted,telehealth,office_location,website,booking_link,custom_links")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("is_platform", value: true)
            .eq("verified", value: true)
            .eq("verification_status", value: "verified")
            .eq("verification_tier", value: "verified_professional")
            .limit(1)
            .execute()
            .value
        return rows.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile })
    }

    func updateMyPlatformProfileContent(bio: String, coreValues: String) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let cleanedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedValues = coreValues.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedBio.count <= 1000, cleanedValues.count <= 1000 else { throw FeedServiceError.actionFailed }
        let isAdmin: Bool = try await client.rpc("kathar_is_admin").execute().value
        guard isAdmin else { throw FeedServiceError.publishingNotAllowed }

        let userID = try await currentUserID()
        let professionals = try await verifiedProfessionals(for: userID, tenantID: tenantID)
        guard let officialProfile = professionals.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile }),
              let profileUUID = UUID(uuidString: officialProfile.id) else {
            throw FeedServiceError.publishingNotAllowed
        }

        let updated: [ProfessionalUpdatedRow] = try await client.from("kathar_professionals")
            .update(PlatformProfileContentUpdate(bio: cleanedBio, coreValues: cleanedValues))
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: profileUUID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .eq("is_platform", value: true)
            .select("id")
            .execute()
            .value
        guard !updated.isEmpty else { throw FeedServiceError.actionFailed }
    }

    func updateMyPlatformProfileName(_ name: String) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 60 else { throw FeedServiceError.invalidProfileName }

        let isAdmin: Bool = try await client.rpc("kathar_is_admin").execute().value
        guard isAdmin else { throw FeedServiceError.publishingNotAllowed }

        let userID = try await currentUserID()
        let professionals = try await verifiedProfessionals(for: userID, tenantID: tenantID)
        guard let officialProfile = professionals.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile }),
              let profileUUID = UUID(uuidString: officialProfile.id) else {
            throw FeedServiceError.publishingNotAllowed
        }

        let updated: [ProfessionalUpdatedRow] = try await client.from("kathar_professionals")
            .update(PlatformProfileNameUpdate(fullName: cleanedName))
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: profileUUID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .eq("is_platform", value: true)
            .select("id")
            .execute()
            .value
        guard !updated.isEmpty else { throw FeedServiceError.actionFailed }
    }

    func updateMyPlatformProfilePhoto(_ jpegData: Data?) async throws -> String? {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        if let jpegData, jpegData.isEmpty || jpegData.count > 8_000_000 {
            throw FeedServiceError.invalidProfileImage
        }

        let isAdmin: Bool = try await client.rpc("kathar_is_admin").execute().value
        guard isAdmin else { throw FeedServiceError.publishingNotAllowed }

        let userID = try await currentUserID()
        let professionals = try await verifiedProfessionals(for: userID, tenantID: tenantID)
        guard let officialProfile = professionals.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile }),
              let profileUUID = UUID(uuidString: officialProfile.id) else {
            throw FeedServiceError.publishingNotAllowed
        }

        let currentPhotoURL = try await fetchBentoProfile(professionalID: officialProfile.id)?.photoURL
        let oldPath = ownedMediaPath(for: currentPhotoURL, tenantID: tenantID, userID: userID)
        let newPath: String?
        if let jpegData {
            let path = "\(tenantID.uuidString.lowercased())/\(userID.uuidString.lowercased())/profile-\(UUID().uuidString.lowercased()).jpg"
            try await client.storage.from(services.configuration.mediaBucketID).upload(
                path,
                data: jpegData,
                options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false)
            )
            newPath = path
        } else {
            newPath = nil
        }

        do {
            let updated: [ProfessionalUpdatedRow] = try await client.from("kathar_professionals")
                .update(PlatformProfilePhotoUpdate(photoURL: newPath))
                .eq("tenant_id", value: tenantID.uuidString)
                .eq("id", value: profileUUID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .eq("is_platform", value: true)
                .select("id")
                .execute()
                .value
            guard !updated.isEmpty else { throw FeedServiceError.actionFailed }
        } catch {
            if let newPath {
                _ = try? await client.storage.from(services.configuration.mediaBucketID).remove(paths: [newPath])
            }
            throw error
        }

        if let oldPath, oldPath != newPath {
            _ = try? await client.storage.from(services.configuration.mediaBucketID).remove(paths: [oldPath])
        }
        return newPath
    }

    func updateMyBentoLinks(_ links: [BentoLink]) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        guard links.count <= 6 else { throw FeedServiceError.bentoLinksLimitExceeded }

        var cleanedLinks: [BentoLink] = []
        for (position, link) in links.enumerated() {
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = link.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 60,
                  (detail?.count ?? 0) <= 140,
                  let url = ExternalURLPolicy.url(from: link.url) else {
                throw FeedServiceError.invalidBentoLink
            }
            cleanedLinks.append(BentoLink(
                id: link.id,
                title: title,
                detail: detail?.isEmpty == true ? nil : detail,
                url: url.absoluteString,
                kind: link.kind,
                position: position
            ))
        }
        guard Set(cleanedLinks.map(\.id)).count == cleanedLinks.count else { throw FeedServiceError.actionFailed }

        let userID = try await currentUserID()
        let professionals = try await verifiedProfessionals(for: userID, tenantID: tenantID)
        guard let professional = professionals.first(where: { $0.isTrustedPublisher && $0.isOfficialProfile })
            ?? professionals.first(where: \.isTrustedPublisher),
              let professionalUUID = UUID(uuidString: professional.id) else {
            throw FeedServiceError.publishingNotAllowed
        }
        let updated: [ProfessionalUpdatedRow] = try await client.from("kathar_professionals")
            .update(BentoLinksUpdate(customLinks: cleanedLinks))
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: professionalUUID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .select("id")
            .execute()
            .value
        guard !updated.isEmpty else { throw FeedServiceError.actionFailed }
    }

    private func uploadMedia(_ media: [PostMediaUpload], tenantID: UUID, userID: UUID) async throws -> [PostMedia] {
        var uploadedPaths: [String] = []
        var storedMedia: [PostMedia] = []
        do {
            for item in media {
                let size = try item.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= CatharsiaMediaLimits.maximumVideoUploadBytes else { throw FeedServiceError.mediaFileTooLarge }
                if item.kind == .video, (item.durationSeconds ?? 0) > CatharsiaMediaLimits.maximumVideoDuration { throw FeedServiceError.videoTooLong }
                let expectedType = item.kind == .video ? "video/mp4" : "image/jpeg"
                guard item.mimeType == expectedType,
                      item.fileExtension.lowercased() == (item.kind == .video ? "mp4" : "jpg") else {
                    throw FeedServiceError.unsupportedMedia
                }
                let path = "\(tenantID.uuidString.lowercased())/\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(item.fileExtension)"
                try await client.storage.from(services.configuration.mediaBucketID).upload(
                    path,
                    fileURL: item.fileURL,
                    options: FileOptions(cacheControl: "31536000", contentType: expectedType, upsert: false)
                )
                uploadedPaths.append(path)
                storedMedia.append(PostMedia(
                    kind: item.kind,
                    path: path,
                    mimeType: expectedType,
                    byteSize: size,
                    durationSeconds: item.durationSeconds
                ))
            }
        } catch {
            if !uploadedPaths.isEmpty {
                _ = try? await client.storage.from(services.configuration.mediaBucketID).remove(paths: uploadedPaths)
            }
            throw error
        }
        return storedMedia
    }

    private func ownedMediaPath(
        for storedValue: String?,
        tenantID: UUID,
        userID: UUID,
        bucketID: String? = nil
    ) -> String? {
        guard let storedValue, !storedValue.isEmpty else { return nil }
        var path = storedValue
        if let url = URL(string: storedValue), url.scheme != nil {
            let marker = "/storage/v1/object/public/\(bucketID ?? services.configuration.mediaBucketID)/"
            guard let range = url.path.range(of: marker),
                  let decodedPath = String(url.path[range.upperBound...]).removingPercentEncoding else {
                return nil
            }
            path = decodedPath
        }

        let requiredPrefix = "\(tenantID.uuidString.lowercased())/\(userID.uuidString.lowercased())/"
        guard path.hasPrefix(requiredPrefix),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            return nil
        }
        return path
    }

    private func postFormat(for media: [PostMedia]) -> String {
        if media.count > 1 { return "carousel" }
        if media.first?.kind == .video { return "video" }
        return "article"
    }

    private func existingMediaItems(from record: PostEditRecord) -> [PostMedia] {
        if let items = record.mediaItems, !items.isEmpty { return items }
        guard let path = [record.coverURL, record.mediaURL, record.fileURL].compactMap({ $0 }).first else { return [] }
        let isVideo = ["mp4", "mov", "m4v"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        return [PostMedia(
            kind: isVideo ? .video : .photo,
            path: path,
            mimeType: isVideo ? "video/mp4" : "image/jpeg",
            byteSize: 0,
            durationSeconds: nil
        )]
    }

    func reportPost(postID: String, reason: String) async throws {
        try await createReport(postID: uuid(postID), commentID: nil, reason: reason)
    }

    func reportComment(postID _: String, commentID: String, reason: String) async throws {
        try await createReport(postID: nil, commentID: uuid(commentID), reason: reason)
    }

    func blockedUsers() async throws -> [BlockedUser] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let rows: [BlockedUserRow] = try await client.from("kathar_user_blocks")
            .select("blocked_user_id")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("blocker_id", value: userID.uuidString)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }
        let ids = rows.map(\.blockedUserID)
        let profiles: [SupabaseProfileName] = try await client.from("kathar_profiles")
            .select("id,full_name,display_name")
            .eq("tenant_id", value: tenantID.uuidString)
            .in("id", values: ids)
            .execute()
            .value
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return ids.compactMap { id in
            guard let profile = byID[id] else { return nil }
            return BlockedUser(userID: id, name: profile.displayName ?? profile.fullName ?? "Member")
        }
    }

    func setBlockedUser(_ user: BlockedUser, blocked: Bool) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let userID = try await currentUserID()
        let blockedID = try uuid(user.userID)
        if blocked {
            try await client.from("kathar_user_blocks")
                .insert(BlockInsert(tenantID: tenantID, blockerID: userID, blockedUserID: blockedID))
                .execute()
        } else {
            try await client.from("kathar_user_blocks")
                .delete()
                .eq("tenant_id", value: tenantID.uuidString)
                .eq("blocker_id", value: userID.uuidString)
                .eq("blocked_user_id", value: blockedID.uuidString)
                .execute()
        }
    }

    func pendingReports() async throws -> [ModerationReport] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        return try await client.from("kathar_reports")
            .select("id,post_id,comment_id,reason,created_at,author_name,content_excerpt")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func reviewReport(id: String, removeContent: Bool) async throws {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let reportID = try uuid(id)
        let matches: [ModerationReport] = try await client.from("kathar_reports")
            .select("id,post_id,comment_id,reason,created_at,author_name,content_excerpt")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: reportID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let report = matches.first else { throw FeedServiceError.actionFailed }
        let userID = try await currentUserID()

        if removeContent {
            if let commentID = report.commentId {
                try await client.from("kathar_comments").delete()
                    .eq("tenant_id", value: tenantID.uuidString)
                    .eq("id", value: commentID)
                    .execute()
            } else if let postID = report.postId {
                try await client.from("kathar_posts").delete()
                    .eq("tenant_id", value: tenantID.uuidString)
                    .eq("id", value: postID)
                    .execute()
            }
        }

        let update = ReportReviewUpdate(
            status: removeContent ? "removed" : "dismissed",
            reviewedBy: userID,
            reviewedAt: CatharsiaISO8601.format(Date())
        )
        try await client.from("kathar_reports").update(update)
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("id", value: reportID.uuidString)
            .execute()
    }

    private func hydrate(_ records: [SupabasePostRecord]) async throws -> [PublishedPost] {
        guard let tenantID else { throw FeedServiceError.notConfigured }
        let professionalIDs = Array(Set(records.compactMap(\.professionalID)))
        let professionalRecords: [String: SupabaseProfessionalRecord]
        if professionalIDs.isEmpty {
            professionalRecords = [:]
        } else {
            let professionals: [SupabaseProfessionalRecord] = try await client.from("kathar_professionals")
                .select("id,full_name,credentials,is_platform,verified,verification_status,verification_tier")
                .eq("tenant_id", value: tenantID.uuidString)
                .in("id", values: professionalIDs)
                .eq("verified", value: true)
                .eq("verification_status", value: "verified")
                .execute()
                .value
            professionalRecords = Dictionary(uniqueKeysWithValues: professionals.filter(\.isTrustedPublisher).map { ($0.id, $0) })
        }
        return records.compactMap { record -> PublishedPost? in
            guard record.isMock != true, record.isTest != true else { return nil }
            return PublishedPost(record: record, verifiedProfessionalsByID: professionalRecords)
        }
    }

    private func verifiedProfessionals(for userID: UUID, tenantID: UUID) async throws -> [SupabaseProfessionalRecord] {
        try await client.from("kathar_professionals")
            .select("id,full_name,credentials,is_platform,verified,verification_status,verification_tier")
            .eq("tenant_id", value: tenantID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .eq("verified", value: true)
            .eq("verification_status", value: "verified")
            .in("verification_tier", values: ["verified_clinician", "verified_professional"])
            .limit(5)
            .execute()
            .value
    }

    private func createReport(postID: UUID?, commentID: UUID?, reason: String) async throws {
        let _: UUID = try await client.rpc(
            "kathar_create_content_report",
            params: CreateReportParameters(pPostID: postID, pCommentID: commentID, pReason: reason)
        ).execute().value
    }

    private func currentUserID() async throws -> UUID {
        let identity = try await SupabaseAccountService(services: services).currentIdentity()
        return try uuid(identity.id)
    }

    private func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else { throw FeedServiceError.actionFailed }
        return id
    }

    private struct FeedCursor {
        let createdAt: String
        let id: String

        init(_ encoded: String) throws {
            let parts = encoded.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 2, UUID(uuidString: String(parts[1])) != nil else {
                throw FeedServiceError.invalidFeedCursor
            }
            createdAt = String(parts[0])
            id = String(parts[1])
        }

        init(record: SupabasePostRecord) {
            createdAt = record.createdAt
            id = record.id
        }

        var encoded: String { "\(createdAt)|\(id)" }
    }
}

private struct PostDeleteRecord: Decodable, Sendable {
    let mediaItems: [PostMedia]?
    let coverURL: String?
    let mediaURL: String?
    let fileURL: String?

    enum CodingKeys: String, CodingKey {
        case mediaItems = "media_items"
        case coverURL = "cover_url"
        case mediaURL = "media_url"
        case fileURL = "file_url"
    }
}

private struct PostEditRecord: Decodable, Sendable {
    let mediaItems: [PostMedia]?
    let coverURL: String?
    let mediaURL: String?
    let fileURL: String?
    let topics: [String]?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case mediaItems = "media_items"
        case coverURL = "cover_url"
        case mediaURL = "media_url"
        case fileURL = "file_url"
        case topics
        case updatedAt = "updated_at"
    }
}

private struct PostUpdatedRow: Decodable, Sendable {
    let id: String
}

private struct ProfessionalUpdatedRow: Decodable, Sendable {
    let id: String
}

private struct MemberProfileUpdatedRow: Decodable, Sendable {
    let id: String
}

private struct MemberProfileUpdate: Encodable, Sendable {
    let fullName: String
    let displayName: String
    let username: String?
    let photoURL: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case displayName = "display_name"
        case username
        case photoURL = "photo_url"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(username, forKey: .username)
        try container.encode(photoURL, forKey: .photoURL)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct BentoLinksUpdate: Encodable, Sendable {
    let customLinks: [BentoLink]
    enum CodingKeys: String, CodingKey { case customLinks = "custom_links" }
}

private struct PlatformProfileNameUpdate: Encodable, Sendable {
    let fullName: String
    enum CodingKeys: String, CodingKey { case fullName = "full_name" }
}

private struct PlatformProfileContentUpdate: Encodable, Sendable {
    let bio: String
    let coreValues: String
    enum CodingKeys: String, CodingKey { case bio; case coreValues = "core_values" }
}

private struct PlatformProfilePhotoUpdate: Encodable, Sendable {
    let photoURL: String?

    enum CodingKeys: String, CodingKey { case photoURL = "photo_url" }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(photoURL, forKey: .photoURL)
    }
}

private struct PostUpdate: Encodable, Sendable {
    let title: String
    let summary: String
    let body: String
    let format: String
    let topics: [String]
    let linkURL: String?
    let coverURL: String?
    let mediaURL: String?
    let fileURL: String?
    let mediaItems: [PostMedia]

    init(caption: String, format: String, topics: [String], mediaItems: [PostMedia], firstMediaPath: String?, externalURL: String?) {
        title = caption
        summary = caption
        body = caption
        self.format = format
        self.topics = topics
        linkURL = externalURL
        coverURL = firstMediaPath
        mediaURL = firstMediaPath
        fileURL = firstMediaPath
        self.mediaItems = mediaItems
    }

    enum CodingKeys: String, CodingKey {
        case title, summary, body, format, topics
        case linkURL = "link_url"
        case coverURL = "cover_url"
        case mediaURL = "media_url"
        case fileURL = "file_url"
        case mediaItems = "media_items"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(body, forKey: .body)
        try container.encode(format, forKey: .format)
        try container.encode(topics, forKey: .topics)
        try container.encode(linkURL, forKey: .linkURL)
        try container.encode(coverURL, forKey: .coverURL)
        try container.encode(mediaURL, forKey: .mediaURL)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(mediaItems, forKey: .mediaItems)
    }
}

private struct ToggleLikeParameters: Encodable, Sendable {
    let pPostID: UUID
    let pLiked: Bool
    enum CodingKeys: String, CodingKey { case pPostID = "p_post_id", pLiked = "p_liked" }
}

private struct RecordPostShareParameters: Encodable, Sendable {
    let pPostID: UUID
    enum CodingKeys: String, CodingKey { case pPostID = "p_post_id" }
}

private struct BetaPublisherCodeParameters: Encodable, Sendable {
    let pCode: String
    enum CodingKeys: String, CodingKey { case pCode = "p_code" }
}

private struct CreateReportParameters: Encodable, Sendable {
    let pPostID: UUID?
    let pCommentID: UUID?
    let pReason: String
    enum CodingKeys: String, CodingKey { case pPostID = "p_post_id", pCommentID = "p_comment_id", pReason = "p_reason" }
}

private struct PostLikeRow: Decodable, Sendable {
    let postID: String
    enum CodingKeys: String, CodingKey { case postID = "post_id" }
}

private struct SavedItemRow: Decodable, Sendable {
    let targetID: String
    enum CodingKeys: String, CodingKey { case targetID = "target_id" }
}

private struct BlockedUserRow: Decodable, Sendable {
    let blockedUserID: String
    enum CodingKeys: String, CodingKey { case blockedUserID = "blocked_user_id" }
}

private struct SavedItemInsert: Encodable, Sendable {
    let tenantID: UUID
    let viewerID: UUID
    let kind = "post"
    let targetID: UUID
    enum CodingKeys: String, CodingKey {
        case tenantID = "tenant_id", viewerID = "viewer_id", kind
        case targetID = "target_id"
    }
}

private struct BlockInsert: Encodable, Sendable {
    let tenantID: UUID
    let blockerID: UUID
    let blockedUserID: UUID
    enum CodingKeys: String, CodingKey {
        case tenantID = "tenant_id", blockerID = "blocker_id", blockedUserID = "blocked_user_id"
    }
}

private struct CommentInsert: Encodable, Sendable {
    let tenantID: UUID
    let postID: UUID
    let authorID: UUID
    let authorName: String
    let isProfessional: Bool
    let body: String
    enum CodingKeys: String, CodingKey {
        case tenantID = "tenant_id", postID = "post_id", authorID = "author_id"
        case authorName = "author_name", isProfessional = "is_professional", body
    }
}

private struct PostInsert: Encodable, Sendable {
    let tenantID: UUID
    let id: UUID
    let title: String
    let summary: String
    let body: String
    let format: String
    let topics: [String]
    let linkURL: String?
    let coverURL: String?
    let mediaURL: String?
    let mediaItems: [PostMedia]
    let professionalID: UUID?
    let authorUserID: UUID
    let authorName: String
    let authorCredentials: String
    let isMock = false
    let isTest = false
    init(tenantID: UUID, id: UUID, title: String, summary: String, body: String, topics: [String], mediaItems: [PostMedia], externalURL: String?, professionalID: UUID?, authorUserID: UUID, authorName: String, authorCredentials: String?) {
        self.tenantID = tenantID
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.topics = topics
        linkURL = externalURL
        self.mediaItems = mediaItems
        coverURL = mediaItems.first?.path
        mediaURL = mediaItems.first?.path
        format = mediaItems.count > 1 ? "carousel" : (mediaItems.first?.kind == .video ? "video" : "article")
        self.professionalID = professionalID
        self.authorUserID = authorUserID
        self.authorName = authorName
        self.authorCredentials = authorCredentials ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case tenantID = "tenant_id", id, title, summary, body, format, topics
        case linkURL = "link_url"
        case coverURL = "cover_url", mediaURL = "media_url", mediaItems = "media_items"
        case professionalID = "professional_id", authorUserID = "author_user_id"
        case authorName = "author_name", authorCredentials = "author_credentials"
        case isMock = "is_mock", isTest = "is_test"
    }
}

private struct ReportReviewUpdate: Encodable, Sendable {
    let status: String
    let reviewedBy: UUID
    let reviewedAt: String
    enum CodingKeys: String, CodingKey { case status, reviewedBy = "reviewed_by", reviewedAt = "reviewed_at" }
}
