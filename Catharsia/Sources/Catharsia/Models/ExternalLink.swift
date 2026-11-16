import Foundation

struct PostExternalLink: Hashable, Sendable {
    let url: URL

    init?(rawURL: String) {
        guard let url = ExternalURLPolicy.url(from: rawURL) else { return nil }
        self.url = url
    }

    var displayHost: String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? "External website"
    }
}

enum ExternalURLPolicy {
    static func url(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 2_048,
              !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }

        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              host.contains("."),
              components.user == nil,
              components.password == nil else { return nil }
        return components.url
    }
}
