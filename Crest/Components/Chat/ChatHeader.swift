import SwiftUI

/// 聊天页顶部导航，提供侧边栏、新对话和账户入口。
struct ChatHeader: View {
    let title: String
    let subtitle: String
    let onOpenSidebar: () -> Void
    let onNewConversation: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 160)
            }

            HStack(spacing: 2) {
                SidebarOpenButton(action: onOpenSidebar)

                Spacer()

                Button(action: onNewConversation) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("新对话")
                .systemGlassCircleButton()

                Button(action: onOpenSettings) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("账户")
                .systemGlassCircleButton()
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .padding(.horizontal, 10)
        .frame(height: 56)
    }
}
