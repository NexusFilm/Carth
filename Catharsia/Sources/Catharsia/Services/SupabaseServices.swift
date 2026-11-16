import Foundation
import Supabase

/// Shared Supabase client; the publishable key is public client configuration.
/// Tenant IDs and authenticated row access are still checked by Postgres RLS.
final class SupabaseServices: @unchecked Sendable {
    static let shared = SupabaseServices()

    let configuration: SupabaseConfiguration
    let client: SupabaseClient

    init(configuration: SupabaseConfiguration = SupabaseConfiguration()) {
        self.configuration = configuration
        let endpoint = configuration.endpoint ?? URL(string: "https://unconfigured.supabase.co")!
        let key = configuration.publishableKey.isEmpty ? "unconfigured" : configuration.publishableKey
        client = SupabaseClient(
            supabaseURL: endpoint,
            supabaseKey: key,
            options: .init(auth: .init(
                redirectToURL: configuration.authRedirectURL,
                emitLocalSessionAsInitialSession: true
            ))
        )
    }

    func publicMediaURL(for storedValue: String?, bucketID: String? = nil) -> URL? {
        guard let storedValue, !storedValue.isEmpty else { return nil }
        if let url = URL(string: storedValue), url.scheme != nil { return url }
        guard let endpoint = configuration.endpoint else { return nil }
        let encodedPath = storedValue.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "\(endpoint.absoluteString)/storage/v1/object/public/\(bucketID ?? configuration.mediaBucketID)/\(encodedPath)")
    }
}
