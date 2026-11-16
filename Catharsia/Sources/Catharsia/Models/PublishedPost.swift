import Foundation

struct PublishedPost: Identifiable, Hashable {
    let id: String
    let caption: String
    let body: String
    let topicID: String
    let professionalID: String?
    let authorUserID: String
    let authorName: String
    let authorLabel: String
    let authorVerified: Bool
    let mediaPath: String?
    let mediaItems: [PostMedia]
    let externalLink: PostExternalLink?
    let publishedAt: Date?
    let format: String
    var likeCount: Int
    var commentCount: Int
    var saveCount: Int
    var shareCount: Int

    init(record: SupabasePostRecord, verifiedProfessionalsByID: [String: SupabaseProfessionalRecord]) {
        id = record.id
        let title = record.title?.trimmedNonempty
        let summary = record.summary?.trimmedNonempty
        let body = record.body?.trimmedNonempty
        caption = title ?? summary ?? body ?? ""
        self.body = body ?? summary ?? title ?? ""
        topicID = record.topics?.first ?? ""
        professionalID = record.professionalID
        authorUserID = record.authorUserID ?? ""
        let professional = record.professionalID.flatMap { verifiedProfessionalsByID[$0] }
        let isOfficialProfile = professional?.isOfficialProfile == true
        authorName = isOfficialProfile
            ? professional?.fullName?.trimmedNonempty ?? "Catharsia"
            : record.authorName?.trimmedNonempty ?? "Catharsia therapist"
        authorLabel = isOfficialProfile
            ? "Official profile"
            : record.authorCredentials?.trimmedNonempty
                ?? (record.professionalID == nil ? "Catharsia" : "Verified therapist")
        authorVerified = professional?.isTrustedPublisher ?? false
        let legacyMediaPath = record.coverURL?.trimmedNonempty ?? record.mediaURL?.trimmedNonempty ?? record.fileURL?.trimmedNonempty
        if let mediaItems = record.mediaItems, !mediaItems.isEmpty {
            self.mediaItems = mediaItems
            mediaPath = mediaItems.first?.path ?? legacyMediaPath
        } else if let legacyMediaPath {
            let isVideo = ["mp4", "mov", "m4v"].contains(URL(fileURLWithPath: legacyMediaPath).pathExtension.lowercased())
            let item = PostMedia(
                kind: isVideo ? .video : .photo,
                path: legacyMediaPath,
                mimeType: isVideo ? "video/mp4" : "image/jpeg",
                byteSize: 0,
                durationSeconds: nil
            )
            self.mediaItems = [item]
            mediaPath = legacyMediaPath
        } else {
            self.mediaItems = []
            mediaPath = nil
        }
        format = record.format ?? "article"
        likeCount = max(0, record.likes ?? 0)
        commentCount = max(0, record.commentCount ?? 0)
        saveCount = max(0, record.saves ?? 0)
        shareCount = max(0, record.shareCount ?? 0)
        externalLink = record.linkURL.flatMap { PostExternalLink(rawURL: $0) }
        publishedAt = CatharsiaISO8601.parse(record.createdAt)
    }

    var topicName: String {
        topicID.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var publishedLabel: String {
        guard let publishedAt else { return "" }
        return publishedAt.formatted(.relative(presentation: .named))
    }
}

struct PostEngagementCounts: Decodable, Sendable {
    let likes: Int
    let saves: Int
    let comments: Int
    let shares: Int

    enum CodingKeys: String, CodingKey {
        case likes, saves
        case comments = "comment_count"
        case shares = "share_count"
    }
}

struct SupabasePostRecord: Decodable, Sendable {
    let id: String
    let title: String?
    let summary: String?
    let body: String?
    let format: String?
    let topics: [String]?
    let linkURL: String?
    let coverURL: String?
    let mediaURL: String?
    let fileURL: String?
    let professionalID: String?
    let authorUserID: String?
    let authorName: String?
    let authorCredentials: String?
    let createdAt: String
    let isMock: Bool?
    let isTest: Bool?
    let mediaItems: [PostMedia]?
    let likes: Int?
    let saves: Int?
    let commentCount: Int?
    let shareCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, body, format, topics
        case linkURL = "link_url"
        case coverURL = "cover_url"
        case mediaURL = "media_url"
        case fileURL = "file_url"
        case professionalID = "professional_id"
        case authorUserID = "author_user_id"
        case authorName = "author_name"
        case authorCredentials = "author_credentials"
        case createdAt = "created_at"
        case isMock = "is_mock"
        case isTest = "is_test"
        case mediaItems = "media_items"
        case likes, saves
        case commentCount = "comment_count"
        case shareCount = "share_count"
    }
}

enum PostMediaKind: String, Codable, Hashable, Sendable {
    case photo
    case video
}

enum CatharsiaMediaLimits {
    static let maximumVideoDuration: Double = 60
    static let maximumVideoUploadBytes = 48_000_000
    static let maximumCameraSourceBytes = 250_000_000
}

