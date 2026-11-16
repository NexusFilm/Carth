import SwiftUI

struct TherapistAccessView: View {
    @Environment(SessionStore.self) private var session
    private let service = SupabaseInteractionService()

    @State private var application: TherapistApplication?
    @State private var fullName = ""
    @State private var credentials = ""
    @State private var licenseNumber = ""
    @State private var licenseState = "US-TX"
    @State private var specialties = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var submitAgain = false
    @State private var message: String?
    @State private var loadError: String?
    @State private var showSignIn = false
    @State private var publisherCode = ""
    @State private var publisherCodeMessage: String?
    @State private var isRedeemingCode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if session.isSignedIn && !session.canPublish {
                    publisherCodeCard
                }
                if !session.isSignedIn {
                    signInCard
                } else if session.isBetaPublisher {
                    betaPublisherStatus
                } else if isLoading {
                    ContentCard {
                        HStack(spacing: 12) {
                            ProgressView().tint(CatharsiaStyle.violet)
                            Text("Checking your request")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(CatharsiaStyle.muted)
                        }
                    }
                } else if let loadError {
                    errorCard(loadError)
                } else if let application, application.status != "rejected" || !submitAgain {
                    requestStatus(application)
                } else {
                    applicationForm
                }
            }
            .padding(18)
            .padding(.bottom, 24)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Therapist access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .toolbar {
            if session.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh therapist request status")
                    .disabled(isLoading || isSubmitting)
                }
            }
        }
        .sheet(isPresented: $showSignIn) { AccountAccessView().environment(session) }
        .alert("Therapist access", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .task(id: "\(session.isSignedIn)-\(session.isBetaPublisher)") {
            if session.isSignedIn && !session.isBetaPublisher { await loadApplication() }
        }
    }

    private var signInCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Therapist publishing", systemImage: "checkmark.seal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("Explore stays open to everyone. Sign in to request therapist publishing access.")
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
                Button("Sign in or create account") { showSignIn = true }
                    .buttonStyle(.borderedProminent)
                    .tint(CatharsiaStyle.violet)
                    .foregroundStyle(CatharsiaStyle.canvas)
            }
        }
    }

    private var publisherCodeCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 11) {
                Label("Invited to publish?", systemImage: "key.horizontal.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("Enter the shared beta code. It unlocks contributor posting for this account; it does not verify therapist credentials.")
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
                HStack(spacing: 10) {
                    TextField("Publisher code", text: $publisherCode)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .accessibilityLabel("Beta publisher code")
                        .padding(.horizontal, 13)
                        .frame(minHeight: 48)
                        .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Button {
                        Task { await redeemPublisherCode() }
                    } label: {
                        if isRedeemingCode { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.right").font(.headline.weight(.bold)) }
                    }
                    .frame(width: 48, height: 48)
                    .foregroundStyle(.white)
                    .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Redeem publisher code")
                    .disabled(isRedeemingCode || publisherCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.emailIsVerified)
                    .opacity(session.emailIsVerified ? 1 : 0.55)
                }
                if !session.emailIsVerified {
                    Text("Confirm your email before redeeming a code.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CatharsiaStyle.butter)
                }
                if let publisherCodeMessage {
                    Text(publisherCodeMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CatharsiaStyle.coral)
                }
            }
        }
    }

    private var betaPublisherStatus: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Publisher access is active", systemImage: "checkmark.seal.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.aqua)
                Text("This account can publish as a Catharsia beta contributor. Therapist verification remains a separate process.")
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
                LabeledContent("Account", value: session.userEmail)
                    .font(.footnote.weight(.medium))
            }
        }
    }

    private var applicationForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Licensed clinicians")
                Text("Request posting access")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text("We’ll check your active license with the professional regulator for your jurisdiction before enabling posts.")
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 15) {
                    labeledField("Full name", placeholder: "Name as shown on license", text: $fullName)
                        .textContentType(.name)
                    labeledField("Professional license type", placeholder: "LPC, LCSW, LMFT, psychologist", text: $credentials)
                        .textInputAutocapitalization(.characters)
                    labeledField("License number", placeholder: "Your active license number", text: $licenseNumber)
                        .textInputAutocapitalization(.never)
                    labeledField("License jurisdiction", placeholder: "US-TX or GB-ENG", text: $licenseState)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Text("Enter the country and region code used by your licensing board, such as US-TX or GB-ENG.")
                        .font(.footnote)
                        .foregroundStyle(CatharsiaStyle.muted)
                    labeledField("Specialties (optional)", placeholder: "Separate with commas", text: $specialties)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("License information stays private", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("Your license number is available to you and Catharsia administrators for review. We do not ask for your sign-in password or identity documents. It won’t appear on your public therapist profile. Posting stays disabled until an administrator records a successful regulator check.")
                        .font(.footnote)
                        .lineSpacing(3)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
            }

            if !session.emailIsVerified {
                ContentCard {
                    Label("Confirm your email before sending a request", systemImage: "envelope.badge")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.muted)
                }
            }

            Button {
                Task { await submitApplication() }
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting { ProgressView().tint(CatharsiaStyle.canvas) }
                    else { Text("Send access request").fontWeight(.bold) }
                    Spacer()
                }
                .frame(height: 50)
                .foregroundStyle(CatharsiaStyle.canvas)
                .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || !formIsValid || !session.emailIsVerified)
            .opacity(formIsValid && session.emailIsVerified ? 1 : 0.55)
        }
    }

    private func requestStatus(_ application: TherapistApplication) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: application.status == "verified" ? "checkmark.seal.fill" : "clock.badge")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(application.status == "verified" ? CatharsiaStyle.aqua : CatharsiaStyle.violet)
                    Text(statusTitle(application.status))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.ink)
                }
                Text(statusDescription(application.status))
                    .font(.subheadline)
                    .foregroundStyle(CatharsiaStyle.muted)
                Divider()
                LabeledContent("Credential", value: application.credentials ?? "Licensed clinician")
                LabeledContent("Jurisdiction", value: application.licenseState)
                if !application.submittedLabel.isEmpty {
                    LabeledContent("Requested", value: application.submittedLabel)
                }
                if application.status == "verified" {
                    Button {
                        Task { try? await session.refreshIdentity() }
                    } label: {
                        Label("Refresh publishing access", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 3)
                } else if application.status == "rejected" {
                    if let notes = application.verificationNotes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(CatharsiaStyle.muted)
                    }
                    Button("Update and resubmit") { submitAgain = true }
                        .buttonStyle(.borderedProminent)
                        .tint(CatharsiaStyle.violet)
                        .foregroundStyle(CatharsiaStyle.canvas)
                } else {
                    Button("Check request status") {
                        Task { await refreshStatus() }
                    }
                    .buttonStyle(.bordered)
                    .tint(CatharsiaStyle.violet)
                }
            }
        }
    }

    private func errorCard(_ error: String) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn’t load your request")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text(error).font(.subheadline).foregroundStyle(CatharsiaStyle.muted)
                Button("Try again") { Task { await loadApplication() } }
                    .buttonStyle(.borderedProminent)
                    .tint(CatharsiaStyle.violet)
                    .foregroundStyle(CatharsiaStyle.canvas)
            }
        }
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.muted)
            TextField(placeholder, text: text)
                .font(.body)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var formIsValid: Bool {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && credentials.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && !licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && licenseState.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                .range(of: #"^[A-Z]{2}(-[A-Z0-9]{1,8})?$"#, options: .regularExpression) != nil
    }

    private func loadApplication() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            application = try await service.myTherapistApplication()
            if fullName.isEmpty { fullName = session.displayName }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshStatus() async {
        await loadApplication()
        try? await session.refreshIdentity()
    }

    private func submitApplication() async {
        guard session.isSignedIn, formIsValid else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let topics = specialties.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        do {
            try await service.submitTherapistApplication(
                fullName: fullName,
                credentials: credentials,
                licenseNumber: licenseNumber,
                licenseState: licenseState,
                specialties: Array(Set(topics)).sorted()
            )
            submitAgain = false
            await loadApplication()
            message = "Your request is in. Explore stays public while Catharsia verifies the license."
        } catch {
            message = error.localizedDescription
        }
    }

    private func redeemPublisherCode() async {
        guard session.isSignedIn, session.emailIsVerified else { return }
        isRedeemingCode = true
        publisherCodeMessage = nil
        defer { isRedeemingCode = false }
        do {
            let redeemed = try await service.redeemBetaPublisherCode(publisherCode)
            guard redeemed else {
                publisherCodeMessage = "That code couldn’t be used. Check it and try again."
                return
            }
            try await session.refreshIdentity()
            if !session.isBetaPublisher {
                publisherCodeMessage = "The code was accepted. Refresh your account to load publishing access."
                return
            }
            publisherCode = ""
        } catch {
            publisherCodeMessage = error.localizedDescription
        }
    }

    private func statusTitle(_ status: String) -> String {
        switch status {
        case "verified": "Access approved"
        case "rejected": "More information needed"
        case "in_review": "License under review"
        default: "Request received"
        }
    }

    private func statusDescription(_ status: String) -> String {
        switch status {
        case "verified": "Your active license was verified. Sign out and back in, or refresh access, to start posting."
        case "rejected": "Your request wasn’t approved yet. Review the administrator’s note, update the details, and resubmit."
        case "in_review": "A Catharsia administrator is checking the license against the official registry. Posting remains disabled during review."
        default: "A Catharsia administrator will check the license against the official registry. Posting remains disabled during review."
        }
    }
}
