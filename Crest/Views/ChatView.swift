import SwiftUI

/// 聊天主页，负责消息流、历史会话、侧边栏和设置弹窗的状态编排。
struct ChatView: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var isComposerFocused: Bool
    @FocusState private var isSearchFocused: Bool

    private let api = APIClient()

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isWaitingForService = false
    @State private var streamStatus = "正在连接"
    @State private var streamingMessageID: String?
    @State private var activeSessionID: String?
    @State private var activeTitle = "新对话"
    @State private var history: [ChatSessionSummary] = []
    @State private var isLoadingHistory = false
    @State private var loadingHistoryWorkspaceID: String?
    @State private var isLoadingConversation = false
    @State private var isSidebarOpen = false
    @State private var sidebarDragTranslation: CGFloat = 0
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var isSettingPassword = false
    @State private var presentedAlert: ChatAlert?
    @State private var renameDraft = ""
    @State private var chatTask: Task<Void, Never>?
    @State private var pendingStreamText = ""
    @State private var streamFlushTask: Task<Void, Never>?
    @State private var isCopyToastPresented = false
    @State private var copyToastTask: Task<Void, Never>?

    private let sidebarEdgeWidth: CGFloat = 32
    private let sidebarDistanceThreshold: CGFloat = 0.34

    private var suggestions: [ChatSuggestion] {
        if session.tenantID == nil {
            return [
                ChatSuggestion(icon: "menucard", title: "帮我设计一份菜单结构"),
                ChatSuggestion(icon: "chart.pie", title: "如何控制餐厅食材成本"),
                ChatSuggestion(icon: "megaphone", title: "制定新店开业推广计划")
            ]
        }
        return [
            ChatSuggestion(icon: "chart.line.uptrend.xyaxis", title: "分析本月经营情况"),
            ChatSuggestion(icon: "exclamationmark.magnifyingglass", title: "找出最近的异常费用"),
            ChatSuggestion(icon: "doc.text", title: "生成一份经营摘要")
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isSearchPresented {
                    searchContent
                        .transition(.move(edge: .trailing))
                } else {
                    chatContent
                        .transition(.move(edge: .leading))
                }
                appSidebar
            }
            .simultaneousGesture(sidebarDragGesture(drawerWidth: geometry.size.width))
        }
        .animation(.easeInOut(duration: 0.28), value: isSearchPresented)
        .overlay(alignment: .top) {
            if isCopyToastPresented {
                CopyConfirmationToast()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isSidebarOpen)
        .alert(
            presentedAlert?.title ?? "",
            isPresented: Binding(
                get: { presentedAlert != nil },
                set: { if !$0 { presentedAlert = nil } }
            ),
            presenting: presentedAlert
        ) { alert in
            if let item = alert.renameTarget {
                TextField("对话名称", text: $renameDraft)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    performRenameConversation(item)
                }
                .disabled(
                    renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == item.title
                )
            } else if let item = alert.deletionTarget {
                Button("取消", role: .cancel) {}
                Button("确认", role: .destructive) {
                    performDeleteConversation(item)
                }
            } else {
                Button("好") {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .task(id: session.activeWorkspaceID) {
            resetForWorkspaceChange()
            await loadHistory()
        }
        .onDisappear {
            chatTask?.cancel()
            cancelPendingStreamText()
            copyToastTask?.cancel()
        }
        .sheet(isPresented: $isSettingsPresented) {
            AppSettingsSheet()
                .environmentObject(session)
            .presentationDetents([.fraction(0.78), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(45)
        }
        .sheet(isPresented: $isSettingPassword) {
            InitialPasswordView()
                .environmentObject(session)
                .presentationDetents([.medium])
        }
    }

    private var chatContent: some View {
        ZStack {
            ChatBackdrop()
                .ignoresSafeArea(.container)

            VStack(spacing: 0) {
                ChatHeader(
                    title: activeTitle,
                    subtitle: session.tenantID == nil ? "餐饮经营助手" : "经营助手",
                    onOpenSidebar: openSidebar,
                    onNewConversation: startNewConversation,
                    onOpenSettings: openSettings
                )

                Divider()
                    .overlay(AppColors.border)

                if session.tenantID == nil && !session.hasPassword {
                    Button {
                        isSettingPassword = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.badge.plus")
                            Text("完善密码")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.chatSendButton)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(AppColors.surface)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(AppColors.border)
                }

                conversation
                    .frame(maxHeight: .infinity)

                ChatComposer(
                    draft: $draft,
                    isFocused: $isComposerFocused,
                    canSend: canSend,
                    onSend: sendMessage
                )
            }
        }
    }

    private var appSidebar: some View {
        AppSidebar(
            isPresented: $isSidebarOpen,
            dragTranslation: sidebarDragTranslation,
            username: session.accountDisplayName,
            avatarData: session.avatarData,
            sessions: history,
            activeSessionID: activeSessionID,
            isLoading: isLoadingHistory,
            onNewConversation: startNewConversation,
            onOpenSearch: openSearch,
            onSelectSession: openConversation,
            onPinSession: pinConversation,
            onRenameSession: renameConversation,
            onDeleteSession: deleteConversation,
            onRefresh: {
                Task { await loadHistory() }
            },
            onOpenSettings: openSettings
        )
    }

    private var searchContent: some View {
        ConversationSearchView(
            isSearchFocused: $isSearchFocused,
            sessions: history,
            activeSessionID: activeSessionID,
            isLoading: isLoadingHistory,
            onOpenSidebar: openSidebar
        ) { item in
            openConversation(item)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoadingConversation {
                    ProgressView()
                        .tint(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 500)
                } else if messages.isEmpty {
                    ChatEmptyState(
                        suggestions: suggestions,
                        subtitle: "从一个餐饮经营问题开始"
                    ) { suggestion in
                        draft = suggestion.title
                        isComposerFocused = true
                    }
                } else {
                    ChatMessageList(
                        messages: messages,
                        streamingMessageID: streamingMessageID,
                        streamStatus: streamStatus,
                        canRetry: !isWaitingForService,
                        onCopy: showCopyConfirmation,
                        onRetry: retryResponse
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                isComposerFocused = false
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: isWaitingForService) { _, _ in
                scrollToBottom(with: proxy)
            }
            .onChange(of: isComposerFocused) { _, isFocused in
                if isFocused {
                    scrollToBottom(with: proxy)
                }
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isWaitingForService
    }

    private func showCopyConfirmation() {
        copyToastTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isCopyToastPresented = true
        }
        copyToastTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                isCopyToastPresented = false
            }
        }
    }

    /// 先插入空的助手消息占位，再把流式片段持续追加到同一条消息。
    private func sendMessage() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sendMessage(content, clearsDraft: true)
    }

    /// 当前接口没有“重新生成”能力，重试时按一次新消息重新发送原问题。
    private func retryResponse(_ assistantMessage: ChatMessage) {
        guard !isWaitingForService,
              let assistantIndex = messages.firstIndex(where: { $0.id == assistantMessage.id }),
              let userMessage = messages[..<assistantIndex].reversed().first(where: { message in
                  if case .user = message.role { return true }
                  return false
              }) else { return }

        sendMessage(userMessage.content, clearsDraft: false)
    }

    private func sendMessage(_ rawContent: String, clearsDraft: Bool) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isWaitingForService else { return }

        let requestSessionID = activeSessionID ?? UUID().uuidString
        let assistantID = UUID().uuidString
        let workspaceID = session.activeWorkspaceID
        activeSessionID = requestSessionID

        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(ChatMessage(role: .user, content: content))
            messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
            if clearsDraft {
                draft = ""
            }
            isWaitingForService = true
            streamingMessageID = assistantID
            streamStatus = "正在连接"
        }
        isComposerFocused = false

        chatTask?.cancel()
        cancelPendingStreamText()
        chatTask = Task {
            do {
                try await session.withAuthenticatedSession { token in
                    try await api.streamChat(
                        message: content,
                        sessionID: requestSessionID,
                        accessToken: token
                    ) { event in
                        await MainActor.run {
                            guard workspaceID == session.activeWorkspaceID else { return }
                            apply(event, to: assistantID)
                        }
                    }
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                finishStreamingMessage(assistantID)
                await loadHistory()
            } catch is CancellationError {
                finishStreamingMessage(assistantID)
            } catch {
                finishStreamingMessage(assistantID)
                presentedAlert = ChatAlert(
                    title: "发送失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func startNewConversation() {
        chatTask?.cancel()
        cancelPendingStreamText()
        dismissInputFocus()
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchPresented = false
            messages.removeAll()
            draft = ""
            isWaitingForService = false
            streamingMessageID = nil
            activeSessionID = nil
            activeTitle = "新对话"
        }
        closeSidebar()
    }

    private func openSidebar() {
        dismissInputFocus()
        withAnimation(sidebarOpenAnimation) {
            isSidebarOpen = true
            sidebarDragTranslation = 0
        }
        Task { await loadHistory() }
    }

    /// 关闭时仅响应左侧边缘右滑；展开后在侧栏任意位置左滑即可关闭。
    private func sidebarDragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height

                guard abs(horizontalDistance) > abs(verticalDistance) else { return }

                if isSidebarOpen {
                    guard horizontalDistance < 0 else { return }
                    sidebarDragTranslation = max(-drawerWidth, horizontalDistance)
                } else {
                    guard value.startLocation.x <= sidebarEdgeWidth,
                          horizontalDistance > 0 else { return }
                    dismissInputFocus()
                    sidebarDragTranslation = min(drawerWidth, horizontalDistance)
                }
            }
            .onEnded { value in
                guard sidebarDragTranslation != 0 else { return }

                let horizontalDistance = value.translation.width
                let predictedHorizontalDistance = value.predictedEndTranslation.width
                let distanceThreshold = drawerWidth * sidebarDistanceThreshold
                let projectedThreshold = drawerWidth * 0.5

                if isSidebarOpen {
                    let shouldClose = -horizontalDistance >= distanceThreshold
                        || -predictedHorizontalDistance >= projectedThreshold

                    withAnimation(shouldClose ? sidebarCloseAnimation : sidebarOpenAnimation) {
                        if shouldClose {
                            isSidebarOpen = false
                        }
                        sidebarDragTranslation = 0
                    }
                    return
                }

                let shouldOpen = horizontalDistance >= distanceThreshold
                    || predictedHorizontalDistance >= projectedThreshold

                withAnimation(shouldOpen ? sidebarOpenAnimation : sidebarSnapBackAnimation) {
                    if shouldOpen {
                        isSidebarOpen = true
                    }
                    sidebarDragTranslation = 0
                }

                if shouldOpen {
                    Task { await loadHistory() }
                }
            }
    }

    private func closeSidebar() {
        withAnimation(sidebarCloseAnimation) {
            isSidebarOpen = false
            sidebarDragTranslation = 0
        }
    }

    private func openSearch() {
        dismissInputFocus()
        withAnimation(.easeInOut(duration: 0.28)) {
            isSearchPresented = true
        }
        closeSidebar()
    }

    private func openSettings() {
        dismissInputFocus()
        closeSidebar()
        isSettingsPresented = true
    }

    private func pinConversation(_ item: ChatSessionSummary) {
        let workspaceID = session.activeWorkspaceID
        Task {
            do {
                let updated = try await session.withAuthenticatedSession { token in
                    try await api.updateChatSession(
                        sessionID: item.sessionID,
                        isPinned: !item.isPinned,
                        accessToken: token
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                replaceHistoryItem(updated)
            } catch is CancellationError {
                return
            } catch {
                guard workspaceID == session.activeWorkspaceID else { return }
                presentedAlert = ChatAlert(
                    title: item.isPinned ? "取消固定失败" : "固定失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func renameConversation(_ item: ChatSessionSummary) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            renameDraft = item.title
            presentedAlert = ChatAlert(
                title: "重命名对话",
                message: "输入新的对话名称",
                renameTarget: item
            )
        }
    }

    private func performRenameConversation(_ item: ChatSessionSummary) {
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != item.title else { return }
        let workspaceID = session.activeWorkspaceID

        Task {
            do {
                let updated = try await session.withAuthenticatedSession { token in
                    try await api.updateChatSession(
                        sessionID: item.sessionID,
                        title: title,
                        accessToken: token
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                replaceHistoryItem(updated)
            } catch is CancellationError {
                return
            } catch {
                guard workspaceID == session.activeWorkspaceID else { return }
                presentedAlert = ChatAlert(
                    title: "重命名失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func replaceHistoryItem(_ updated: ChatSessionSummary) {
        guard let index = history.firstIndex(where: { $0.sessionID == updated.sessionID }) else {
            return
        }
        history[index] = updated
        history.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
        if activeSessionID == updated.sessionID {
            activeTitle = updated.title
        }
    }

    private func deleteConversation(_ item: ChatSessionSummary) {
        Task { @MainActor in
            // 等待系统长按菜单完成收起，避免 Alert 的展示请求被菜单吞掉。
            try? await Task.sleep(for: .milliseconds(250))
            presentedAlert = ChatAlert(
                title: "要删除对话吗？",
                message: "这个对话将不再显示在此处，此操作还会从你的活动记录中删除相关的活动记录。",
                deletionTarget: item
            )
        }
    }

    private func performDeleteConversation(_ item: ChatSessionSummary) {
        let workspaceID = session.activeWorkspaceID

        Task {
            do {
                try await session.withAuthenticatedSession { token in
                    try await api.deleteChatSession(
                        sessionID: item.sessionID,
                        accessToken: token
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }

                history.removeAll { $0.sessionID == item.sessionID }
                if activeSessionID == item.sessionID {
                    startNewConversation()
                }
            } catch is CancellationError {
                return
            } catch {
                guard workspaceID == session.activeWorkspaceID else { return }
                presentedAlert = ChatAlert(
                    title: "删除失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// 加载侧边栏历史，并同步当前会话可能被服务端更新的标题。
    private func loadHistory() async {
        let workspaceID = session.activeWorkspaceID
        guard loadingHistoryWorkspaceID != workspaceID else { return }
        loadingHistoryWorkspaceID = workspaceID
        isLoadingHistory = true
        defer {
            if loadingHistoryWorkspaceID == workspaceID {
                loadingHistoryWorkspaceID = nil
                isLoadingHistory = false
            }
        }

        do {
            let loadedHistory = try await session.withAuthenticatedSession { token in
                try await api.listChatSessions(accessToken: token)
            }
            try Task.checkCancellation()
            guard workspaceID == session.activeWorkspaceID else { return }
            history = loadedHistory
            if let activeSessionID,
               let activeSession = history.first(where: { $0.sessionID == activeSessionID }) {
                activeTitle = activeSession.title
            }
        } catch is CancellationError {
            return
        } catch {
            guard workspaceID == session.activeWorkspaceID else { return }
            presentedAlert = ChatAlert(
                title: "历史记录加载失败",
                message: error.localizedDescription
            )
        }
    }

    /// 等待侧边栏收起动画结束后加载所选历史会话。
    private func openConversation(_ item: ChatSessionSummary) {
        chatTask?.cancel()
        cancelPendingStreamText()
        let waitsForSidebar = isSidebarOpen
        isSearchPresented = false
        closeSidebar()
        dismissInputFocus()
        let workspaceID = session.activeWorkspaceID

        chatTask = Task {
            do {
                if waitsForSidebar {
                    try await Task.sleep(for: .milliseconds(220))
                }
                isLoadingConversation = true
                let detail = try await session.withAuthenticatedSession { token in
                    try await api.chatSessionDetail(
                        sessionID: item.sessionID,
                        accessToken: token
                    )
                }
                try Task.checkCancellation()
                guard workspaceID == session.activeWorkspaceID else { return }
                activeSessionID = detail.sessionID
                activeTitle = detail.title
                messages = detail.messages.compactMap(ChatMessage.init(historyMessage:))
                isLoadingConversation = false
            } catch is CancellationError {
                isLoadingConversation = false
            } catch {
                isLoadingConversation = false
                presentedAlert = ChatAlert(
                    title: "对话加载失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func resetForWorkspaceChange() {
        chatTask?.cancel()
        cancelPendingStreamText()
        dismissInputFocus()
        messages = []
        draft = ""
        history = []
        loadingHistoryWorkspaceID = nil
        isLoadingHistory = false
        isWaitingForService = false
        isLoadingConversation = false
        streamingMessageID = nil
        activeSessionID = nil
        activeTitle = "新对话"
        isSearchPresented = false
        closeSidebar()
    }

    /// 将网络层流式事件合并进当前页面状态。
    private func apply(_ event: ChatStreamEvent, to messageID: String) {
        switch event {
        case .text(let text):
            pendingStreamText += text
            guard streamFlushTask == nil else { return }

            streamFlushTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                flushPendingStreamText(to: messageID)
            }
        case .metadata(let serverSessionID):
            if let serverSessionID, !serverSessionID.isEmpty {
                activeSessionID = serverSessionID
            }
        case .stage(let label):
            streamStatus = label
        case .done:
            break
        }
    }

    private func finishStreamingMessage(_ messageID: String) {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        flushPendingStreamText(to: messageID)

        if let index = messages.firstIndex(where: { $0.id == messageID }),
           messages[index].content.isEmpty {
            messages.remove(at: index)
        }
        isWaitingForService = false
        if streamingMessageID == messageID {
            streamingMessageID = nil
        }
    }

    private func flushPendingStreamText(to messageID: String) {
        let text = pendingStreamText
        pendingStreamText = ""
        streamFlushTask = nil

        guard !text.isEmpty,
              let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].content += text
    }

    private func cancelPendingStreamText() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        pendingStreamText = ""
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = messages.last?.id else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func dismissInputFocus() {
        isComposerFocused = false
        isSearchFocused = false
    }

    private var sidebarOpenAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.84, blendDuration: 0)
    }

    private var sidebarCloseAnimation: Animation {
        .easeIn(duration: 0.21)
    }

    private var sidebarSnapBackAnimation: Animation {
        .spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0)
    }
}

private struct CopyConfirmationToast: View {
    var body: some View {
        Label("已复制到剪贴板", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.primaryText)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(AppColors.surface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppColors.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .accessibilityLabel("已复制到剪贴板")
    }
}

#Preview {
    ChatView()
        .environmentObject(SessionStore())
}
