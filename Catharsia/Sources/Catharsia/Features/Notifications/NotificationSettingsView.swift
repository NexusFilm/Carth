import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @State private var push = PushNotificationService.shared
    @State private var preferences = PushPreferenceSettings()
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var preferencesError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                deliverySection
                preferencesSection
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Push alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .task { await loadPreferences() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await push.refreshAuthorizationStatus() }
        }
        .tint(CatharsiaStyle.violet)
        .preferredColorScheme(.light)
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAuthorized ? "bell.badge.fill" : "bell.badge")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .frame(width: 44, height: 44)
                    .background(CatharsiaStyle.violet.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(deliveryTitle)
                        .font(.headline)
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text(deliveryDetail)
                        .font(.body)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isAuthorized && push.registrationMessage == nil {
                    Image(systemName: push.bannersEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(push.bannersEnabled ? CatharsiaStyle.aqua : CatharsiaStyle.butter)
                        .accessibilityLabel(push.bannersEnabled ? "Push banners enabled" : "Push banners disabled in iPhone Settings")
                }
            }

            if isAuthorized || push.authorizationStatus == .denied {
                Rectangle()
                    .fill(CatharsiaStyle.ink.opacity(0.08))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }

            if isAuthorized {
                Button {
                    if push.registrationMessage != nil {
                        Task { await push.refreshAuthorizationStatus() }
                    } else {
                        Task { await push.sendTestAlert() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if push.isSendingTestAlert {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: push.registrationMessage == nil ? "paperplane" : "arrow.clockwise")
                                .accessibilityHidden(true)
                        }
                        Text(testActionTitle)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(push.isSendingTestAlert)
                .accessibilityHint(push.registrationMessage == nil
                    ? "Sends a test notification to this device."
                    : "Refreshes this device’s push connection.")
                if !push.bannersEnabled {
                    Button("Open iPhone Settings", action: push.openSystemSettings)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .accessibilityHint("Turn on Catharsia banners in Notifications settings.")
                }
            } else if push.authorizationStatus == .denied {
                Button("Open iPhone Settings", action: push.openSystemSettings)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .accessibilityHint("Turn on notifications for Catharsia in iPhone Settings.")
            } else {
                Button {
                    Task { await push.requestAuthorization() }
                } label: {
                    Text("Turn on push alerts")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Allows Catharsia to send the alert categories you choose below.")
            }

            if let message = push.testAlertMessage {
                Label(message, systemImage: push.testAlertFailed ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(push.testAlertFailed ? CatharsiaStyle.coral : CatharsiaStyle.aqua)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose what you receive")
                    .font(.headline)
                    .foregroundStyle(CatharsiaStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("These control push alerts only. In-app activity stays here until you delete it.")
                    .font(.body)
                    .foregroundStyle(CatharsiaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if hasLoaded {
                    preferenceToggle(
                        title: "Likes and comments",
                        detail: "Activity on your posts",
                        isOn: autoPushBinding
                    )
                    Rectangle().fill(CatharsiaStyle.ink.opacity(0.08)).frame(height: 1).accessibilityHidden(true)
                    preferenceToggle(
                        title: "Catharsia announcements",
                        detail: "Official updates from Catharsia",
                        isOn: announcementPushBinding
                    )
                } else if isLoading {
                    HStack(spacing: 10) {
                        ProgressView().tint(CatharsiaStyle.violet)
                        Text("Loading preferences")
                            .font(.body)
                            .foregroundStyle(CatharsiaStyle.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(.horizontal, 14)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading push preferences")
                } else {
                    Button("Try again") { Task { await loadPreferences() } }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 14)
                }
            }
            .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.06), lineWidth: 1))

            if let preferencesError {
                Text(preferencesError)
                    .font(.body)
                    .foregroundStyle(CatharsiaStyle.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var isAuthorized: Bool {
        push.authorizationStatus == .authorized || push.authorizationStatus == .provisional
    }

    private var deliveryTitle: String {
        if push.authorizationStatus == .denied { return "Push alerts are off" }
        if isAuthorized, push.registrationMessage != nil { return "Connection needs attention" }
        if isAuthorized && !push.bannersEnabled { return "iPhone banners are off" }
        if isAuthorized { return "Push alerts are on" }
        return "Push alerts are off"
    }

    private var deliveryDetail: String {
        if let message = push.registrationMessage { return message }
        if isAuthorized && !push.bannersEnabled {
            return "Push can reach this iPhone, but iOS isn’t set to show banners. Turn on Banners for Catharsia in iPhone Settings."
        }
        if isAuthorized { return "This iPhone can show banners for the alert types you enable below." }
        if push.authorizationStatus == .denied { return "Turn them on in iPhone Settings to receive alerts." }
        return "Choose alert types below, then allow notifications from iPhone."
    }

    private var testActionTitle: String {
        if push.isSendingTestAlert { return "Sending test alert" }
        return push.registrationMessage == nil ? "Send a test alert" : "Retry connection"
    }

    private var autoPushBinding: Binding<Bool> {
        Binding(get: { preferences.autoPushEnabled }, set: { save(autoPushEnabled: $0) })
    }

    private var announcementPushBinding: Binding<Bool> {
        Binding(get: { preferences.manualPushEnabled }, set: { save(manualPushEnabled: $0) })
    }

    private func preferenceToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(CatharsiaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(CatharsiaStyle.aqua)
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .disabled(!hasLoaded || isSaving)
    }

    private func loadPreferences() async {
        isLoading = true
        defer { isLoading = false }
        do {
            await push.refreshAuthorizationStatus()
            preferences = try await SupabaseNotificationService.shared.loadPushPreferences() ?? PushPreferenceSettings()
            preferencesError = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                hasLoaded = false
                preferencesError = "Your push preferences couldn’t load. Try again."
            }
        }
    }

    private func save(autoPushEnabled: Bool? = nil, manualPushEnabled: Bool? = nil) {
        guard hasLoaded, !isSaving else { return }
        let previous = preferences
        if let autoPushEnabled { preferences.autoPushEnabled = autoPushEnabled }
        if let manualPushEnabled { preferences.manualPushEnabled = manualPushEnabled }
        let updated = preferences
        preferencesError = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await SupabaseNotificationService.shared.savePushPreferences(updated)
            } catch {
                preferences = previous
                preferencesError = "Couldn’t save this preference. Try again."
            }
        }
    }
}
