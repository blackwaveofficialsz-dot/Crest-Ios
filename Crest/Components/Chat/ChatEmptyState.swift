import SwiftUI

/// 新对话的欢迎内容。
struct ChatEmptyState: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            CrestMark()
                .padding(.bottom, 22)

            Text("今天想一起处理什么？")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .padding(.top, 8)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: 560, minHeight: 500)
    }
}

/// 新对话时显示在输入框上方的快捷问题。
struct ChatSuggestionBar: View {
    let suggestions: [ChatSuggestion]
    let onSelectSuggestion: (ChatSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions) { suggestion in
                Button {
                    onSelectSuggestion(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.icon)
                            .frame(width: 20)
                        Text(suggestion.title)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
                    .background(
                        AppColors.surface,
                        in: RoundedRectangle(cornerRadius: 21, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 25)
        .padding(.bottom, 8)
        .background(AppColors.background)
    }
}

private struct CrestMark: View {
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.surface)
            Circle()
                .stroke(AppColors.border, lineWidth: 1)
            Text("C")
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.primaryText)
        }
        .frame(width: size, height: size)
        .shadow(color: AppColors.primaryText.opacity(0.1), radius: size * 0.42)
        .accessibilityHidden(true)
    }
}
