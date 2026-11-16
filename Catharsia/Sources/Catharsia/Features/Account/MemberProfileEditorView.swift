import PhotosUI
import SwiftUI
import UIKit

struct MemberProfileEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var username = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedPhoto: UIImage?
    @State private var selectedJPEG: Data?
    @State private var removePhoto = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let service = SupabaseInteractionService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                avatarControl

                VStack(alignment: .leading, spacing: 14) {
                    Text("Display name")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.muted)
                    TextField("Name people see", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.body)
                        .foregroundStyle(CatharsiaStyle.ink)
                        .padding(16)
                        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Display name")

                    Text("Username")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CatharsiaStyle.muted)
                    HStack(spacing: 7) {
                        Text("@")
                            .foregroundStyle(CatharsiaStyle.violet)
                            .font(.body.weight(.semibold))
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.body)
                            .foregroundStyle(CatharsiaStyle.ink)
                            .accessibilityLabel("Username")
                    }
                    .padding(16)
                    .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("3–24 letters, numbers, or underscores")
                        .font(.caption)
                        .foregroundStyle(CatharsiaStyle.muted)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(CatharsiaStyle.aqua)
                    Text("Your name, username, and photo appear beside your posts and comments. Your email stays private.")
                        .font(.subheadline)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(CatharsiaStyle.coral)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                Button(action: save) {
                    HStack(spacing: 9) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Saving…" : "Save profile")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(CatharsiaStyle.violet, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isLoading || isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(isLoading || isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.58 : 1)
                .accessibilityHint("Save your public name, username, and profile photo")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
        .task { await loadProfile() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    private var avatarControl: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(CatharsiaStyle.panelRaised)
                if let selectedPhoto {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .scaledToFill()
                } else if !removePhoto,
                          let url = SupabaseServices.shared.publicMediaURL(for: session.profilePhotoURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { avatarFallback }
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())
            .overlay(Circle().stroke(CatharsiaStyle.violet.opacity(0.16), lineWidth: 1))
            .accessibilityHidden(true)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
                    .frame(minHeight: 44)
            }
            .disabled(isSaving)
            .accessibilityHint("Choose a profile photo from your photo library")

            if selectedPhoto != nil || session.profilePhotoURL != nil {
                Button("Remove photo", role: .destructive) {
                    selectedPhoto = nil
                    selectedJPEG = nil
                    pickerItem = nil
                    removePhoto = true
                }
                .font(.caption.weight(.semibold))
                .frame(minHeight: 36)
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var avatarFallback: some View {
        Text(String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(CatharsiaStyle.violet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await service.fetchMyMemberProfile()
            displayName = profile.displayName ?? profile.fullName ?? session.displayName
            username = profile.username ?? ""
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let source = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: source),
                  let jpeg = compressedJPEG(from: image) else {
                throw FeedServiceError.invalidProfileImage
            }
            selectedPhoto = UIImage(data: jpeg)
            selectedJPEG = jpeg
            removePhoto = false
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                errorMessage = FeedServiceError.invalidProfileImage.localizedDescription
            }
        }
    }

    private func compressedJPEG(from image: UIImage) -> Data? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        let scale = min(1, 1200 / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        var quality: CGFloat = 0.86
        while quality >= 0.5 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 4_000_000 {
                return data
            }
            quality -= 0.1
        }
        return nil
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.updateMyMemberProfile(
                    displayName: displayName,
                    username: username,
                    photoJPEGData: selectedJPEG,
                    removePhoto: removePhoto
                )
                try await session.refreshIdentity()
                dismiss()
            } catch {
                if !Task.isCancelled && !error.isCatharsiaCancellation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
