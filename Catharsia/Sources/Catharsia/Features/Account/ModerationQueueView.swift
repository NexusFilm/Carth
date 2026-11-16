import SwiftUI

struct ModerationQueueView: View {
    @State private var reports: [ModerationReport] = []
    @State private var selectedReport: ModerationReport?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        Group {
            if isLoading && reports.isEmpty {
                ProgressView().tint(CatharsiaStyle.violet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(CatharsiaStyle.aqua)
                    Text("You’re all caught up")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("New reports will appear here for review.")
                        .font(.subheadline)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 13) {
                        ForEach(reports) { report in
                            reportCard(report)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Safety review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .task { await load() }
        .confirmationDialog("Remove reported content?", isPresented: Binding(
            get: { selectedReport != nil },
            set: { if !$0 { selectedReport = nil } }
        ), titleVisibility: .visible) {
            Button("Remove content", role: .destructive) {
                guard let selectedReport else { return }
                Task { await review(selectedReport, removeContent: true) }
            }
            Button("Cancel", role: .cancel) { selectedReport = nil }
        } message: {
            Text("The reported comment or post will be removed from Explore.")
        }
        .alert("Safety review", isPresented: Binding(
            get: { errorMessage != nil || statusMessage != nil },
            set: { if !$0 { errorMessage = nil; statusMessage = nil } }
        )) {
            Button("Done", role: .cancel) { errorMessage = nil; statusMessage = nil }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
    }

    private func reportCard(_ report: ModerationReport) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: report.commentId == nil ? "POST REPORT" : "COMMENT REPORT")
                    Spacer()
                    Text(report.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CatharsiaStyle.muted)
                }
                Text(report.authorName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Text(report.content)
                    .font(.subheadline)
                    .lineLimit(6)
                    .foregroundStyle(CatharsiaStyle.ink.opacity(0.9))
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        selectedReport = report
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(isWorking)
                    Spacer()
                    Button("Dismiss report") {
                        Task { await review(report, removeContent: false) }
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(isWorking)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            reports = try await SupabaseInteractionService().pendingReports()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func review(_ report: ModerationReport, removeContent: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseInteractionService().reviewReport(id: report.id, removeContent: removeContent)
            reports.removeAll { $0.id == report.id }
            selectedReport = nil
            statusMessage = removeContent ? "The content was removed." : "The report was dismissed."
        } catch {
            selectedReport = nil
            errorMessage = error.localizedDescription
        }
    }
}
