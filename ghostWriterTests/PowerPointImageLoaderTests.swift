import Foundation
import Testing
@testable import ghostWriter

struct PowerPointImageLoaderTests {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
    private static let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\" fill=\"red\"/></svg>".utf8)

    private static func response(_ url: URL, type: String = "image/png", status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
    }

    @Test func remotePNGIsLoadedOncePerSource() async throws {
        actor Counter {
            var count = 0
            func increment() { count += 1 }
        }
        let counter = Counter()
        let source = "https://example.com/owl.png"
        let images = try await PowerPointImageLoader.load(sources: [source, source], sourceDirectory: nil, fetch: { url in
            await counter.increment()
            return (Self.png, Self.response(url))
        })
        #expect(images[source]?.data == Self.png)
        #expect(images[source]?.mediaType == "image/png")
        #expect(await counter.count == 1)
    }

    @Test func failedDownloadsDoNotDiscardOtherImages() async throws {
        let good = "https://example.com/good.png"
        let images = try await PowerPointImageLoader.load(
            sources: ["https://example.com/timeout.png", "https://example.com/missing.png", good],
            sourceDirectory: nil,
            fetch: { url in
            if url.lastPathComponent == "timeout.png" { throw URLError(.timedOut) }
            return (Self.png, Self.response(url, status: url.lastPathComponent == "missing.png" ? 404 : 200))
        })
        #expect(images.count == 1)
        #expect(images[good] != nil)
    }

    @Test func insecureAndCredentialedURLsAreNotFetched() async throws {
        let images = try await PowerPointImageLoader.load(
            sources: ["http://example.com/owl.png", "https://user:secret@example.com/owl.png", "file:///tmp/owl.png"],
            sourceDirectory: nil,
            fetch: { _ in
            Issue.record("A disallowed URL reached the downloader")
            throw URLError(.badURL)
        })
        #expect(images.isEmpty)
    }

    @Test func responseValidationRejectsInvalidOversizedAndDowngradedData() {
        let url = URL(string: "https://example.com/owl.png")!
        #expect(PowerPointImageLoader.validate(Data("not a png".utf8), response: Self.response(url)) == nil)
        #expect(PowerPointImageLoader.validate(Self.png, response: Self.response(url, type: "text/html")) == nil)
        #expect(PowerPointImageLoader.validate(Self.png, response: Self.response(url, status: 500)) == nil)
        #expect(PowerPointImageLoader.validate(Self.png, response: Self.response(URL(string: "http://example.com/owl.png")!)) == nil)
        #expect(PowerPointImageLoader.validate(Data(repeating: 0, count: PowerPointImageLoader.maximumBytes + 1), response: Self.response(url)) == nil)
    }

    @Test func SVGIsConvertedToValidatedPNG() async throws {
        let source = "https://example.com/owl.svg"
        let images = try await PowerPointImageLoader.load(sources: [source], sourceDirectory: nil,
            fetch: { (Self.svg, Self.response($0, type: "image/svg+xml")) },
            rasterizeSVG: { data in
                #expect(data == Self.svg)
                return Self.png
            })
        #expect(images[source]?.data == Self.png)
        #expect(images[source]?.mediaType == "image/png")

        let missingFallback = try await PowerPointImageLoader.load(sources: [source], sourceDirectory: nil,
            fetch: { (Self.svg, Self.response($0, type: "image/svg+xml")) },
            rasterizeSVG: { _ in throw PowerPointImageLoader.ImageError.renderingFailed })
        #expect(missingFallback.isEmpty)
    }

    @Test func unsafeSVGIsRejectedBeforeRendering() async throws {
        let unsafe = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>".utf8)
        let images = try await PowerPointImageLoader.load(sources: ["https://example.com/unsafe.svg"], sourceDirectory: nil,
            fetch: { (unsafe, Self.response($0, type: "image/svg+xml")) },
            rasterizeSVG: { _ in
                Issue.record("Unsafe SVG reached the renderer")
                return Self.png
            })
        #expect(images.isEmpty)
    }

    @Test func cancellationIsNotTreatedAsMissingImage() async {
        await #expect(throws: CancellationError.self) {
            _ = try await PowerPointImageLoader.load(sources: ["https://example.com/owl.png"], sourceDirectory: nil, fetch: { _ in
                throw CancellationError()
            })
        }
    }

    @Test func attachedSVGUsesSameRasterPipelineWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let assetDirectory = directory.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.svg.write(to: assetDirectory.appendingPathComponent("owl.svg"))
        let source = ".ghostwriter-assets-test/owl.svg"
        let images = try await PowerPointImageLoader.load(sources: [source], sourceDirectory: directory,
            fetch: { _ in
                Issue.record("Local SVG unexpectedly attempted a download")
                throw URLError(.badURL)
            }, rasterizeSVG: { data in
                #expect(data == Self.svg)
                return Self.png
            })
        #expect(images[source]?.data == Self.png)
    }
}
