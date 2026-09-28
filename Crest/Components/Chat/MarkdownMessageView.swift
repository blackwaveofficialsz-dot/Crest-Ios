import SwiftUI
import UIKit

/// 将助手返回的 Markdown 拆成适合聊天页面展示的块级内容。
struct MarkdownMessageView: View {
    let content: String
    let isStreaming: Bool

    @State private var blockCache: MarkdownBlockCache

    init(content: String, isStreaming: Bool) {
        self.content = content
        self.isStreaming = isStreaming
        _blockCache = State(
            initialValue: MarkdownBlockCache(content: content, isStreaming: isStreaming)
        )
    }

    @ViewBuilder
    var body: some View {
        Group {
            if isStreaming {
                blocksView
            } else {
                blocksView
                    .textSelection(.enabled)
            }
        }
        .onChange(of: content) { _, newContent in
            blockCache.update(content: newContent, isStreaming: isStreaming)
        }
        .onChange(of: isStreaming) { _, newValue in
            blockCache.update(content: content, isStreaming: newValue)
        }
    }

    private var blocksView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blockCache.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(AppColors.primaryText)
        .tint(AppColors.chatSendButton)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            MarkdownInlineText(text)
                .font(.body)
                .lineSpacing(5)

        case .heading(let level, let text):
            MarkdownInlineText(text)
                .font(headingFont(level: level))
                .padding(.top, level == 1 ? 10 : level == 2 ? 8 : 6)
                .padding(.bottom, 2)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: 24, alignment: .trailing)
                        MarkdownInlineText(item)
                            .font(.body)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .orderedList(let start, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(start + offset).")
                            .foregroundStyle(AppColors.secondaryText)
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                        MarkdownInlineText(item)
                            .font(.body)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.secondaryText.opacity(0.55))
                    .frame(width: 3)
                MarkdownInlineText(text)
                    .font(.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

        case .code(let language, let code):
            MarkdownCodeBlock(language: language, code: code)

        case .table(let headers, let rows):
            if isStreaming {
                StreamingMarkdownTable(headers: headers, rows: rows)
            } else {
                MarkdownTable(headers: headers, rows: rows)
            }

        case .divider:
            Divider()
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            .system(size: 20, weight: .semibold)
        case 2:
            .system(size: 18, weight: .semibold)
        default:
            .system(size: 17, weight: .semibold)
        }
    }
}

private struct StreamingMarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            Text(source)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: true, vertical: false)
                .padding(12)
        }
        .scrollIndicators(.hidden)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        }
    }

    private var source: String {
        ([headers] + rows)
            .map { "| " + $0.joined(separator: " | ") + " |" }
            .joined(separator: "\n")
    }
}

private struct MarkdownInlineText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct MarkdownCodeBlock: View {
    let language: String?
    let code: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.isEmpty == false ? language! : "代码")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.4))
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "已复制" : "复制代码")
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(minHeight: 38)

            Divider()

            ScrollView(.horizontal) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 14, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(AppColors.primaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        }
    }
}

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]
    var title: String? = nil
    var previewRowCount = 10
    var totalRowCount: Int? = nil
    var columnWidths: [CGFloat]? = nil

    @State private var isExpanded = false

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    private var visibleRows: [[String]] {
        isExpanded ? rows : Array(rows.prefix(previewRowCount))
    }

    private var reportedRowCount: Int {
        max(totalRowCount ?? rows.count, rows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
            }

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cell(
                                value(at: column, in: headers),
                                column: column,
                                isHeader: true
                            )
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(AppColors.border)
                            .frame(height: 1)
                    }

                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(0..<columnCount, id: \.self) { column in
                                cell(
                                    value(at: column, in: row),
                                    column: column,
                                    isHeader: false
                                )
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if rowIndex < visibleRows.count - 1 {
                                Rectangle()
                                    .fill(AppColors.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .background(AppColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .scrollIndicators(.hidden)

            if totalRowCount != nil {
                Text("当前展示 \(visibleRows.count) / \(reportedRowCount) 行")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }

            if rows.count > previewRowCount {
                Button(isExpanded ? "收起" : expandButtonTitle) {
                    isExpanded.toggle()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppColors.chatSendButton)
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "只显示前十行" : "显示全部表格行")
            }
        }
    }

    private var expandButtonTitle: String {
        if reportedRowCount > rows.count {
            return "展开已返回的 \(rows.count) 行"
        }
        return "展开全部（\(rows.count) 行）"
    }

    private func value(at index: Int, in row: [String]) -> String {
        index < row.count ? row[index] : ""
    }

    private func cell(
        _ value: String,
        column: Int,
        isHeader: Bool
    ) -> some View {
        Text(value)
            .font(.system(size: 15, weight: isHeader ? .semibold : .regular))
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: width(for: column), alignment: .leading)
            .background(isHeader ? AppColors.surface : AppColors.background)
    }

    private func width(for column: Int) -> CGFloat {
        guard let columnWidths, column < columnWidths.count else {
            return column == 0 ? 168 : 144
        }
        return columnWidths[column]
    }
}
