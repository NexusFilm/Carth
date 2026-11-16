import SwiftUI
import Supabase

struct AdminAnnouncementView: View {
    private enum FocusedField: Hashable {
        case title
        case message
    }

    @Environment(SessionStore.self) private var session
    @FocusState private var focusedField: FocusedField?
    @State private var title = ""
    @State private var message = ""
    @State private var destination: CatharsiaAnnouncementDestination?
    @State private var isConfirming = false
    @State private var isSending = false
    @State private var statusMessage: String?
    @State private var didSend = false

    private var canSend: Bool {
        session.isAdmin && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OFFICIAL UPDATE")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(CatharsiaStyle.aqua)
                    Text("Catharsia announcement")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("It appears in the community inbox. Push follows each person’s settings, including yours.")
                        .font(.body)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if focusedField != nil {
                        HStack {
                            Spacer()
                            Button {
                                focusedField = nil
                            } label: {
                                Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.violet)
                                    .padding(.horizontal, 11)
                                    .frame(height: 34)
                                    .background(CatharsiaStyle.panel, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Dismisses the keyboard and keeps this draft.")
                        }
                    }
                    field(title: "Title", text: $title, limit: 60, axis: .horizontal)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Message").font(.body.weight(.semibold)).foregroundStyle(CatharsiaStyle.ink)
                            Spacer()
                            Text("\(message.count)/240").font(.footnote.monospacedDigit()).foregroundStyle(CatharsiaStyle.muted)
                        }
                        TextField("Write a short community update", text: $message, axis: .vertical)
                            .font(.body)
                            .lineLimit(4...7)
                            .fixedSize(horizontal: false, vertical: true)
                            .focused($focusedField, equals: .message)
                            .accessibilityLabel("Announcement message")
                            .accessibilityHint("Up to 240 characters.")
                            .padding(14)
                            .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onChange(of: message) { _, value in if value.count > 240 { message = String(value.prefix(240)) } }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Link to a page")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Menu {
                            Button("No link", systemImage: "xmark") { destination = nil }
                            ForEach(CatharsiaAnnouncementDestination.allCases) { page in
                                Button(page.title, systemImage: page.symbol) { destination = page }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: destination?.symbol ?? "link")
                                    .foregroundStyle(CatharsiaStyle.violet)
                                    .accessibilityHidden(true)
                                Text(destination?.title ?? "No link")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(CatharsiaStyle.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.muted)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityLabel("Announcement destination")
                        .accessibilityValue(destination?.title ?? "No link")
                        .accessibilityHint("Choose Explore, Saved posts, or Profile.")
                    }
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let statusMessage {
                    Label(statusMessage, systemImage: didSend ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(didSend ? CatharsiaStyle.aqua : CatharsiaStyle.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { isConfirming = true } label: {
                    HStack(spacing: 8) {
                        if isSending { ProgressView().tint(.white) }
                        Text(isSending ? "Sending" : "Send announcement")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(canSend ? CatharsiaStyle.violet : CatharsiaStyle.muted.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(18)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Official announcements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Send this announcement?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Send announcement", role: .destructive) { Task { await send() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will appear in the Catharsia inbox, including yours. Push delivery follows each person’s settings.")
        }
        .task {
            guard session.isAdmin else { statusMessage = "This tool is only available to a Catharsia administrator."; return }
        }
    }

    private func field(title: String, text: Binding<String>, limit: Int, axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(CatharsiaStyle.ink)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)").font(.footnote.monospacedDigit()).foregroundStyle(CatharsiaStyle.muted)
            }
            TextField(title, text: text, axis: axis)
                .font(.body)
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focusedField, equals: .title)
                .accessibilityLabel(title == "Title" ? "Announcement title" : title)
                .accessibilityHint("Up to \(limit) characters.")
                .padding(14)
                .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: text.wrappedValue) { _, value in if value.count > limit { text.wrappedValue = String(value.prefix(limit)) } }
        }
    }

    @MainActor
    private func send() async {
        isSending = true
        statusMessage = nil
        defer { isSending = false }
        let sentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentBody = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentDestination = destination?.rawValue
        do {
            let response: AnnouncementResponse = try await SupabaseServices.shared.client.functions.invoke(
                "catharsia-push",
                options: FunctionInvokeOptions(method: .post, body: AnnouncementRequest(
                    action: "announcement",
                    title: sentTitle,
                    body: sentBody,
                    destination: sentDestination
                ))
            )
            didSend = true
            let environments = response.pushSentByEnvironment ?? [:]
            let sandboxAccepted = environments["sandbox"] ?? 0
            let productionAccepted = environments["production"] ?? 0
            statusMessage = "Added to \(response.recipients) accounts. APNs accepted \(response.pushSent) (sandbox \(sandboxAccepted), production \(productionAccepted))."
            NotificationCenter.default.post(
                name: .catharsiaShowInAppNotificationBanner,
                object: nil,
                userInfo: [
                    "title": sentTitle,
                    "body": sentBody,
                    "destination": sentDestination ?? "notifications"
                ]
            )
            title = ""
            message = ""
        } catch {
            didSend = false
            statusMessage = error.localizedDescription
        }
    }
}

private struct AnnouncementRequest: Encodable, Sendable {
    let action: String
    let title: String
    let body: String
    let destination: String?
}

private struct AnnouncementResponse: Decodable, Sendable {
    let ok: Bool
    let recipients: Int
    let pushSent: Int
    let pushSentByEnvironment: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case ok, recipients
        case pushSent = "push_sent"
        case pushSentByEnvironment = "push_sent_by_environment"
    }
}
