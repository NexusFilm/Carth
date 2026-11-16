import SwiftUI
import UIKit

struct BetaPublisherCodeSettingsView: View {
    @State private var service = SupabaseInteractionService()
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var hasActiveCode = false
    @State private var code: String?
    @State private var copied = false
    @State private var confirmReplace = false
    @State private var errorMessage: String?
    @State private var statusError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Admin tools")
                    Text("Beta publisher code")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("Give invited contributors one code to unlock posting on their own account.")
                        .font(.subheadline)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
                .padding(.horizontal, 2)

                ContentCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Contributor access", systemImage: "person.2.badge.key.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Text("Redeeming the code grants publishing access. It does not verify anyone as a therapist or show a clinician badge.")
                            .font(.subheadline)
                            .foregroundStyle(CatharsiaStyle.muted)

                        if isLoading {
                            ProgressView("Checking code")
                                .tint(CatharsiaStyle.violet)
                                .padding(.top, 3)
                        } else if let code {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SHARE THIS CODE")
                                    .font(.caption.weight(.bold))
                                    .tracking(1)
                                    .foregroundStyle(CatharsiaStyle.aqua)
                                Text(code)
                                    .font(.system(.title3, design: .monospaced).weight(.bold))
                                    .tracking(0.7)
                                    .foregroundStyle(CatharsiaStyle.ink)
                                    .textSelection(.enabled)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Button {
                                    UIPasteboard.general.string = code
                                    copied = true
                                } label: {
                                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                                        .font(.subheadline.weight(.bold))
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(CatharsiaStyle.violet)
                                .foregroundStyle(.white)
                                Text("This code is shown once. If you lose it, replace it with a new one.")
                                    .font(.footnote)
                                    .foregroundStyle(CatharsiaStyle.muted)
                            }
                        } else {
                            Label(
                                hasActiveCode ? "A shared code is active" : "No shared code yet",
                                systemImage: hasActiveCode ? "checkmark.circle.fill" : "key.horizontal"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(hasActiveCode ? CatharsiaStyle.aqua : CatharsiaStyle.muted)
                        }

                        if let statusError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(statusError)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(CatharsiaStyle.coral)
                                Button("Try again") { Task { await refreshCodeStatus() } }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(CatharsiaStyle.coral)
                        }

                        Button {
                            if hasActiveCode { confirmReplace = true }
                            else { Task { await generateCode() } }
                        } label: {
                            HStack {
                                Spacer()
                                if isWorking { ProgressView().tint(.white) }
                                else { Text(hasActiveCode ? "Replace shared code" : "Create shared code").fontWeight(.bold) }
                                Spacer()
                            }
                            .frame(minHeight: 48)
                            .foregroundStyle(.white)
                            .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || isWorking || statusError != nil)
                    }
                }

                if hasActiveCode && code == nil {
                    Text("Replacing the code stops new redemptions of the old code. Accounts that already redeemed it keep their access.")
                        .font(.footnote)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .padding(.horizontal, 3)
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Publisher code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .confirmationDialog("Replace the shared code?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace code", role: .destructive) { Task { await generateCode() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("People who already redeemed the old code keep publishing access. New contributors will need the replacement code.")
        }
        .task { await refreshCodeStatus() }
        .preferredColorScheme(.light)
    }

    @MainActor
    private func refreshCodeStatus() async {
        isLoading = true
        statusError = nil
        defer { isLoading = false }
        do {
            hasActiveCode = try await service.betaPublisherCodeIsActive()
        } catch {
            statusError = error.localizedDescription
        }
    }

    @MainActor
    private func generateCode() async {
        isWorking = true
        errorMessage = nil
        copied = false
        defer { isWorking = false }
        do {
            code = try await service.rotateBetaPublisherCode()
            hasActiveCode = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
