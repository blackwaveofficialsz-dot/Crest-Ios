import SwiftUI

/// 新对话的欢迎内容和快捷问题入口。
struct ChatEmptyState: View {
    let suggestions: [ChatSuggestion]
    let subtitle: String
    let onSelectSuggestion: (ChatSuggestion) -> Void

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

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onSelectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 22)

                            Text(suggestion.title)
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .foregroundStyle(AppColors.primaryText)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 54)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 34)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: 560, minHeight: 500)
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