struct PostMedia: Codable, Hashable, Sendable {
    let kind: PostMediaKind
    let path: String
    let mimeType: String
    let byteSize: Int
    let durationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case kind, path
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case durationSeconds = "duration_seconds"
    }
}

struct PostMediaUpload: Sendable {
    let kind: PostMediaKind
    let fileURL: URL
    let mimeType: String
    let fileExtension: String
    let durationSeconds: Double?
}

struct SupabaseProfessionalRecord: Decodable, Sendable {
    let id: String
    let fullName: String?
    let credentials: String?
    let isPlatform: Bool?
    let verified: Bool
    let verificationStatus: String?
    let verificationTier: String?

    enum CodingKeys: String, CodingKey {
        case id, credentials, verified
        case fullName = "full_name"
        case isPlatform = "is_platform"
        case verificationStatus = "verification_status"
        case verificationTier = "verification_tier"
    }

    var isTrustedPublisher: Bool {
        verified && verificationStatus == "verified"
            && ["verified_clinician", "verified_professional"].contains(verificationTier ?? "")
    }

    var isOfficialProfile: Bool { isPlatform == true }
}

struct Comment: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let authorUserID: String
    var authorName: String
    var authorPhotoURL: String?
    var authorUsername: String?
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorUserID = "author_id"
        case authorName = "author_name"
        case authorPhotoURL = "author_photo_url"
        case authorUsername = "author_username"
        case createdAt = "created_at"
    }
}

struct BlockedUser: Identifiable, Hashable, Sendable {
    let userID: String
    let name: String
    var id: String { userID }
}

struct SupabaseProfileName: Decodable, Sendable {
    let id: String
    let fullName: String?
    let displayName: String?
    let photoURL: String?
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case displayName = "display_name"
        case photoURL = "photo_url"
        case username
    }
}

struct CatharsiaMemberProfile: Decodable, Sendable {
    let fullName: String?
    let displayName: String?
    let username: String?
    let photoURL: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case displayName = "display_name"
        case username
        case photoURL = "photo_url"
    }
}

struct ModerationReport: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let postId: String?
    let commentId: String?
    let reason: String
    let createdAt: String
    let authorName: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case id, reason
        case postId = "post_id"
        case commentId = "comment_id"
        case createdAt = "created_at"
        case authorName = "author_name"
        case content = "content_excerpt"
    }
}

struct InteractionState: Decodable, Sendable {
    let likedPostIDs: [String]
    let savedPostIDs: [String]

    static let empty = InteractionState(likedPostIDs: [], savedPostIDs: [])
}

struct PublisherCapabilities: Decodable, Sendable {
    let canPublish: Bool
    let isAdmin: Bool
    let isTherapist: Bool
    let isBetaPublisher: Bool
    let needsAdminVerification: Bool

    static let none = PublisherCapabilities(canPublish: false, isAdmin: false, isTherapist: false, isBetaPublisher: false, needsAdminVerification: false)
}

enum FeedServiceError: LocalizedError {
    case notConfigured
    case invalidFeedCursor
    case actionFailed
    case signInRequired
    case publishingNotAllowed
    case verifiedEmailRequired
    case applicationFieldsRequired
    case mediaSelectionInvalid
    case invalidExternalURL
    case invalidBentoLink
    case bentoLinksLimitExceeded
    case invalidProfileName
    case invalidProfileImage
    case invalidUsername
    case usernameAlreadyTaken
    case mediaFileTooLarge
    case videoTooLong
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Catharsia couldn’t connect to its Supabase tenant. Check the local app configuration."
        case .invalidFeedCursor:
            "Pull down to refresh Explore, then try again."
        case .actionFailed:
            "That didn’t go through. Try again in a moment."
        case .signInRequired:
            "Sign in to continue."
        case .publishingNotAllowed:
            "Posting is available to approved therapists and Catharsia’s official account."
        case .verifiedEmailRequired:
            "Confirm your email address before requesting therapist access."
        case .applicationFieldsRequired:
            "Enter your name, professional credential, license number, and two-letter license state."
        case .mediaSelectionInvalid:
            "Write a caption, add photos or video, or include an external link."
        case .invalidExternalURL:
            "Enter a valid secure https:// link."
        case .invalidBentoLink:
            "Add a title and a valid secure https:// link."
        case .bentoLinksLimitExceeded:
            "Profiles can have up to six links."
        case .invalidProfileName:
            "Enter a profile name with 1 to 60 characters."
        case .invalidProfileImage:
            "Choose a valid photo or logo image."
        case .invalidUsername:
            "Use 3 to 24 letters, numbers, or underscores for your username."
        case .usernameAlreadyTaken:
            "That username is already in use. Try another one."
        case .mediaFileTooLarge:
            "Each photo or video must be smaller than 48 MB. Try a shorter or more compressed clip."
        case .videoTooLong:
            "Videos can be up to 60 seconds. Trim this clip in Photos and try again."
        case .unsupportedMedia:
            "Use a photo or MP4 video so it can be shared safely."
        }
    }
}

struct FeedPage {
    let posts: [PublishedPost]
    let nextCursor: String?
}

extension String {
    fileprivate var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum CatharsiaISO8601 {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
