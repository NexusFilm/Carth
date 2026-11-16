import Foundation

struct TherapistApplication: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let applicantUserID: String?
    let fullName: String
    let email: String
    let credentials: String?
    let licenseNumber: String
    let licenseState: String
    let specialties: [String]
    let status: String
    let verificationStatus: String
    let verificationNotes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, credentials, specialties, status
        case applicantUserID = "applicant_user_id"
        case fullName = "full_name"
        case licenseNumber = "license_number"
        case licenseState = "license_state"
        case verificationStatus = "verification_status"
        case verificationNotes = "verification_notes"
        case createdAt = "created_at"
    }

    var submittedLabel: String {
        guard let date = CatharsiaISO8601.parse(createdAt) else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct TherapistApplicationInsert: Encodable, Sendable {
    let tenantID: UUID
    let applicantUserID: UUID
    let fullName: String
    let email: String
    let credentials: String
    let licenseNumber: String
    let licenseState: String
    let specialties: [String]

    enum CodingKeys: String, CodingKey {
        case email, credentials, specialties
        case tenantID = "tenant_id"
        case applicantUserID = "applicant_user_id"
        case fullName = "full_name"
        case licenseNumber = "license_number"
        case licenseState = "license_state"
    }
}

struct ReviewTherapistApplicationParameters: Encodable, Sendable {
    let pApplicationID: UUID
    let pDecision: String
    let pVerificationSource: String?
    let pNotes: String?

    enum CodingKeys: String, CodingKey {
        case pApplicationID = "p_application_id"
        case pDecision = "p_decision"
        case pVerificationSource = "p_verification_source"
        case pNotes = "p_notes"
    }
}
