import ImageIO
import MarkdownUI
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct LoadedImage: @unchecked Sendable {
    let cgImage: CGImage
    let pixelWidth: CGFloat
    let path: String?
}

nonisolated enum ImageLoadError: LocalizedError, Sendable {
    case missing(String)
    case blockedScheme(String)
    case remoteDisabled(URL)
    case tooLarge
    case undecodable

    var errorDescription: String? {
        switch self {
        case .missing(let name): name.isEmpty ? "Image not found" : "Image not found: \(name)"
        case .blockedScheme(let scheme): "Blocked image source (\(scheme):)"
        case .remoteDisabled(let url): "Remote image from \(url.host() ?? "the web")"
        case .tooLarge: "Image is too large to display"
        case .undecodable: "Unsupported image format"
        }
    }
}

/// Loads every image a note references. Policy:
/// - vault images come only from the verified local cache (downloaded on demand)
/// - remote images are off by default (they leak your IP / act as read receipts);
///   when allowed they must be https, use a cookie-less session and are size-capped
/// - `file:`, `data:`, `http:` and any other scheme are refused
/// - decoding is limited to common raster formats and downsampled to bound memory
final class VaultImageLoader {
    private let sync: SyncEngine
    private let vault: VaultStore
    private let auth: AuthManager
    private var cache: [String: LoadedImage] = [:]
    private var order: [String] = []

    init(sync: SyncEngine, vault: VaultStore, auth: AuthManager) {
        self.sync = sync
        self.vault = vault
        self.auth = auth
    }

    func clear() {
        cache.removeAll()
        order.removeAll()
    }

    func load(_ url: URL?, allowRemoteOnce: Bool = false) async throws -> LoadedImage {
        guard let url = url?.absoluteURL else { throw ImageLoadError.missing("") }
        let key = url.absoluteString
        if let cached = cache[key] { return cached }

        let image: LoadedImage
        switch url.scheme?.lowercased() {
        case VaultURL.fileScheme:
            let params = VaultURL.parameters(of: url)
            guard url.host() == "image", let path = params["path"], vault.contains(path) else {
                throw ImageLoadError.missing(params["name"] ?? "")
            }
            image = try await loadVault(path)
        case VaultURL.relativeScheme:
            guard let relative = VaultURL.relativePath(of: url),
                  let path = vault.resolver.resolve(relative, from: nil) else {
                throw ImageLoadError.missing(url.lastPathComponent)
            }
            image = try await loadVault(path)
        case "https":
            guard allowRemoteOnce || UserDefaults.standard.bool(forKey: Prefs.loadRemoteImages) else {
                throw ImageLoadError.remoteDisabled(url)
            }
            image = try await loadRemote(url)
        default:
            throw ImageLoadError.blockedScheme(url.scheme ?? "unknown")
        }

        cache[key] = image
        order.append(key)
        if order.count > 40 { cache[order.removeFirst()] = nil }
        return image
    }

    private func loadVault(_ path: String) async throws -> LoadedImage {
        guard PathPolicy.kind(of: path) == .image else { throw ImageLoadError.undecodable }
        let fileURL = try await sync.localURL(for: path, client: auth.client)
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageDecoder.decode(source: CGImageSourceCreateWithURL(fileURL as CFURL, ImageDecoder.sourceOptions))
        }.value
        guard let decoded else { throw ImageLoadError.undecodable }
        return LoadedImage(cgImage: decoded.image, pixelWidth: decoded.width, path: path)
    }

    private func loadRemote(_ url: URL) async throws -> LoadedImage {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await SecureSession.media.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ImageLoadError.missing(url.lastPathComponent)
        }
        let limit = AppConfig.maxRemoteImageBytes
        guard response.expectedContentLength <= Int64(limit) else { throw ImageLoadError.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(response.expectedContentLength, 0)))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw ImageLoadError.tooLarge }
        }
        let payload = data
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageDecoder.decode(source: CGImageSourceCreateWithData(payload as CFData, ImageDecoder.sourceOptions))
        }.value
        guard let decoded else { throw ImageLoadError.undecodable }
        return LoadedImage(cgImage: decoded.image, pixelWidth: decoded.width, path: nil)
    }
}

nonisolated enum ImageDecoder {
    struct Decoded: @unchecked Sendable {
        let image: CGImage
        let width: CGFloat
    }

    static let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

    static let allowedTypes: Set<String> = Set(
        [UTType.png, .jpeg, .gif, .webP, .heic, .heif, .bmp, .tiff].map(\.identifier)
    )

    /// Refuses unknown formats and absurd dimensions (decompression bombs), then
    /// downsamples so a huge photo can't exhaust memory.
    static func decode(source: CGImageSource?) -> Decoded? {
        guard let source, CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?, allowedTypes.contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width * height <= 120_000_000
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: AppConfig.maxImagePixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Decoded(image: image, width: CGFloat(min(width, image.width)))
    }
}

// MARK: - MarkdownUI providers

struct VaultImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        VaultImageView(url: url)
    }
}

/// Inline images (inside a line of text) go through the same loader, so MarkdownUI's
/// default network loader is never used.
nonisolated struct VaultInlineImageProvider: InlineImageProvider {
    let loader: VaultImageLoader

    func image(with url: URL, label: String) async throws -> Image {
        let loaded = try await loader.load(url)
        return Image(decorative: loaded.cgImage, scale: 2)
    }
}

struct VaultImageView: View {
    let url: URL?

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case loaded(LoadedImage)
        case failed(String)
        case remote(URL)
    }

    private var requestedWidth: CGFloat? {
        url.flatMap { VaultURL.parameters(of: $0)["w"] }.flatMap(Double.init).map { CGFloat($0) }
    }

    var body: some View {
        content
            .task(id: url) { await load(allowRemoteOnce: false) }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            RoundedRectangle(cornerRadius: Shad.radius)
                .fill(Shad.muted.opacity(0.6))
                .frame(maxWidth: requestedWidth ?? .infinity)
                .frame(height: 160)
                .overlay(ProgressView().controlSize(.small))
        case .loaded(let image):
            let natural = image.pixelWidth / max(displayScale, 1)
            let width = requestedWidth.map { min($0, natural) } ?? natural
            let height = width * CGFloat(image.cgImage.height) / CGFloat(max(image.cgImage.width, 1))
            ScrollView(.horizontal, showsIndicators: false) {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: Shad.radius))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let path = image.path, let link = URL(string: VaultURL.file(path)) { openURL(link) }
                    }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(height: height)
            .padding(.vertical, 4)
        case .failed(let message):
            placeholder(icon: "photo", text: message)
        case .remote(let remote):
            HStack(spacing: 10) {
                placeholderLabel(icon: "globe", text: "Remote image from \(remote.host() ?? "the web") blocked")
                Spacer(minLength: 8)
                Button("Load once") { Task { await load(allowRemoteOnce: true) } }
                    .buttonStyle(.shad(.outline, size: .sm))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Shad.radius).strokeBorder(Shad.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        placeholderLabel(icon: icon, text: text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Shad.radius).strokeBorder(Shad.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func placeholderLabel(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(Shad.font(13.5))
            .foregroundStyle(Shad.mutedForeground)
            .lineLimit(2)
    }

    private func load(allowRemoteOnce: Bool) async {
        do {
            phase = .loaded(try await model.images.load(url, allowRemoteOnce: allowRemoteOnce))
        } catch ImageLoadError.remoteDisabled(let remote) {
            phase = .remote(remote)
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "Image unavailable")
        }
    }
}
