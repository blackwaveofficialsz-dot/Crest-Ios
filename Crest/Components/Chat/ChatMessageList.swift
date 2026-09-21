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
    let playback: ChatTextPlayback

    var body: some View {
        LazyVStack(spacing: 22) {
            ForEach(messages) { message in
                MessageRow(
                    message: message,
                    displayText: message.id == playback.messageID ? playback.visibleText : message.content,
                    isPlaying: message.id == playback.messageID && playback.hasPendingText,
                    loadingLabel: message.id == streamingMessageID ? streamStatus : nil,
                    canRetry: canRetry,
                    onCopy: onCopy,
                    onRetry: onRetry
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
                if message.content.isEmpty, let loadingLabel {
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
                } else {
                    MarkdownMessageView(
                        content: displayText,
                        isStreaming: loadingLabel != nil || isPlaying
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   loadingLabel == nil, !isPlaying {
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
