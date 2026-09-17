import SwiftUI

/// 底部消息编辑器，输入内容和焦点状态由聊天页统一管理。
struct ChatComposer: View {
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        // 外层负责底部区域背景，内层 HStack 是可见的圆角输入框。
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "给 Crest 发消息",
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.body)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
                .padding(.leading, 16)
                .padding(.vertical, 14)

                // 发送按钮和多行输入框底部对齐。
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.chatSendButtonText)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
                .accessibilityLabel("发送")
                .tint(AppColors.chatSendButton)
                .padding(.trailing, 2)
                .padding(.bottom, 4)
            }
            .frame(minHeight: 52)
            .background(
                AppColors.inputBackground,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        isFocused ? AppColors.secondaryText.opacity(0.8) : AppColors.border,
                        lineWidth: 1
                    )
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 8)
        }
        .frame(minHeight: 64)
        .background(AppColors.background)
    }
}
