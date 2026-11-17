@preconcurrency import AVFoundation
import Combine
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposePostView: View {
    typealias PublishAction = (String, String, [PostMediaUpload], String?) async throws -> Void
    typealias UpdateAction = (String, String, [PostMedia], [PostMediaUpload], String?) async throws -> Void

    private enum FocusedField: Hashable {
        case caption
        case link
    }

    private let onPublish: PublishAction?
    private let onUpdate: UpdateAction?
    private let editingPost: PublishedPost?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: FocusedField?
    @Binding private var isComposerActionsPresented: Bool

    @State private var caption = ""
    @State private var externalURLText = ""
    @State private var didAttemptExternalURLValidation = false
    @State private var isLinkEditorVisible = false
    @State private var retainedMedia: [PostMedia] = []
    @State private var media: [DraftPostMedia] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var showCamera = false
    @State private var showDiscardConfirmation = false
    @State private var isProcessingMedia = false
    @State private var isPublishing = false
    @State private var errorMessage: String?

    private let captionLimit = 800

    init(isComposerActionsPresented: Binding<Bool>, onPublish: @escaping PublishAction) {
        _isComposerActionsPresented = isComposerActionsPresented
        self.onPublish = onPublish
        onUpdate = nil
        editingPost = nil
        _caption = State(initialValue: "")
        _externalURLText = State(initialValue: "")
        _isLinkEditorVisible = State(initialValue: false)
        _retainedMedia = State(initialValue: [])
    }

    init(editing post: PublishedPost, isComposerActionsPresented: Binding<Bool>, onUpdate: @escaping UpdateAction) {
        _isComposerActionsPresented = isComposerActionsPresented
        onPublish = nil
        self.onUpdate = onUpdate
        editingPost = post
        _caption = State(initialValue: post.caption)
        _externalURLText = State(initialValue: post.externalLink?.url.absoluteString ?? "")
        _isLinkEditorVisible = State(initialValue: post.externalLink != nil)
        _retainedMedia = State(initialValue: post.mediaItems)
    }

    var body: some View {
        Group {
            if editingPost != nil {
                editScreen
            } else {
                inlineComposer
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(mediaCount: totalMediaCount) { capture in
                Task { await addCapture(capture) }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importLibrary(items) }
        }
        .onChange(of: focusedField) { previous, current in
            if previous == .link && current != .link {
                didAttemptExternalURLValidation = true
            }
        }
        .onChange(of: caption) { _, value in
            if value.count > captionLimit { caption = String(value.prefix(captionLimit)) }
        }
        .preferredColorScheme(.light)
    }

    private var inlineComposer: some View {
        VStack(spacing: 5) {
            if showDiscardConfirmation {
                discardConfirmationPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                if hasDraft || focusedField != nil {
                    HStack {
                        if hasDraft {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                    isComposerActionsPresented = false
                                    showDiscardConfirmation = true
                                }
                            } label: {
                                Label("Discard draft", systemImage: "xmark.circle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CatharsiaStyle.muted)
                            }
                            .buttonStyle(.plain)
                            .disabled(isPublishing || isProcessingMedia)
                        }
                        Spacer()
                        if focusedField != nil && !isComposerActionsPresented { keyboardDismissButton }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }

                if isComposerActionsPresented { composerActionsRow }

                if totalMediaCount > 0 { mediaStrip }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        captionField
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        HStack(spacing: 10) {
                            cameraButton
                            photoPickerButton
                            Spacer(minLength: 8)
                            publishButton
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        cameraButton
                        photoPickerButton
                        captionInput
                    }
                }

                if isLinkEditorVisible { linkEditor }

                if isProcessingMedia || errorMessage != nil { processingStatus }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(CatharsiaStyle.canvas)
        .overlay(alignment: .top) { Rectangle().fill(CatharsiaStyle.ink.opacity(0.08)).frame(height: 1) }
    }

    private var discardConfirmationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CatharsiaStyle.coral)
                    .frame(width: 34, height: 34)
                    .background(CatharsiaStyle.coral.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Discard this draft?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Text("Your text and media will be removed.")
                        .font(.caption)
                        .foregroundStyle(CatharsiaStyle.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Keep editing") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        showDiscardConfirmation = false
                    }
                }
                .foregroundStyle(CatharsiaStyle.violet)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(CatharsiaStyle.panelRaised.opacity(0.7), in: Capsule())
                .buttonStyle(.plain)

                Button(role: .destructive, action: discardDraft) {
                    Text("Discard draft")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(CatharsiaStyle.coral.opacity(0.09), in: Capsule())
                }
                .tint(CatharsiaStyle.coral)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.07), lineWidth: 1))
    }

    private var editScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if focusedField != nil {
                        HStack {
                            Spacer()
                            keyboardDismissButton
                        }
                        .transition(.opacity)
                    }

                    TextField("Write a caption…", text: $caption, axis: .vertical)
                        .font(.body)
                        .lineLimit(3...8)
                        .focused($focusedField, equals: .caption)
                        .foregroundStyle(CatharsiaStyle.ink)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Edit post caption")

                    if isLinkEditorVisible { linkEditor }

                    if totalMediaCount > 0 { mediaStrip }

                    HStack(spacing: 12) {
                        cameraButton
                        photoPickerButton
                        Text("\(totalMediaCount)/5")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.muted)
                        Spacer()
                    }

                    if isProcessingMedia || errorMessage != nil { processingStatus }
                }
                .padding(20)
            }
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { publish() }
                        .fontWeight(.semibold)
                        .disabled(!canPublish || isPublishing || isProcessingMedia)
                }
            }
        }
    }

    private var photoPickerButton: some View {
        PostComposerActionsButton(
            isPresented: $isComposerActionsPresented,
            onToggle: toggleComposerActions
        )
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $pickerItems,
            maxSelectionCount: max(1, 5 - totalMediaCount),
            matching: .any(of: [.images, .videos])
        )
        .accessibilityLabel("More post options")
        .accessibilityHint("Add a photo, video, or link to this post.")
        .disabled(isProcessingMedia || isPublishing)
    }

    private func toggleComposerActions() {
        guard !isProcessingMedia, !isPublishing else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isComposerActionsPresented.toggle()
        }
    }

    private var composerActionsRow: some View {
        HStack(spacing: 3) {
            composerActionButton(
                symbol: "link",
                label: externalURLText.isEmpty ? "Add a link" : "Edit link"
            ) {
                focusedField = nil
                didAttemptExternalURLValidation = false
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    isComposerActionsPresented = false
                    isLinkEditorVisible = true
                }
            }

            composerActionButton(symbol: "photo.on.rectangle", label: "Photo or video") {
                focusedField = nil
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    isComposerActionsPresented = false
                }
                isPhotoPickerPresented = true
            }
            .disabled(totalMediaCount >= 5 || isProcessingMedia || isPublishing)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.leading, 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .contain)
    }

    private func composerActionButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CatharsiaStyle.violet)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.ink)
            }
            .frame(minHeight: 42)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PostComposerPressStyle())
        .accessibilityLabel(label)
    }

    private var captionInput: some View {
        HStack(spacing: 6) {
            captionField
            publishButton
        }
        .padding(5)
        .frame(minHeight: 56)
        .background(CatharsiaStyle.panel, in: Capsule())
    }

    private var captionField: some View {
        TextField("Share a thought…", text: $caption, axis: .vertical)
            .font(.body.weight(.medium))
            .lineLimit(1...3)
            .fixedSize(horizontal: false, vertical: true)
            .focused($focusedField, equals: .caption)
            .foregroundStyle(CatharsiaStyle.ink)
            .padding(.leading, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .accessibilityLabel("Write a post caption")
            .accessibilityHint("Add text to your post. Use the plus button for photos, videos, or a link.")
            .disabled(isPublishing || isProcessingMedia)
    }

    private var keyboardDismissButton: some View {
        Button {
            focusedField = nil
        } label: {
            Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.violet)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(CatharsiaStyle.panel, in: Capsule())
                .overlay(Capsule().stroke(CatharsiaStyle.violet.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PostComposerPressStyle())
        .accessibilityHint("Keeps your draft and closes the keyboard.")
    }

    private var cameraButton: some View {
        Button(action: beginCamera) {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(CatharsiaStyle.violet, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open camera")
        .disabled(totalMediaCount >= 5 || isProcessingMedia || isPublishing)
    }

    private var publishButton: some View {
        Button(action: publish) {
            Group {
                if isPublishing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(canPublish ? CatharsiaStyle.aqua : CatharsiaStyle.muted.opacity(0.24), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Publish post")
        .disabled(!canPublish || isPublishing || isProcessingMedia)
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Post link", systemImage: "link")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.ink)
                Spacer()
                Button("Remove", action: removeExternalLink)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .disabled(isPublishing || isProcessingMedia)
            }

            TextField("https://your-event-or-resource.com", text: $externalURLText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focusedField, equals: .link)
                .accessibilityLabel("External post link")
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(CatharsiaStyle.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .disabled(isPublishing || isProcessingMedia)

            Text(hasInvalidExternalURL && didAttemptExternalURLValidation
                 ? "Enter a valid https:// link."
                 : "Paste a secure https:// link.")
                .font(.caption)
                .foregroundStyle(hasInvalidExternalURL && didAttemptExternalURLValidation ? CatharsiaStyle.coral : CatharsiaStyle.muted)
        }
        .padding(11)
        .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var processingStatus: some View {
        HStack(spacing: 7) {
            if isProcessingMedia { ProgressView().tint(CatharsiaStyle.violet) }
            Text(errorMessage ?? "Preparing media…")
                .font(.body)
                .foregroundStyle(errorMessage == nil ? CatharsiaStyle.muted : CatharsiaStyle.coral)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text("\(totalMediaCount)/5")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(CatharsiaStyle.muted)
        }
    }

    private var mediaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(retainedMedia, id: \.path) { item in
                    existingMediaTile(item)
                }
                ForEach(media) { item in
                    draftMediaTile(item)
                }
                Text("\(totalMediaCount)/5")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.muted)
                    .padding(.horizontal, 5)
            }
            .padding(.horizontal, 3)
        }
    }

    private func existingMediaTile(_ item: PostMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if item.kind == .photo, let url = SupabaseServices.shared.publicMediaURL(for: item.path) {
                    PostPhotoView(url: url, contentMode: .fill)
                } else {
                    CatharsiaStyle.panelRaised
                    Image(systemName: item.kind == .video ? "play.fill" : "photo")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CatharsiaStyle.violet)
                }
            }
            .frame(width: 70, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.58), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
            }
            removeMediaButton(label: "Remove attached media") {
                retainedMedia.removeAll { $0.path == item.path }
            }
        }
        .frame(width: 70, height: 62)
    }

    private func draftMediaTile(_ item: DraftPostMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = item.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    CatharsiaStyle.panelRaised
                    Image(systemName: item.upload.kind == .video ? "play.fill" : "photo")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CatharsiaStyle.violet)
                }
            }
            .frame(width: 70, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            if item.upload.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.58), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
            }
            removeMediaButton(label: "Remove added media") { remove(item) }
        }
        .frame(width: 70, height: 62)
    }

    private func removeMediaButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.65), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var totalMediaCount: Int { retainedMedia.count + media.count }

    private var hasDraft: Bool {
        !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !externalURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || totalMediaCount > 0
    }

    private var canPublish: Bool {
        let hasCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return caption.count <= captionLimit
            && !hasInvalidExternalURL
            && (totalMediaCount > 0 || hasCaption || normalizedExternalURL != nil)
    }

    private var normalizedExternalURL: String? {
        ExternalURLPolicy.url(from: externalURLText)?.absoluteString
    }

    private var hasInvalidExternalURL: Bool {
        !externalURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && normalizedExternalURL == nil
    }

    private func beginCamera() {
        focusedField = nil
        guard totalMediaCount < 5 else { return }
        guard AVCaptureDevice.default(for: .video) != nil else {
            errorMessage = "Camera capture is available on iPhone. Add media from your library in the simulator."
            return
        }
        showCamera = true
    }

    private func importLibrary(_ items: [PhotosPickerItem]) async {
        isProcessingMedia = true
        errorMessage = nil
        defer {
            isProcessingMedia = false
            pickerItems = []
        }

        for item in items.prefix(max(0, 5 - totalMediaCount)) {
            do {
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
                if isVideo, let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    try await addVideo(movie.url)
                } else if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    try addPhoto(image)
                }
            } catch {
                if !Task.isCancelled && !error.isCatharsiaCancellation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func addCapture(_ capture: CapturedMedia) async {
        do {
            switch capture.kind {
            case .photo:
                guard let data = capture.data else { throw FeedServiceError.actionFailed }
                guard let image = UIImage(data: data) else { throw FeedServiceError.actionFailed }
                try addPhoto(image)
            case .video:
                guard let url = capture.url else { throw FeedServiceError.actionFailed }
                try await addVideo(url)
            }
        } catch {
            if !Task.isCancelled && !error.isCatharsiaCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addPhoto(_ image: UIImage) throws {
        guard totalMediaCount < 5 else { throw FeedServiceError.mediaSelectionInvalid }
        guard let data = optimizedJPEG(image), data.count <= 12 * 1_048_576 else {
            throw FeedServiceError.mediaFileTooLarge
        }
        let url = temporaryURL(extension: "jpg")
        try data.write(to: url, options: .atomic)
        let upload = PostMediaUpload(kind: .photo, fileURL: url, mimeType: "image/jpeg", fileExtension: "jpg", durationSeconds: nil)
        media.append(DraftPostMedia(upload: upload, preview: UIImage(data: data)))
    }

    private func addVideo(_ sourceURL: URL) async throws {
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard totalMediaCount < 5 else { throw FeedServiceError.mediaSelectionInvalid }
        isProcessingMedia = true
        defer { isProcessingMedia = false }
        let output = try await PostMediaProcessor.make720pMP4(from: sourceURL)
        let size = try output.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= CatharsiaMediaLimits.maximumVideoUploadBytes else {
            try? FileManager.default.removeItem(at: output.url)
            throw FeedServiceError.mediaFileTooLarge
        }
        let upload = PostMediaUpload(kind: .video, fileURL: output.url, mimeType: "video/mp4", fileExtension: "mp4", durationSeconds: output.duration)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output.url))
        generator.appliesPreferredTrackTransform = true
        let poster = try? UIImage(cgImage: generator.copyCGImage(at: .zero, actualTime: nil))
        media.append(DraftPostMedia(upload: upload, preview: poster))
    }

    private func remove(_ item: DraftPostMedia) {
        media.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.upload.fileURL)
    }

    private func discardDraft() {
        focusedField = nil
        showDiscardConfirmation = false
        media.forEach { try? FileManager.default.removeItem(at: $0.upload.fileURL) }
        media = []
        caption = ""
        externalURLText = ""
        isLinkEditorVisible = false
        pickerItems = []
        errorMessage = nil
    }

    private func removeExternalLink() {
        externalURLText = ""
        didAttemptExternalURLValidation = false
        focusedField = nil
        withAnimation(.easeOut(duration: 0.18)) { isLinkEditorVisible = false }
    }

    private func publish() {
        guard canPublish else { return }
        focusedField = nil
        isPublishing = true
        errorMessage = nil
        Task {
            defer { isPublishing = false }
            do {
                let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                if let editingPost, let onUpdate {
                    try await onUpdate(editingPost.id, cleanCaption, retainedMedia, media.map(\.upload), normalizedExternalURL)
                    media.forEach { try? FileManager.default.removeItem(at: $0.upload.fileURL) }
                    media = []
                    dismiss()
                } else if let onPublish {
                    try await onPublish(cleanCaption, "", media.map(\.upload), normalizedExternalURL)
                    media.forEach { try? FileManager.default.removeItem(at: $0.upload.fileURL) }
                    media = []
                    caption = ""
                    externalURLText = ""
                    isLinkEditorVisible = false
                    dismiss()
                }
            } catch {
                if !Task.isCancelled && !error.isCatharsiaCancellation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func optimizedJPEG(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1920
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in stride(from: 0.88, through: 0.32, by: -0.08) {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 12 * 1_048_576 { return data }
        }
        return resized.jpegData(compressionQuality: 0.28)
    }

    private func temporaryURL(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("catharsia-\(UUID().uuidString.lowercased())")
            .appendingPathExtension(fileExtension)
    }
}

private struct PostComposerActionsButton: View {
    @Binding var isPresented: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CatharsiaStyle.violet)
                .rotationEffect(.degrees(isPresented ? 45 : 0))
                .frame(width: 46, height: 46)
                .background(CatharsiaStyle.panel, in: Circle())
                .overlay(Circle().stroke(CatharsiaStyle.violet.opacity(0.1), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PostComposerPressStyle())
        .accessibilityLabel(isPresented ? "Close post options" : "More post options")
        .accessibilityHint(isPresented ? "Closes post actions." : "Add a photo, video, or link to this post.")
        .sensoryFeedback(.selection, trigger: isPresented)
    }
}

private struct PostComposerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DraftPostMedia: Identifiable {
    let id = UUID()
    let upload: PostMediaUpload
    let preview: UIImage?
}

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .video) { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("catharsia-library-\(UUID().uuidString.lowercased())")
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

private struct CapturedMedia: Identifiable, Sendable {
    enum Kind: Sendable { case photo, video }
    let id = UUID()
    let kind: Kind
    let data: Data?
    let url: URL?

    static func photo(_ data: Data) -> Self { Self(kind: .photo, data: data, url: nil) }
    static func video(_ url: URL) -> Self { Self(kind: .video, data: nil, url: url) }
}

private struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = CameraSessionModel()
    @State private var mode: CameraSessionModel.CaptureMode = .video
    @State private var prompt = ""
    @State private var isEditingPrompt = false
    @State private var teleprompterSpeed = 25.0
    @FocusState private var promptIsFocused: Bool
    let mediaCount: Int
    let onCapture: (CapturedMedia) -> Void

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: CatharsiaStyle.ink.opacity(0.78), location: 0),
                    .init(color: .clear, location: 0.26),
                    .init(color: .clear, location: 0.58),
                    .init(color: CatharsiaStyle.ink.opacity(0.84), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                cameraHeader

                if mode == .video { teleprompterPanel }

                Spacer(minLength: 16)

                if let message = camera.errorMessage { cameraError(message) }

                if !isEditingPrompt {
                    cameraControls
                }
            }

            if !camera.isReady && camera.errorMessage == nil {
                ProgressView("Opening camera")
                    .tint(CatharsiaStyle.aqua)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(camera.isRecording)
        .onAppear {
            camera.configure()
        }
        .onChange(of: camera.isRecording) { _, isRecording in
            if isRecording {
                promptIsFocused = false
                isEditingPrompt = false
            }
        }
        .onChange(of: camera.captured?.id) { _, _ in
            guard let captured = camera.captured else { return }
            onCapture(captured)
            dismiss()
        }
        .onDisappear { camera.stopSession() }
    }

    private var cameraHeader: some View {
        HStack(spacing: 0) {
            cameraButton("xmark", label: "Close camera") {
                promptIsFocused = false
                camera.discardAndStop()
                dismiss()
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                BrainMark(size: 27)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CATHARSIA")
                        .font(.caption.weight(.heavy))
                        .tracking(1.7)
                        .foregroundStyle(.white)
                    Text("CAMERA")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Catharsia camera")
            Spacer(minLength: 12)
            cameraButton("arrow.triangle.2.circlepath.camera", label: "Switch camera") { camera.flipCamera() }
                .disabled(camera.isRecording || !camera.isReady)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var teleprompterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.aqua)
                    .accessibilityHidden(true)
                Text("PROMPTER")
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.92))
                    .accessibilityAddTraits(.isHeader)
                if camera.isRecording {
                    Circle().fill(CatharsiaStyle.coral).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Spacer()
                if isEditingPrompt {
                    Button("Done") {
                        promptIsFocused = false
                        isEditingPrompt = false
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 48, minHeight: 44)
                    .accessibilityHint("Closes the prompt editor and keeps your script on screen.")
                } else {
                    Button(prompt.isEmpty ? "Add prompt" : "Edit") {
                        isEditingPrompt = true
                        promptIsFocused = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(minWidth: 48, minHeight: 44)
                    .disabled(camera.isRecording)
                    .accessibilityHint(prompt.isEmpty ? "Write a script to read while recording." : "Edit your teleprompter script.")
                }
            }

            if isEditingPrompt {
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Write what you want to say…")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 9)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $prompt)
                        .font(.body)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .focused($promptIsFocused)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .accessibilityLabel("Teleprompter script")
                        .accessibilityHint("Your script stays on this camera screen and scrolls while you record.")
                }
                .frame(height: 88)
            } else if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    isEditingPrompt = true
                    promptIsFocused = true
                } label: {
                    Label("Add a prompt", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(camera.isRecording)
                .accessibilityHint("Add text to read while looking at the camera.")
            } else {
                TeleprompterReader(
                    text: prompt,
                    isScrolling: camera.isRecording && !reduceMotion,
                    speed: CGFloat(teleprompterSpeed)
                )
                .frame(height: 88)

                if !camera.isRecording {
                    HStack(spacing: 9) {
                        Image(systemName: "tortoise.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Slider(value: $teleprompterSpeed, in: 12...48)
                            .tint(CatharsiaStyle.aqua)
                            .accessibilityLabel("Teleprompter scroll speed")
                            .accessibilityValue(teleprompterSpeed < 20 ? "Slow" : teleprompterSpeed < 36 ? "Medium" : "Fast")
                            .accessibilityHint("Adjust how quickly the script scrolls during recording.")
                        Image(systemName: "hare.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(colors: [CatharsiaStyle.violet.opacity(0.86), CatharsiaStyle.aqua.opacity(0.78), .white.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2
                )
        }
        .shadow(color: CatharsiaStyle.violet.opacity(0.20), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var cameraControls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 5) {
                modeButton(.video, title: "Video")
                modeButton(.photo, title: "Photo")
            }
            .padding(4)
            .background(.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))

            HStack(alignment: .center) {
                Text("\(mediaCount) / 5")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.30), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
                    .accessibilityLabel("\(mediaCount) of 5 media items added")
                Spacer()
                shutterButton
                Spacer()
                if mode == .video {
                    TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                        Text(camera.isRecording ? camera.recordingTimeLabel(at: timeline.date) : "60 SEC")
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 36)
                            .background(.black.opacity(0.34), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                            .accessibilityLabel(camera.isRecording ? "Recording time" : "Maximum recording time")
                            .accessibilityValue(camera.recordingTimeLabel(at: timeline.date))
                    }
                } else {
                    Color.clear.frame(width: 72, height: 36)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: 330)

            Text(camera.isRecording ? "Reading your prompt" : mediaCount >= 5 ? "Post is full" : mode == .video ? "Up to one minute" : "A moment to keep")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.76))
                .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private var shutterButton: some View {
        Button(action: shutterAction) {
            ZStack {
                Circle().fill(.black.opacity(0.24)).frame(width: 88, height: 88)
                Circle().stroke(.white.opacity(0.72), lineWidth: 1).frame(width: 80, height: 80)
                if camera.isRecording {
                    TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                        Circle()
                            .trim(from: 0, to: camera.recordingProgress(at: timeline.date))
                            .stroke(
                                AngularGradient(colors: [CatharsiaStyle.aqua, CatharsiaStyle.violet, CatharsiaStyle.coral], center: .center),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 88, height: 88)
                            .accessibilityHidden(true)
                    }
                } else {
                    Circle()
                        .stroke(LinearGradient(colors: [CatharsiaStyle.violet, CatharsiaStyle.aqua], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 5)
                        .frame(width: 88, height: 88)
                        .accessibilityHidden(true)
                }
                Group {
                    if camera.isRecording {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CatharsiaStyle.coral)
                            .frame(width: 27, height: 27)
                    } else if mode == .video {
                        Circle()
                            .fill(CatharsiaStyle.violet)
                            .overlay(Circle().fill(CatharsiaStyle.aqua.opacity(0.38)).padding(5))
                            .frame(width: 57, height: 57)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 54, height: 54)
                    }
                }
            }
            .frame(width: 92, height: 92)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!camera.isReady || camera.errorMessage != nil || (mediaCount >= 5 && !camera.isRecording))
        .accessibilityLabel(camera.isRecording ? "Stop recording" : mode == .photo ? "Take photo" : "Start recording")
        .accessibilityValue(camera.isRecording ? camera.recordingTimeLabel(at: .now) : mode == .video ? "Maximum 60 seconds" : "Photo mode")
        .accessibilityHint(camera.isRecording ? "Saves this clip and returns it to your post." : "Starts the camera capture.")
    }

    private func cameraError(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.aqua)
                .accessibilityHidden(true)
            Text(message)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
            Button("Back to post") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(CatharsiaStyle.violet, in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: 330)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.17), lineWidth: 1))
        .padding(.horizontal, 28)
    }

    private func cameraButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.34), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(label == "Switch camera" ? "Switches between the front and back cameras." : "Returns to your post.")
    }

    private func modeButton(_ option: CameraSessionModel.CaptureMode, title: String) -> some View {
        Button {
            guard !camera.isRecording else { return }
            promptIsFocused = false
            isEditingPrompt = false
            mode = option
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mode == option ? .white : .white.opacity(0.72))
                .frame(minWidth: 92, minHeight: 42)
                .background {
                    if mode == option {
                        Capsule()
                            .fill(LinearGradient(colors: [CatharsiaStyle.violet, CatharsiaStyle.aqua], startPoint: .leading, endPoint: .trailing))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == option ? .isSelected : [])
        .disabled(camera.isRecording)
    }

    private func shutterAction() {
        if mode == .photo {
            camera.takePhoto()
        } else if camera.isRecording {
            camera.stopRecording()
        } else {
            promptIsFocused = false
            isEditingPrompt = false
            camera.startRecording()
        }
    }
}

