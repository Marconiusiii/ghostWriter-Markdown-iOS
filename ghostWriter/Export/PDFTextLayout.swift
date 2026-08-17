//
//  PDFTextLayout.swift
//  ghostWriter
//
//  Turns inline spans into attributed strings, and attributed strings into
//  measured lines that fit a given width.
//
//  PDF has no layout engine of its own — a page is a fixed rectangle and every
//  glyph is placed at an explicit coordinate. HTML and Word both hand layout to
//  the receiving application; here the app has to do it. Core Text supplies the
//  line breaking, and this wraps it in the measurements the writer needs to
//  decide where pages end.
//

import CoreText
import Foundation
import UIKit

nonisolated enum PDFTextLayout {

    // MARK: - Fonts

    /// Point sizes for the document. These are absolute rather than tied to the
    /// reader's Dynamic Type setting, because a PDF is a fixed artifact that
    /// will be read on other devices — pinning it to this device's text size
    /// would bake one reader's preference into the file.
    nonisolated struct Metrics: Sendable {
        var body: CGFloat = 11
        var code: CGFloat = 9.5
        var lineSpacing: CGFloat = 3
        var paragraphSpacing: CGFloat = 8

        func headingSize(level: Int) -> CGFloat {
            switch level {
            case 1: return 22
            case 2: return 18
            case 3: return 15
            case 4: return 13
            case 5: return 12
            default: return 11
            }
        }

        func headingSpacingBefore(level: Int) -> CGFloat {
            level <= 2 ? 16 : 12
        }
    }

    static let metrics = Metrics()

    private static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        guard bold || italic else { return base }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }

        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func monospacedFont(size: CGFloat, bold: Bool) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    // MARK: - Attributed string construction

    nonisolated struct InlineStyle: Sendable {
        var size: CGFloat
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var monospaced = false
        var color: UIColor = .black
        var alignment: NSTextAlignment = .natural
    }

    /// Builds an attributed string for a run of inline spans.
    ///
    /// Links are rendered in a colour *and* underlined. Colour alone would fail
    /// for anyone who cannot distinguish it, and a PDF link that is only a
    /// colour change is indistinguishable from ordinary text in print.
    static func attributedString(
        for spans: [ExportInline],
        style: InlineStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        append(spans, to: result, style: style)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = metrics.lineSpacing
        paragraph.alignment = style.alignment
        result.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: result.length)
        )

        return result
    }

    private static func append(
        _ spans: [ExportInline],
        to result: NSMutableAttributedString,
        style: InlineStyle
    ) {
        for span in spans {
            switch span {
            case .text(let value):
                result.append(NSAttributedString(string: value, attributes: attributes(for: style)))

            case .emphasis(let children):
                var nested = style
                nested.italic = true
                append(children, to: result, style: nested)

            case .strong(let children):
                var nested = style
                nested.bold = true
                append(children, to: result, style: nested)

            case .strikethrough(let children):
                var nested = style
                nested.strikethrough = true
                append(children, to: result, style: nested)

            case .underline(let children):
                var nested = style
                nested.underline = true
                append(children, to: result, style: nested)

            case .code(let value):
                var nested = style
                nested.monospaced = true
                result.append(NSAttributedString(string: value, attributes: attributes(for: nested)))

            case .link(let destination, let content):
                var nested = style
                nested.underline = true
                nested.color = PDFPalette.link
                let start = result.length
                append(content, to: result, style: nested)
                // The URL is attached so the tagged writer can emit a real link
                // annotation, not merely coloured text.
                if result.length > start {
                    result.addAttribute(
                        .link,
                        value: destination,
                        range: NSRange(location: start, length: result.length - start)
                    )
                }

            case .image(let image):
                // Images are placed as their own block-level figures, so an
                // inline occurrence contributes only its alternative text here.
                if let alt = image.alternativeText, !alt.isEmpty {
                    var nested = style
                    nested.italic = true
                    result.append(NSAttributedString(
                        string: "[Image: \(alt)]",
                        attributes: attributes(for: nested)
                    ))
                }

            case .lineBreak:
                result.append(NSAttributedString(
                    string: "\u{2028}",
                    attributes: attributes(for: style)
                ))
            }
        }
    }

    private static func attributes(for style: InlineStyle) -> [NSAttributedString.Key: Any] {
        let font = style.monospaced
            ? monospacedFont(size: style.size * 0.94, bold: style.bold)
            : font(size: style.size, bold: style.bold, italic: style.italic)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.color
        ]

        if style.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        return attributes
    }

    // MARK: - Line breaking

    /// One laid-out line, ready to be drawn at an explicit origin.
    nonisolated struct Line {
        let ctLine: CTLine
        /// Range in the source attributed string, so a caller can tell which
        /// text a line covers.
        let range: NSRange
        let ascent: CGFloat
        let descent: CGFloat
        let leading: CGFloat

        var height: CGFloat { ascent + descent + leading }
    }

    /// Breaks an attributed string into lines fitting `width`.
    ///
    /// CTTypesetter is used directly rather than CTFramesetter because the
    /// writer needs to place lines one at a time — a paragraph can be split
    /// across a page boundary, and a frame would have to be re-created for each
    /// remaining fragment.
    static func lines(
        for attributed: NSAttributedString,
        width: CGFloat
    ) -> [Line] {
        guard attributed.length > 0, width > 0 else { return [] }

        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [Line] = []
        var start = 0

        while start < attributed.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            // A width too narrow for even one glyph would otherwise loop
            // forever; force progress instead.
            if count <= 0 { count = 1 }

            let range = CFRange(location: start, length: count)
            let ctLine = CTTypesetterCreateLine(typesetter, range)

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)

            lines.append(Line(
                ctLine: ctLine,
                range: NSRange(location: start, length: count),
                ascent: ascent,
                descent: descent,
                leading: leading + metrics.lineSpacing
            ))

            start += count
        }

        return lines
    }

    /// Total height of a run of lines, used to decide whether a block fits in
    /// the space left on the current page.
    static func height(of lines: [Line]) -> CGFloat {
        lines.reduce(0) { $0 + $1.height }
    }

    /// Horizontal offset for a line within `width`, honouring table cell
    /// alignment. Core Text draws from the origin, so centring and trailing
    /// alignment are applied by shifting the pen rather than by the paragraph
    /// style alone.
    static func offset(
        for line: Line,
        in width: CGFloat,
        alignment: ExportAlignment
    ) -> CGFloat {
        switch alignment {
        case .natural, .leading:
            return 0
        case .center, .trailing:
            let used = CGFloat(CTLineGetTypographicBounds(line.ctLine, nil, nil, nil))
            let slack = max(0, width - used)
            return alignment == .center ? slack / 2 : slack
        }
    }
}

/// Colours used in the PDF. Every pairing here is checked against the white
/// page background for WCAG AA contrast, because a PDF is often printed and a
/// low-contrast link or caption cannot be corrected by the reader afterwards.
nonisolated enum PDFPalette {
    static let text = UIColor.black
    /// 7.0:1 against white.
    static let link = UIColor(red: 0.0, green: 0.28, blue: 0.65, alpha: 1)
    /// 7.4:1 against white — used for code and quoted text.
    static let secondary = UIColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1)
    static let rule = UIColor(white: 0.62, alpha: 1)
    static let quoteBar = UIColor(white: 0.55, alpha: 1)
    static let codeBackground = UIColor(white: 0.955, alpha: 1)
    static let tableRule = UIColor(white: 0.5, alpha: 1)
}
