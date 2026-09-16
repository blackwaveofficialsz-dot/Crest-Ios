import SwiftUI

/// 从底部展示的账户和主题设置面板。
struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.systemColorScheme) private var systemColorScheme
    @EnvironmentObject private var session: SessionStore
    @AppStorage(AppTheme.storageKey) private var selectedTheme = AppTheme.dark.rawValue
    @State private var workspaceError: String?

    private var displayName: String {
        session.username.isEmpty ? "Crest 用户" : session.username
    }

    private var initials: String {
        String(displayName.prefix(1)).uppercased()
    }

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .dark
    }

    /// “跟随系统”使用捕获的真实系统主题，其他选项使用用户指定主题。
    private var resolvedColorScheme: ColorScheme {
        theme.colorScheme ?? systemColorScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("设置")
                            .font(.title2.weight(.semibold))

                        Spacer()

                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("关闭设置")
                        .systemGlassProminentCircleButton()
                        .tint(.blue)
                    }

                    VStack(spacing: 12) {
                        Text(initials)
                            .font(.system(size: 32, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 82, height: 82)
                            .background(Color.accentColor, in: Circle())

                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 30)

                    settingsSection(title: "账户") {
                        settingsRow(
                            icon: "person.crop.circle",
                            title: "账户",
                            value: displayName
                        )
                    }

                    settingsSection(title: "工作空间") {
                        if session.workspaces.isEmpty && session.isLoadingWorkspaces {
                            ProgressView()
                                .tint(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 58)
                        } else {
                            ForEach(Array(session.workspaces.enumerated()), id: \.element.id) { index, workspace in
                                if index > 0 {
                                    Divider()
                                        .overlay(AppColors.border)
                                        .padding(.leading, 58)
                                }

                                Button {
                                    switchWorkspace(to: workspace.workspaceID)
                                } label: {
                                    workspaceRow(workspace)
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    workspace.workspaceID == session.activeWorkspaceID
                                        || session.isSwitchingWorkspace
                                )
                            }
                        }
                    }

                    settingsSection(title: "主题") {
                        Menu {
                            Picker("外观", selection: $selectedTheme) {
                                ForEach(AppTheme.allCases) { option in
                                    Label(option.title, systemImage: option.systemImage)
                                        .tag(option.rawValue)
                                }
                            }
                        } label: {
                            settingsRow(
                                icon: theme.systemImage,
                                title: "外观",
                                value: theme.title,
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            Button {
                dismiss()
                session.signOut()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        AppColors.surface,
                        in: RoundedRectangle(cornerRadius: 45, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .foregroundStyle(AppColors.primaryText)
        .background(AppColors.background.ignoresSafeArea())
        .preferredColorScheme(resolvedColorScheme)
        .tint(.blue)
        .task {
            do {
                try await session.loadWorkspaces()
            } catch {
                workspaceError = error.localizedDescription
            }
        }
        .alert(
            "工作空间切换失败",
            isPresented: Binding(
                get: { workspaceError != nil },
                set: { if !$0 { workspaceError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(workspaceError ?? "请稍后重试")
        }
    }

    /// 统一设置分区标题、间距和圆角容器。
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.secondaryText)
                .padding(.leading, 4)

            VStack(spacing: 0, content: content)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.bottom, 26)
    }

    /// 统一设置行的图标、标题、值和下拉指示样式。
    private func settingsRow(
        icon: String,
        title: String,
        value: String? = nil,
        titleColor: Color = AppColors.primaryText,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(titleColor)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(titleColor)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.tertiaryText)
            }
        }
        .font(.body)
        .frame(minHeight: 58)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func workspaceRow(_ workspace: WorkspaceSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: workspace.workspaceType == .personal ? "person.crop.circle" : "building.2")
                .font(.system(size: 19, weight: .medium))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.name)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)

                Text(workspace.workspaceType == .personal ? "个人账号" : workspace.role)
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if session.isSwitchingWorkspace
                && workspace.workspaceID != session.activeWorkspaceID {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppColors.secondaryText)
            } else if workspace.workspaceID == session.activeWorkspaceID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.body)
        .frame(minHeight: 62)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func switchWorkspace(to workspaceID: String) {
        Task {
            do {
                try await session.switchWorkspace(to: workspaceID)
            } catch {
                workspaceError = error.localizedDescription
            }
        }
    }
}
