import Foundation

/// 页面使用的统一消息模型，可由历史消息转换而来。
struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var content: String

    init(id: String = UUID().uuidString, role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    init?(historyMessage: ChatHistoryMessage) {
        guard historyMessage.role == "user" || historyMessage.role == "assistant" else {
            return nil
        }
        id = historyMessage.id
        role = historyMessage.role == "user" ? .user : .assistant
        content = historyMessage.content
    }
}

/// 驱动聊天页面原生错误弹窗的数据模型。
struct ChatAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let deletionTarget: ChatSessionSummary?
    let renameTarget: ChatSessionSummary?

    init(
        title: String,
        message: String,
        deletionTarget: ChatSessionSummary? = nil,
        renameTarget: ChatSessionSummary? = nil
    ) {
        self.title = title
        self.message = message
        self.deletionTarget = deletionTarget
        self.renameTarget = renameTarget
    }
}

/// 空白对话页中的快捷问题。
struct ChatSuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
}
