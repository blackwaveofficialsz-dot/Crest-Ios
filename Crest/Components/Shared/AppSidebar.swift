import SwiftUI

/// 可在多个业务页面复用的全屏会话侧边栏。
struct AppSidebar: View {
    @Binding var isPresented: Bool
    let dragTranslation: CGFloat
    let username: String
    let sessions: [ChatSessionSummary]
    let activeSessionID: String?
    let isLoading: Bool
    let onNewConversation: () -> Void
    let onOpenSearch: () -> Void
    let onSelectSession: (ChatSessionSummary) -> Void
    let onPinSession: (ChatSessionSummary) -> Void
    let onRenameSession: (ChatSessionSummary) -> Void
    let onDeleteSession: (ChatSessionSummary) -> Void
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let restingOffset = isPresented ? 0 : -width
            let horizontalOffset = min(0, max(-width, restingOffset + dragTranslation))
            let presentationProgress = width > 0 ? 1 + horizontalOffset / width : 0
            let uncoveredWidth = max(0, -horizontalOffset)

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    ZStack {
                        BackdropBlur()
                            .opacity(presentationProgress)
                            .allowsHitTesting(false)

                        Color.black.opacity(0.45 * presentationProgress)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: close)
                    }
                    .frame(width: uncoveredWidth)
                }
                .ignoresSafeArea()

                sidebarContent(
                    bottomInset: geometry.safeAreaInsets.bottom,
                    width: width
                )
                    .frame(width: width)
                    .ignoresSafeArea(edges: .bottom)
                    .offset(x: horizontalOffset)
            }
        }
        .allowsHitTesting(isPresented || dragTranslation > 0)
        .accessibilityHidden(!isPresented)
    }

    private func sidebarContent(bottomInset: CGFloat, width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Button(action: onNewConversation) {
                    Label("发起新对话", systemImage: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)

                Button {
                    onOpenSearch()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppColors.secondaryText)
                        Text("搜索对话内容")
                            .foregroundStyle(AppColors.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(AppColors.border)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                HStack {
                    Text("最近")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                    Spacer()
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("刷新历史记录")
                }
                .padding(.horizontal, 18)

                Group {
                    if isLoading && sessions.isEmpty {
                        ProgressView()
                            .tint(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 64)
                    } else if sessions.isEmpty {
                        Text("暂无对话记录")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 64)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(sessions) { item in
                                Button {
                                    onSelectSession(item)
                                } label: {
                                    sessionRow(item)
                                }
                                .buttonStyle(.plain)
                                .contentShape(
                                    .contextMenuPreview,
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                )
                                .contextMenu {
                                    Button {
                                        onPinSession(item)
                                    } label: {
                                        Label("固定", systemImage: "pin")
                                    }

                                    Button {
                                        onRenameSession(item)
                                    } label: {
                                        Label("重命名", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        onDeleteSession(item)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                } preview: {
                                    sessionRow(item, isContextMenuPreview: true)
                                        .frame(width: max(0, width - 20))
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            .padding(.top, 76)
            .padding(.bottom, 104 + bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .clipped()
        .foregroundStyle(AppColors.primaryText)
        .background {
            AppColors.sidebarBackground
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            headerBar
        }
        .overlay(alignment: .bottom) {
            accountBar(bottomInset: bottomInset)
        }
    }

    private func sessionRow(
        _ item: ChatSessionSummary,
        isContextMenuPreview: Bool = false
    ) -> some View {
        Text(item.title)
            .font(.body)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(
                isContextMenuPreview || item.sessionID == activeSessionID
                    ? AppColors.surface
                    : .clear,
                in: RoundedRectangle(
                    cornerRadius: isContextMenuPreview ? 24 : 7,
                    style: .continuous
                )
            )
    }

    private var headerBar: some View {
        HStack {
            Text("Crest")
                .font(.system(size: 26, weight: .semibold, design: .rounded))

            Spacer()

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("关闭侧边栏")
            .systemGlassCircleButton()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(AppColors.sidebarBackground)
    }

    /// 固定在底部的毛玻璃账户栏，并延伸覆盖设备安全区。
    private func accountBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Button {
                close()
                onOpenSettings()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppColors.secondaryText)

                    Text(username.isEmpty ? "账户" : username)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 30)
                .padding(.bottom, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("账户设置")
        }
        .padding(.bottom, bottomInset)
        .background {
            BackdropBlur()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.18), location: 0.2),
                            .init(color: .black.opacity(0.48), location: 0.45),
                            .init(color: .black.opacity(0.78), location: 0.7),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.21)) {
            isPresented = false
        }
    }
}

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

extension View {
    /// iOS 26 使用原生玻璃按钮，旧系统回退到原生描边圆形按钮。
    @ViewBuilder
    func systemGlassCircleButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(AppColors.primaryText)
        }
    }

    /// 保留强调色填充的系统玻璃圆形按钮。
    @ViewBuilder
    func systemGlassProminentCircleButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
        } else {
            buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
        }
    }
}
