import Foundation

/// Shared heading hierarchy for generated contents. Skipped levels never create
/// empty list items; a heading nests under the nearest preceding lower level.
nonisolated enum ExportTableOfContents {
    struct Node {
        var heading: ExportHeading
        var children: [Node] = []
    }

    static func tree(_ headings: [ExportHeading]) -> [Node] {
        var index = 0
        func level(parent: Int) -> [Node] {
            var result: [Node] = []
            while index < headings.count, headings[index].level > parent {
                let heading = headings[index]
                index += 1
                result.append(Node(heading: heading, children: level(parent: heading.level)))
            }
            return result
        }
        return level(parent: 0)
    }

    static func hasOpeningTitle(_ blocks: [ExportBlock]) -> Bool {
        if case .heading(1, let content)? = blocks.first { return !content.isEffectivelyEmpty }
        return false
    }

    static func html(_ headings: [ExportHeading]) -> String {
        guard !headings.isEmpty else { return "" }
        func list(_ nodes: [Node]) -> String {
            "<ul>" + nodes.map { node in
                "<li><a href=\"#\(node.heading.identifier)\">\(MarkdownRenderer.escape(node.heading.content.plainText))</a>"
                    + (node.children.isEmpty ? "" : list(node.children)) + "</li>"
            }.joined() + "</ul>"
        }
        return "<h2>Table of Contents</h2>" + list(tree(headings))
    }

    static func list(_ headings: [ExportHeading], pages: [String: Int]) -> ExportBlock {
        func items(_ nodes: [Node]) -> ExportList {
            ExportList(isOrdered: false, items: nodes.map { node in
                let heading = node.heading
                let label = heading.content.plainText + ", page " + String(pages[heading.identifier] ?? 1)
                return ExportListItem(content: [.link(destination: "#" + heading.identifier, content: [.text(label)])],
                                      children: node.children.isEmpty ? [] : [.list(items(node.children))])
            })
        }
        return .list(items(tree(headings)))
    }
}
