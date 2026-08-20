import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct EPUBWriterTests {
    private func entries(title: String, markdown: String) throws -> [String: String] {
        let data = try EPUBWriter.write(title: title, markdown: markdown)
        let archive = try Archive(data: data, accessMode: .read)
        var result: [String: String] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            result[entry.path] = String(decoding: bytes, as: UTF8.self)
        }
        return result
    }

    @Test func navigationTargetsRemainCorrectWhenTitleHeadingIsInserted() throws {
        let package = try entries(
            title: "Book title",
            markdown: "# Chapter one\n\nText.\n\n#### Detail"
        )
        let content = try #require(package["OEBPS/content.xhtml"])
        let navigation = try #require(package["OEBPS/nav.xhtml"])

        #expect(content.contains("id=\"heading-1\">Book title"))
        #expect(content.contains("id=\"heading-2\">Chapter one"))
        #expect(content.contains("id=\"heading-3\">Detail"))
        #expect(navigation.contains("content.xhtml#heading-2"))
        #expect(navigation.contains("content.xhtml#heading-3"))
        #expect(navigation.contains("<ol>\n<li><a href=\"content.xhtml#heading-3\""))
    }

    @Test func matchingDocumentTitleDoesNotCreateDuplicateHeading() throws {
        let package = try entries(title: "Book title", markdown: "# Book title\n\nText.")
        let content = try #require(package["OEBPS/content.xhtml"])
        let navigation = try #require(package["OEBPS/nav.xhtml"])

        #expect(content.components(separatedBy: ">Book title</h1>").count - 1 == 1)
        #expect(navigation.contains("content.xhtml#heading-1"))
    }
}
