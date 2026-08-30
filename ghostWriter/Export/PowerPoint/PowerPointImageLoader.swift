import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// Resolves images before the synchronous ZIP writer runs. Nothing is persisted
/// to the document, and SVGs are rendered with scripts and networking disabled.
nonisolated enum PowerPointImageLoader {
    struct Image: Sendable {
        let data: Data
        let mediaType: String
    }

    static let maximumBytes = 10 * 1024 * 1024
    static let maximumTotalBytes = 40 * 1024 * 1024
    typealias Fetch = @Sendable (URL) async throws -> (Data, HTTPURLResponse)
    typealias Rasterize = @Sendable (Data) async throws -> Data

    static func load(
        sources: [String],
        sourceDirectory: URL?,
        fetch: Fetch = download,
        rasterizeSVG: Rasterize = rasterize
    ) async throws -> [String: Image] {
        var result: [String: Image] = [:]
        var seen = Set<String>()
        var totalBytes = 0
        for source in sources {
            try Task.checkCancellation()
            guard seen.insert(source).inserted else { continue }
            // Bound both export memory and work for documents with many URLs.
            guard seen.count <= 32, totalBytes < maximumTotalBytes else { break }
            do {
                let raw: Image
                if let url = URL(string: source), isAllowedRemoteURL(url) {
                    let (data, response) = try await fetch(url)
                    guard let validated = validate(data, response: response) else { continue }
                    raw = validated
                } else if let local = ExportImageResource.resolveManagedAsset(
                    source: source, sourceDirectory: sourceDirectory
                ), local.data.count <= maximumBytes {
                    raw = Image(data: local.data, mediaType: local.mediaType)
                } else {
                    continue
                }
                guard totalBytes + raw.data.count <= maximumTotalBytes else { continue }
                totalBytes += raw.data.count
                if raw.mediaType == "image/svg+xml" {
                    let png = try await rasterizeSVG(raw.data)
                    guard png.count <= maximumBytes,
                          totalBytes + png.count <= maximumTotalBytes,
                          validRaster(png, mediaType: "image/png") else { continue }
                    totalBytes += png.count
                    // Use the browser-rendered raster as the actual picture.
                    // SVG extension support varies between presentation readers,
                    // including how they interpret SVG CSS colors.
                    result[source] = Image(data: png, mediaType: "image/png")
                } else {
                    result[source] = raw
                }
            } catch {
                // An unavailable image must not prevent exporting the text.
                // Cancellation, however, must cancel the export itself.
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
            }
        }
        return result
    }

    static func isAllowedRemoteURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && !(url.host ?? "").isEmpty
            && url.user == nil && url.password == nil
    }

    static func validate(_ data: Data, response: HTTPURLResponse) -> Image? {
        guard let url = response.url, isAllowedRemoteURL(url),
              (200...299).contains(response.statusCode),
              !data.isEmpty, data.count <= maximumBytes else { return nil }
        let type = response.mimeType?.lowercased() ?? ""
        let mediaType: String
        switch type {
        case "image/png", "image/jpeg", "image/svg+xml": mediaType = type
        case "application/octet-stream", "":
            guard let inferred = ExportImageResource.mediaType(for: url.pathExtension) else { return nil }
            mediaType = inferred
        default: return nil
        }
        if mediaType == "image/svg+xml" {
            guard ExportImageResource.isSafeSVG(data) else { return nil }
        } else {
            guard validRaster(data, mediaType: mediaType) else { return nil }
        }
        return Image(data: data, mediaType: mediaType)
    }

    private static func validRaster(_ data: Data, mediaType: String) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 25_000_000 else { return false }
        return ExportImageResource.hasValidImageData(data, mediaType: mediaType)
    }

    private static func download(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("image/png, image/jpeg, image/svg+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSRedirects())
        guard let response = response as? HTTPURLResponse,
              let finalURL = response.url, isAllowedRemoteURL(finalURL),
              (200...299).contains(response.statusCode),
              response.expectedContentLength <= Int64(maximumBytes) else { throw ImageError.invalidImage }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw ImageError.invalidImage }
            data.append(byte)
        }
        return (data, response)
    }

    private static func rasterize(_ data: Data) async throws -> Data {
        try await SVGRasterizer().render(data)
    }

    enum ImageError: Error { case invalidImage, renderingFailed }
}

nonisolated private final class HTTPSRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(PowerPointImageLoader.isAllowedRemoteURL) == true ? request : nil)
    }
}

/// A private, offscreen WebKit page renders only a validated, self-contained SVG.
/// PDF capture works without inserting a web view into the user's interface.
@MainActor private final class SVGRasterizer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeout: Task<Void, Never>?

    func render(_ data: Data) async throws -> Data {
        try Task.checkCancellation()
        let size = Self.canvasSize(data)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        webView = view
        view.navigationDelegate = self
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}img{display:block;width:100%;height:100%;object-fit:contain}</style></head><body><img src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
        """
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    self?.finish(.failure(PowerPointImageLoader.ImageError.renderingFailed))
                }
                view.loadHTMLString(html, baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKPDFConfiguration()
        configuration.rect = webView.bounds
        configuration.allowTransparentBackground = true
        webView.createPDF(configuration: configuration) { [weak self] result in
            guard let self else { return }
            self.finish(result.flatMap { pdf in
                guard let png = Self.png(from: pdf) else {
                    return .failure(PowerPointImageLoader.ImageError.renderingFailed)
                }
                return .success(png)
            })
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }

    private static func canvasSize(_ data: Data) -> CGSize {
        let text = String(decoding: data, as: UTF8.self)
        var ratio = 4.0 / 3.0
        if let match = text.firstMatch(of: /viewBox\s*=\s*["']\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)\s*["']/),
           let width = Double(match.1), let height = Double(match.2),
           width.isFinite, height.isFinite, width > 0, height > 0 {
            ratio = min(20, max(0.05, width / height))
        } else if let root = text.firstMatch(of: /<svg\b[^>]*>/),
                  let widthMatch = root.0.firstMatch(of: /\swidth\s*=\s*["']([\d.]+)(?:px)?["']/),
                  let heightMatch = root.0.firstMatch(of: /\sheight\s*=\s*["']([\d.]+)(?:px)?["']/),
                  let width = Double(widthMatch.1), let height = Double(heightMatch.1),
                  width.isFinite, height.isFinite, width > 0, height > 0 {
            ratio = min(20, max(0.05, width / height))
        }
        return ratio >= 1 ? CGSize(width: 1600, height: 1600 / ratio)
            : CGSize(width: 1600 * ratio, height: 1600)
    }

    private static func png(from data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), let page = document.page(at: 1) else { return nil }
        let rect = page.getBoxRect(.mediaBox)
        guard rect.width > 0, rect.height > 0, rect.width <= 2048, rect.height <= 2048,
              let context = CGContext(data: nil, width: Int(ceil(rect.width)), height: Int(ceil(rect.height)),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
