import Foundation

struct SupabaseConfiguration: Equatable {
    let endpoint: URL?
    let publishableKey: String
    let tenantID: UUID?
    let mediaBucketID: String
    let authRedirectURL: URL?

    init(bundle: Bundle = .main) {
        let rawURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        endpoint = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines))
        publishableKey = (bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTenantID = bundle.object(forInfoDictionaryKey: "KATHAR_TENANT_ID") as? String ?? ""
        tenantID = UUID(uuidString: rawTenantID.trimmingCharacters(in: .whitespacesAndNewlines))
        mediaBucketID = (bundle.object(forInfoDictionaryKey: "KATHAR_MEDIA_BUCKET_ID") as? String ?? "kathar-media")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRedirectURL = (bundle.object(forInfoDictionaryKey: "SUPABASE_AUTH_REDIRECT_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        authRedirectURL = URL(string: rawRedirectURL)
    }

    var isConfigured: Bool {
        guard let endpoint, endpoint.scheme == "https", tenantID != nil,
              let authRedirectURL,
              authRedirectURL.scheme == "com.catharsia.ios",
              authRedirectURL.host == "login-callback",
              !publishableKey.isEmpty, !mediaBucketID.isEmpty else { return false }
        return true
    }
}
