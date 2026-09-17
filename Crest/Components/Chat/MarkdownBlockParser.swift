import Foundation

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case unorderedList([String])
    case orderedList(start: Int, items: [String])
    case quote(String)
    case code(language: String?, content: String)
    case table(headers: [String], rows: [[String]])
    case divider
}

/// 缓存已经结束的块，流式更新时只重新解析尚未闭合的尾部内容。
struct MarkdownBlockCache {
    private(set) var blocks: [MarkdownBlock] = []

    private var source = ""
    private var committedBlocks: [MarkdownBlock] = []
    private var pendingSource = ""
    private var wasStreaming = false

    init(content: String, isStreaming: Bool) {
        update(content: content, isStreaming: isStreaming)
    }

    mutating func update(content: String, isStreaming: Bool) {
        guard content != source || isStreaming != wasStreaming else { return }

        if !isStreaming {
            source = content
            committedBlocks = []
            pendingSource = ""
            blocks = MarkdownBlockParser.parse(content)
            wasStreaming = false
            return
        }

        guard wasStreaming, content.hasPrefix(source) else {
            resetStreamingContent(content)
            return
        }

        pendingSource.append(contentsOf: content.dropFirst(source.count))
        source = content
        commitStableBlocks()
        blocks = committedBlocks + MarkdownBlockParser.parse(pendingSource)
    }

    private mutating func resetStreamingContent(_ content: String) {
        source = content
        committedBlocks = []
        pendingSource = content
        wasStreaming = true
        commitStableBlocks()
        blocks = committedBlocks + MarkdownBlockParser.parse(pendingSource)
    }

    private mutating func commitStableBlocks() {
        guard let boundary = Self.lastStableBoundary(in: pendingSource) else { return }

        committedBlocks.append(
            contentsOf: MarkdownBlockParser.parse(String(pendingSource[..<boundary]))
        )
        pendingSource = String(pendingSource[boundary...])
    }

    /// 代码围栏外的空行会结束当前块，空行之前的内容可以安全冻结。
    private static func lastStableBoundary(in source: String) -> String.Index? {
        var lineStart = source.startIndex
        var cursor = source.startIndex
        var boundary: String.Index?
        var isInsideCodeFence = false

        while cursor < source.endIndex {
            guard source[cursor] == "\n" else {
                cursor = source.index(after: cursor)
                continue
            }

            let nextLineStart = source.index(after: cursor)
            let line = source[lineStart..<cursor]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("```") {
                isInsideCodeFence.toggle()
            } else if line.isEmpty, !isInsideCodeFence {
                boundary = nextLineStart
            }

            lineStart = nextLineStart
            cursor = nextLineStart
        }

        return boundary
    }
}

enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let languageText = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(
                    .code(
                        language: languageText.isEmpty ? nil : languageText,
                        content: codeLines.joined(separator: "\n")
                    )
                )
                continue
            }

            if index + 1 < lines.count,
               let headers = tableCells(in: line),
               isTableSeparator(lines[index + 1], columnCount: headers.count) {
                flushParagraph()
                index += 2
                var rows: [[String]] = []
                while index < lines.count, let row = tableCells(in: lines[index]) {
                    rows.append(row)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if unorderedItem(in: trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count,
                      let item = unorderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if let firstItem = orderedItem(in: trimmed) {
                flushParagraph()
                var items = [firstItem.text]
                index += 1
                while index < lines.count,
                      let item = orderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item.text)
                    index += 1
                }
                blocks.append(.orderedList(start: firstItem.number, items: items))
                continue
            }

            if quoteText(in: trimmed) != nil {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count,
                      let quote = quoteText(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    quoteLines.append(quote)
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let remainder = line.dropFirst(level)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (level, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(in line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(in line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        guard let number = Int(line[..<dot]) else { return nil }
        let remainder = line[line.index(after: dot)...]
        guard remainder.first?.isWhitespace == true else { return nil }
        return (number, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func quoteText(in line: String) -> String? {
        guard line.first == ">" else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first,
              marker == "-" || marker == "_" || marker == "*"
        else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func tableCells(in line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.first == "|" { value.removeFirst() }
        if value.last == "|" { value.removeLast() }
        let cells = value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isTableSeparator(_ line: String, columnCount: Int) -> Bool {
        guard let cells = tableCells(in: line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            let markers = cell.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            return markers.count >= 3 && markers.allSatisfy { $0 == "-" }
        }
    }
}
