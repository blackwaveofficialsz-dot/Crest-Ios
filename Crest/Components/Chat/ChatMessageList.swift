import SwiftUI
import UIKit

/// 按顺序展示当前会话消息，并为流式消息传递加载状态。
struct ChatMessageList: View {
    let messages: [ChatMessage]
    let streamingMessageID: String?
    let streamStatus: String
    let canRetry: Bool
    let onCopy: () -> Void
    let onRetry: (ChatMessage) -> Void
    let onAction: (ChatResponseAction) -> Void
    let onApproval: (ChatApproval, String) -> Void
    let playback: ChatTextPlayback

    var body: some View {
        VStack(spacing: 22) {
            ForEach(messages) { message in
                MessageRow(
                    message: message,
                    displayText: message.id == playback.messageID ? playback.visibleText : message.content,
                    isPlaying: message.id == playback.messageID && playback.hasPendingText,
                    loadingLabel: message.id == streamingMessageID ? streamStatus : nil,
                    canRetry: canRetry,
                    onCopy: onCopy,
                    onRetry: onRetry,
                    onAction: onAction,
                    onApproval: onApproval
                )
                .id(message.id)
            }
        }
        .frame(maxWidth: 680)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let displayText: String
    let isPlaying: Bool
    let loadingLabel: String?
    let canRetry: Bool
    let onCopy: () -> Void
    let onRetry: (ChatMessage) -> Void
    let onAction: (ChatResponseAction) -> Void
    let onApproval: (ChatApproval, String) -> Void

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 54)
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        AppColors.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if loadingLabel == nil, message.failure == nil,
                   let status = message.responseStatus,
                   status != "ok" {
                    ResponseStatusBadge(status: status)
                }

                if let failure = message.failure {
                    ChatFailureCard(
                        failure: failure,
                        canRetry: canRetry,
                        onRetry: { onRetry(message) }
                    )
                } else if message.content.isEmpty, let loadingLabel {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.secondaryText)
                        Text(loadingLabel)
                            .font(.footnote)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)
                } else if !displayText.isEmpty {
                    MarkdownMessageView(
                        content: displayText,
                        isStreaming: loadingLabel != nil || isPlaying
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if loadingLabel == nil, !isPlaying, !message.responseParts.isEmpty {
                    ForEach(Array(message.responseParts.enumerated()), id: \.offset) { _, part in
                        StructuredResponsePartView(part: part)
                    }
                }

                if loadingLabel == nil, !isPlaying, !message.responseActions.isEmpty {
                    ResponseActionButtons(actions: message.responseActions, onAction: onAction)
                        .padding(.top, 4)
                }

                if let approval = message.approval {
                    ChatApprovalCard(
                        approval: approval,
                        isEnabled: canRetry,
                        onDecision: { onApproval(approval, $0) }
                    )
                    .padding(.top, 4)
                }

                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   message.failure == nil, loadingLabel == nil, !isPlaying {
                    AssistantMessageActions(
                        content: message.content,
                        canRetry: canRetry,
                        onCopy: onCopy,
                        onRetry: { onRetry(message) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChatFailureCard: View {
    let failure: ChatFailure
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("回答生成失败", systemImage: "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.red)

            Text(failure.message)
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let code = failure.code, !code.isEmpty {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppColors.secondaryText)
            }

            if failure.retryable {
                Button(action: onRetry) {
                    Label("重新提问", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(!canRetry)
                .buttonStyle(.bordered)
                .tint(Color.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.22)) }
    }
}

private struct ChatApprovalCard: View {
    let approval: ChatApproval
    let isEnabled: Bool
    let onDecision: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(approval.toolLabel, systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)

            Text(approval.message)
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("拒绝", role: .destructive) { onDecision("reject") }
                    .buttonStyle(.bordered)
                Button("确认执行") { onDecision("approve") }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.chatSendButton)
            }
            .disabled(!isEnabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppColors.border) }
    }
}

private struct ResponseStatusBadge: View {
    let status: String

    private var label: String {
        switch status {
        case "partial": "结果不完整"
        case "empty": "暂无数据"
        case "unavailable": "数据暂不可用"
        case "failed": "分析失败"
        default: "结果状态未知"
        }
    }

    var body: some View {
        Label(label, systemImage: status == "failed" ? "exclamationmark.circle.fill" : "exclamationmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == "failed" ? Color.red : Color.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((status == "failed" ? Color.red : Color.orange).opacity(0.09), in: Capsule())
            .accessibilityLabel("分析结果：\(label)")
    }
}

private struct StructuredResponsePartView: View {
    let part: ChatResponsePart

    @ViewBuilder
    var body: some View {
        switch part.kind {
        case "summary":
            StructuredSummary(part: part)
        case "insights":
            StructuredInsights(part: part)
        case "notice":
            StructuredNotice(part: part)
        case "clarification":
            StructuredClarification(part: part)
        case "table":
            StructuredResponseTable(part: part)
        default:
            EmptyView()
        }
    }
}

private struct StructuredSummary: View {
    let part: ChatResponsePart

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = part.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let message = part.message, !message.isEmpty {
                Text(message).font(.subheadline).foregroundStyle(AppColors.secondaryText)
            }
            if let metrics = part.metrics, !metrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.label ?? metric.key)
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                            Text(formattedMetric(metric))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppColors.primaryText)
                        }
                    }
                }
            }
        }
        .structuredCard()
    }

    private func formattedMetric(_ metric: ChatResponseMetric) -> String {
        guard let decimal = Decimal(string: metric.value) else { return metric.value }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        let value = formatter.string(for: decimal) ?? metric.value
        switch metric.unit?.lowercased() {
        case "cny": return "¥\(value)"
        case "ratio": return "\(formatter.string(for: decimal * 100) ?? metric.value)%"
        case "order": return "\(value)单"
        case "store": return "\(value)家"
        case "hour": return "\(value)小时"
        case "person": return "\(value)人"
        default:
            return metric.unit.map { "\(value) \($0)" } ?? value
        }
    }
}