private struct TeleprompterReader: UIViewRepresentable {
    let text: String
    let isScrolling: Bool
    let speed: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textColor = UIColor.white.withAlphaComponent(0.96)
        view.font = UIFont.preferredFont(forTextStyle: .title3)
        view.adjustsFontForContentSizeCategory = true
        view.textAlignment = .center
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 30, right: 8)
        view.textContainer.lineFragmentPadding = 0
        view.text = text
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Teleprompter script"
        view.accessibilityValue = text
        view.accessibilityHint = "The script scrolls while you record."
        context.coordinator.update(view: view, isScrolling: isScrolling, speed: speed)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            context.coordinator.stop()
            view.text = text
            view.accessibilityValue = text
            view.setContentOffset(CGPoint(x: 0, y: -view.adjustedContentInset.top), animated: false)
        }
        context.coordinator.update(view: view, isScrolling: isScrolling, speed: speed)
    }

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: UITextView?
        private var displayLink: CADisplayLink?
        private var pointsPerSecond: CGFloat = 25

        func update(view: UITextView, isScrolling: Bool, speed: CGFloat) {
            self.view = view
            pointsPerSecond = speed
            if isScrolling {
                guard displayLink == nil else { return }
                view.setContentOffset(CGPoint(x: 0, y: -view.adjustedContentInset.top), animated: false)
                let link = CADisplayLink(target: self, selector: #selector(advance(_:)))
                link.preferredFramesPerSecond = 30
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                stop()
            }
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func advance(_ link: CADisplayLink) {
            guard let view else { stop(); return }
            let top = -view.adjustedContentInset.top
            let bottom = max(top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
            guard view.contentOffset.y < bottom else { stop(); return }
            view.contentOffset.y = min(bottom, view.contentOffset.y + pointsPerSecond * link.duration)
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private final class CameraSessionModel: NSObject, ObservableObject, @unchecked Sendable {
    enum CaptureMode { case photo, video }

    let session = AVCaptureSession()
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var captured: CapturedMedia?
    @Published var errorMessage: String?

    private let queue = DispatchQueue(label: "com.catharsia.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var stopRecordingWorkItem: DispatchWorkItem?
    private var isConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private var shouldDiscardRecording = false
    private var isStoppingRecording = false

    func recordingTimeLabel(at date: Date) -> String {
        guard let recordingStartedAt else { return "00:00 / 01:00" }
        let elapsed = min(Int(CatharsiaMediaLimits.maximumVideoDuration), max(0, Int(date.timeIntervalSince(recordingStartedAt))))
        return String(format: "%02d:%02d / 01:00", elapsed / 60, elapsed % 60)
    }

    func recordingProgress(at date: Date) -> CGFloat {
        guard let recordingStartedAt else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(recordingStartedAt))
        return CGFloat(min(1, elapsed / CatharsiaMediaLimits.maximumVideoDuration))
    }

    func configure() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.errorMessage = "Allow camera access in Settings to record a post." }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] audioGranted in
                guard let self else { return }
                self.configureSession(includeAudio: audioGranted)
            }
        }
    }

    private func configureSession(includeAudio: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isConfigured {
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.isReady = true }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720

            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition) else {
                    throw FeedServiceError.actionFailed
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw FeedServiceError.actionFailed }
                self.session.addInput(input)
                self.videoInput = input

                if includeAudio, let audio = AVCaptureDevice.default(for: .audio) {
                    let audioInput = try AVCaptureDeviceInput(device: audio)
                    if self.session.canAddInput(audioInput) { self.session.addInput(audioInput) }
                }
                guard self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.movieOutput) else {
                    throw FeedServiceError.actionFailed
                }
                self.session.addOutput(self.photoOutput)
                self.session.addOutput(self.movieOutput)
                self.movieOutput.maxRecordedDuration = CMTime(seconds: CatharsiaMediaLimits.maximumVideoDuration, preferredTimescale: 600)
                self.movieOutput.maxRecordedFileSize = Int64(CatharsiaMediaLimits.maximumCameraSourceBytes)
                self.session.commitConfiguration()
                self.isConfigured = true
                self.session.startRunning()
                DispatchQueue.main.async { self.isReady = true }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.errorMessage = "Catharsia couldn’t open the camera. Choose media from your library instead." }
            }
        }
    }

    func takePhoto() {
        guard isReady, !isRecording else { return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        guard isReady, !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catharsia-camera-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("mov")
        shouldDiscardRecording = false
        isStoppingRecording = false
        isRecording = true
        recordingStartedAt = Date()
        movieOutput.startRecording(to: url, recordingDelegate: self)
        let work = DispatchWorkItem { [weak self] in self?.stopRecording() }
        stopRecordingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CatharsiaMediaLimits.maximumVideoDuration, execute: work)
    }

    func stopRecording() {
        guard isRecording, !isStoppingRecording else { return }
        isStoppingRecording = true
        stopRecordingWorkItem?.cancel()
        stopRecordingWorkItem = nil
        movieOutput.stopRecording()
    }

    func flipCamera() {
        guard isReady, !isRecording else { return }
        queue.async { [weak self] in
            guard let self, let currentInput = self.videoInput else { return }
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.currentPosition = newPosition
            } else {
                self.session.addInput(currentInput)
            }
            self.session.commitConfiguration()
        }
    }

    func stopSession() {
        if isRecording { stopRecording() }
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func discardAndStop() {
        if isRecording {
            shouldDiscardRecording = true
            stopRecording()
        }
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

extension CameraSessionModel: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { self.captured = .photo(data) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingStartedAt = nil
            self.isStoppingRecording = false
            let shouldDiscard = self.shouldDiscardRecording
            self.shouldDiscardRecording = false
            if error == nil && !shouldDiscard { self.captured = .video(outputFileURL) }
            else {
                try? FileManager.default.removeItem(at: outputFileURL)
                if !shouldDiscard { self.errorMessage = "The clip couldn’t be saved. Please try again." }
            }
        }
    }
}

private enum PostMediaProcessor {
    static func make720pMP4(from sourceURL: URL) async throws -> (url: URL, duration: Double) {
        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0, duration <= CatharsiaMediaLimits.maximumVideoDuration else { throw FeedServiceError.videoTooLong }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw FeedServiceError.actionFailed
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catharsia-video-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("mp4")
        var keepOutput = false
        defer {
            if !keepOutput { try? FileManager.default.removeItem(at: outputURL) }
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.fileLengthLimit = Int64(CatharsiaMediaLimits.maximumVideoUploadBytes)
        let exportBox = AssetExportSessionBox(exporter)

        try await withCheckedThrowingContinuation { continuation in
            exportBox.session.exportAsynchronously {
                switch exportBox.session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed, .cancelled:
                    continuation.resume(throwing: exportBox.session.error ?? FeedServiceError.actionFailed)
                default:
                    continuation.resume(throwing: FeedServiceError.actionFailed)
                }
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= CatharsiaMediaLimits.maximumVideoUploadBytes else {
            throw FeedServiceError.mediaFileTooLarge
        }
        keepOutput = true
        return (outputURL, duration)
    }
}

private final class AssetExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
