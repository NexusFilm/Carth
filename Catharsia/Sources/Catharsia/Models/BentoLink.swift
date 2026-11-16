import Foundation

enum BentoLinkKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case event
    case booking
    case resource
    case community
    case social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .event: "Event"
        case .booking: "Appointments"
        case .resource: "Resource"
        case .community: "Group or community"
        case .social: "Social"
        }
    }

    var symbol: String {
        switch self {
        case .event: "calendar"
        case .booking: "calendar.badge.clock"
        case .resource: "book.closed"
        case .community: "person.3"
        case .social: "person.2"
        }
    }
}

struct BentoLink: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String?
    var url: String
    var kind: BentoLinkKind
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id, title, detail, url, kind, position
    }

    var destinationURL: URL? {
        ExternalURLPolicy.url(from: url)
    }

    var host: String? {
        destinationURL?.host?.replacingOccurrences(of: "www.", with: "")
    }
}

struct BentoProfessionalRecord: Decodable, Sendable {
    let id: String
    let fullName: String
    let credentials: String
    let isPlatform: Bool?
    let photoURL: String?
    let verified: Bool
    let verificationStatus: String
    let verificationTier: String
    let bio: String?
    let coreValues: String?
    let specialties: [String]
    let yearsExperience: Int?
    let languages: [String]
    let insuranceAccepted: [String]
    let telehealth: Bool
    let officeLocation: String?
    let website: String?
    let bookingLink: String?
    let customLinks: [BentoLink]

    enum CodingKeys: String, CodingKey {
        case id, credentials, verified, bio, specialties, website, languages, telehealth
        case coreValues = "core_values"
        case isPlatform = "is_platform"
        case fullName = "full_name"
        case photoURL = "photo_url"
        case yearsExperience = "years_experience"
        case insuranceAccepted = "insurance_accepted"
        case verificationStatus = "verification_status"
        case verificationTier = "verification_tier"
        case officeLocation = "office_location"
        case bookingLink = "booking_link"
        case customLinks = "custom_links"
    }

    var isTrustedPublisher: Bool {
        verified && verificationStatus == "verified"
            && ["verified_clinician", "verified_professional"].contains(verificationTier)
    }

    var isOfficialProfile: Bool { isPlatform == true }

    var description: String? {
        bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var publicLinks: [BentoLink] {
        var links = customLinks.filter { $0.destinationURL != nil }
        var existingURLs = Set(links.compactMap { $0.destinationURL?.absoluteString })

        if let website, let url = ExternalURLPolicy.url(from: website), !existingURLs.contains(url.absoluteString) {
            links.append(BentoLink(id: "website", title: "Visit my website", detail: nil, url: url.absoluteString, kind: .resource, position: links.count))
            existingURLs.insert(url.absoluteString)
        }
        if let bookingLink, let url = ExternalURLPolicy.url(from: bookingLink), !existingURLs.contains(url.absoluteString) {
            links.append(BentoLink(id: "appointments", title: "Book an appointment", detail: nil, url: url.absoluteString, kind: .booking, position: links.count))
            existingURLs.insert(url.absoluteString)
        }
        return links.sorted { $0.position < $1.position }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
