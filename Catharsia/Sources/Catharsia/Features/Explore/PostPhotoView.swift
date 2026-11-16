import SwiftUI
import UIKit

@MainActor
private enum PostPhotoLoader {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func image(for url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) { return cached }

        var lastError: Error = URLError(.badServerResponse)
        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let image = UIImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                cache.setObject(image, forKey: url as NSURL, cost: data.count)
                return image
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 0 { try await Task.sleep(for: .milliseconds(350)) }
            }
        }
        throw lastError
    }
}

struct PostPhotoView: View {
    let url: URL
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var retryCount = 0

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if didFail {
                Button {
                    didFail = false
                    retryCount += 1
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Photo unavailable")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(CatharsiaStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading photo")
            } else {
                ProgressView()
                    .tint(CatharsiaStyle.violet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CatharsiaStyle.panelRaised)
        .task(id: "\(url.absoluteString)-\(retryCount)") {
            image = nil
            didFail = false
            do {
                image = try await PostPhotoLoader.image(for: url)
                didFail = false
            } catch is CancellationError {
            } catch {
                didFail = true
            }
        }
    }
}

struct PostPhotoBackdrop: View {
    let url: URL

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var retryCount = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CatharsiaStyle.canvas
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if didFail {
                    Button {
                        didFail = false
                        retryCount += 1
                    } label: {
                        Label("Photo unavailable · Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry loading this photo")
                } else {
                    ProgressView()
                        .tint(CatharsiaStyle.violet)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: "\(url.absoluteString)-\(retryCount)") {
            image = nil
            didFail = false
            do {
                image = try await PostPhotoLoader.image(for: url)
                didFail = false
            } catch is CancellationError {
            } catch {
                didFail = true
            }
        }
    }
}