private struct StructuredInsights: View {
    let part: ChatResponsePart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = part.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            ForEach(Array((part.items ?? []).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon(for: item.statementType))
                        .foregroundStyle(color(for: item.statementType))
                        .frame(width: 18)
                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .structuredCard()
    }

    private func icon(for type: String) -> String {
        switch type {
        case "recommendation": "lightbulb"
        case "hypothesis": "questionmark.circle"
        default: "checkmark.circle"
        }
    }

    private func color(for type: String) -> Color {
        type == "recommendation" ? .orange : AppColors.chatSendButton
    }
}

private struct StructuredNotice: View {
    let part: ChatResponsePart

    private var color: Color {
        switch part.severity {
        case "error": .red
        case "warning": .orange
        default: AppColors.chatSendButton
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: part.severity == "error" ? "exclamationmark.octagon.fill" : "info.circle.fill")
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                if let title = part.title, !title.isEmpty {
                    Text(title).font(.subheadline.weight(.semibold))
                }
                Text(part.message ?? "")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2)) }
    }
}

private struct StructuredClarification: View {
    let part: ChatResponsePart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = part.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            Text(part.message ?? "")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .structuredCard()
    }
}

private extension View {
    func structuredCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppColors.border) }
    }
}

private struct StructuredResponseTable: View {
    let part: ChatResponsePart

    private var columns: [ChatResponseColumn] {
        let previewRows = part.previewRows ?? []
        return (part.columns ?? [])
            .filter { column in
                previewRows.contains { row in
                    guard let value = row[column.key] else { return false }
                    let text = value.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !text.isEmpty && text != "—"
                }
            }
            .enumerated()
            .sorted { lhs, rhs in
                let lhsTechnical = isTechnical(lhs.element)
                let rhsTechnical = isTechnical(rhs.element)
                return lhsTechnical == rhsTechnical ? lhs.offset < rhs.offset : !lhsTechnical
            }
            .map(\.element)
    }

    private var rows: [[String]] {
        (part.previewRows ?? []).map { row in
            columns.map { column in
                formattedValue(row[column.key], column: column)
            }
        }
    }

    var body: some View {
        MarkdownTable(
            headers: columns.map(\.label),
            rows: rows,
            title: part.title,
            previewRowCount: 3,
            totalRowCount: part.rowCount,
            columnWidths: columns.map(recommendedWidth)
        )
    }

    private func isTechnical(_ column: ChatResponseColumn) -> Bool {
        column.label.contains("_")
            || (column.label == column.key && column.label.unicodeScalars.allSatisfy(\.isASCII))
    }

    private func recommendedWidth(for column: ChatResponseColumn) -> CGFloat {
        if column.dataType == "decimal" || column.dataType == "integer" {
            return 112
        }

        let longestValue = (part.previewRows ?? [])
            .compactMap { $0[column.key]?.displayText.count }
            .max() ?? 0
        let longestText = max(column.label.count, longestValue)
        if longestText > 18 { return 220 }
        if longestText > 10 || isTechnical(column) { return 180 }
        return 144
    }

    private func formattedValue(_ value: ChatJSONValue?, column: ChatResponseColumn) -> String {
        guard let value else { return "—" }
        let text = value.displayText
        guard text != "—" else { return text }

        if column.key == "comparison_status" {
            switch text {
            case "comparable": return "可比"
            case "not_comparable": return "不可比"
            default: return "未知"
            }
        }

        guard column.dataType == "decimal" || column.dataType == "integer",
              let number = Decimal(string: text) else { return text }
        let formatted = Self.numberFormatter.string(for: number) ?? text
        switch column.unit?.lowercased() {
        case "cny": return "¥\(formatted)"
        case "ratio":
            return "\(Self.numberFormatter.string(for: number * 100) ?? text)%"
        case "order": return "\(formatted)单"
        case "store": return "\(formatted)家"
        case "hour": return "\(formatted)小时"
        case "period": return "\(formatted)期"
        case "product": return "\(formatted)种"
        case "item": return "\(formatted)件"
        case "person": return "\(formatted)人"
        default: return formatted
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        return formatter
    }()
}

private struct ResponseActionButtons: View {
    let actions: [ChatResponseAction]
    let onAction: (ChatResponseAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 8) {
                        Text(action.label)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppColors.chatSendButton)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        AppColors.chatSendButton.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.chatSendButton.opacity(0.2), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("继续完成当前查询")
            }
        }
    }
}

/// 助手回复下方的轻量操作栏，复制与分享直接使用 iOS 系统能力。
private struct AssistantMessageActions: View {
    let content: String
    let canRetry: Bool
    let onCopy: () -> Void
    let onRetry: () -> Void

    @State private var isCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: copyMessage) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(
                        isCopied ? AppColors.chatSendButton : AppColors.secondaryText
                    )
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isCopied ? "已复制" : "复制回复")

            ShareLink(item: content) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("分享回复")

            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canRetry)
            .accessibilityLabel("重试回复")
        }
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(AppColors.secondaryText)
        .buttonStyle(.plain)
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    private func copyMessage() {
        UIPasteboard.general.string = content
        onCopy()

        copyResetTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        copyResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                isCopied = false
            }
        }
    }
}
