import SwiftUI

/// 根据会话恢复结果切换启动加载、登录页和聊天主页。
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isRestoringSession {
                ZStack {
                    AppColors.background.ignoresSafeArea()
                    ProgressView()
                        .tint(AppColors.secondaryText)
                }
            } else if session.isSignedIn {
                ChatView()
            } else {
                LoginView()
            }
        }
        .task {
            await session.restoreSession()
        }
    }
}
