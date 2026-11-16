import SwiftUI

struct TherapistReviewView: View {
    @Environment(SessionStore.self) private var session
    private let service = SupabaseInteractionService()

    @State private var applications: [TherapistApplication] = []
    @State private var sourceURLs: [String: String] = [:]
    @State private var notes: [String: String] = [:]
    @State private var selectedApplication: TherapistApplication?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Admin review")
                    Text("Therapist requests")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("Check each active license on the official licensing registry before approving. The source URL is saved with the verification record.")
                        .font(.subheadline)
                        .foregroundStyle(CatharsiaStyle.muted)
                }

                if !session.isAdmin {
                    ContentCard {
                        Label("Administrator access required", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                    }
                } else if isLoading {
                    ContentCard {
                        HStack(spacing: 10) {
                            ProgressView().tint(CatharsiaStyle.violet)
                            Text("Loading requests")
                                .font(.subheadline)
                                .foregroundStyle(CatharsiaStyle.muted)
                        }
                    }
                } else if let errorMessage {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Couldn’t load requests")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(CatharsiaStyle.ink)
                            Text(errorMessage).font(.footnote).foregroundStyle(CatharsiaStyle.muted)
                            Button("Try again") { Task { await loadApplications() } }
                                .buttonStyle(.borderedProminent)
                                .tint(CatharsiaStyle.violet)
                        }
                    }
                } else if applications.isEmpty {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("No open requests")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(CatharsiaStyle.ink)
                            Text("New therapist applications will appear here after submission.")
                                .font(.subheadline)
                                .foregroundStyle(CatharsiaStyle.muted)
                        }
                    }
                } else {
                    ForEach(applications) { application in
                        applicationCard(application)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 24)
            .frame(maxWidth: 700, alignment: .leading)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Therapist requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadApplications() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh requests")
                .disabled(isLoading || isWorking)
            }
        }
        .task { await loadApplications() }
        .confirmationDialog("Review therapist request", isPresented: Binding(
            get: { selectedApplication != nil },
            set: { if !$0 { selectedApplication = nil } }
        ), titleVisibility: .visible) {
            if let application = selectedApplication {
                Button("Verify and enable posting") {
                    Task { await review(application, decision: "verified") }
                }
                Button("Reject request", role: .destructive) {
                    Task { await review(application, decision: "rejected") }
                }
            }
            Button("Cancel", role: .cancel) { selectedApplication = nil }
        } message: {
            if let application = selectedApplication {
                Text("Review the official registry for \(application.fullName) (\(application.credentials ?? "licensed clinician"), \(application.licenseState) license) before approving.")
            }
        }
        .alert("Therapist requests", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func applicationCard(_ application: TherapistApplication) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(application.fullName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Text(application.email)
                            .font(.caption)
                            .foregroundStyle(CatharsiaStyle.muted)
                    }
                    Spacer(minLength: 0)
                    Text(application.status.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(CatharsiaStyle.violet)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(CatharsiaStyle.violet.opacity(0.1), in: Capsule())
                }

                Divider()
                LabeledContent("Credential", value: application.credentials ?? "Not supplied")
                LabeledContent("License", value: "\(application.licenseState) · \(application.licenseNumber)")
                if !application.specialties.isEmpty {
                    LabeledContent("Specialties", value: application.specialties.joined(separator: ", "))
                }
                if !application.submittedLabel.isEmpty {
                    LabeledContent("Submitted", value: application.submittedLabel)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Official registry URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.muted)
                    TextField("https://licensing-board.gov/lookup", text: binding(for: application.id, in: $sourceURLs))
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Review note (required when rejecting)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.muted)
                    TextField("Add a brief review note", text: binding(for: application.id, in: $notes), axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(2...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    selectedApplication = application
                } label: {
                    Label("Review request", systemImage: "checkmark.shield")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.canvas)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
    }

    private func binding(for key: String, in values: Binding<[String: String]>) -> Binding<String> {
        Binding(
            get: { values.wrappedValue[key, default: ""] },
            set: { values.wrappedValue[key] = $0 }
        )
    }

    private func loadApplications() async {
        guard session.isAdmin else { isLoading = false; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            applications = try await service.pendingTherapistApplications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func review(_ application: TherapistApplication, decision: String) async {
        guard session.isAdmin else { return }
        let source = sourceURLs[application.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = notes[application.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if decision == "verified", source?.lowercased().hasPrefix("https://") != true {
            selectedApplication = nil
            message = "Add the official HTTPS licensing registry URL before approving."
            return
        }
        if decision == "rejected", note?.isEmpty != false {
            selectedApplication = nil
            message = "Add a short note explaining what the applicant needs to correct before rejecting."
            return
        }

        selectedApplication = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.reviewTherapistApplication(
                id: application.id,
                decision: decision,
                verificationSource: decision == "verified" ? source : nil,
                notes: note
            )
            await loadApplications()
            message = decision == "verified"
                ? "License verification was recorded. This therapist can now publish."
                : "The request was declined and the applicant’s note was saved."
        } catch {
            message = error.localizedDescription
        }
    }
}
