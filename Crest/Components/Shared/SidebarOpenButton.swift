import SwiftUI

/// 聊天和搜索页面共用的系统侧边栏按钮。
struct SidebarOpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColors.primaryText)
                .frame(width: 22, height: 22)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("打开侧边栏")
        .systemGlassCircleButton()
    }
}
