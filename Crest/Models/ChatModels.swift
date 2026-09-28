import Foundation

/// Agent 返回的可继续操作。`clarify` 会携带候选标识，`prompt` 只发送提示词。
struct ChatResponseAction: Decodable, Identifiable, Equatable {
    struct Parameters: Decodable, Equatable {
        let candidateID: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case candidateID = "candidate_id"
            case message
        }
    }

    let actionID: String
    let kind: String
    let label: String
    let sourceTurnID: String?
    let params: Parameters?

    var id: String { actionID }

    enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case kind
        case label
        case sourceTurnID = "source_turn_id"
        case params
    }
}

struct ChatResponseColumn: Decodable {
    let key: String
    let label: String
    let dataType: String?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case dataType = "data_type"
        case unit
    }
}

struct ChatResponseMetric: Decodable {
    let key: String
    let label: String?
    let value: String
    let unit: String?
}

struct ChatResponseInsight: Decodable {
    let statementType: String
    let text: String
    let evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case statementType = "statement_type"
        case text
        case evidenceRefs = "evidence_refs"
    }
}

indirect enum ChatJSONValue: Decodable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case array([ChatJSONValue])
    case object([String: ChatJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ChatJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ChatJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                ChatJSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported table cell value"
                )
            )
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .number(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return values.map(\.displayText).joined(separator: ", ")
        case .object(let value):
            return value.keys.sorted().map { key in
                "\(key): \(value[key]?.displayText ?? "—")"
            }.joined(separator: ", ")
        case .null:
            return "—"
        }
    }
}

struct ChatResponsePart: Decodable {
    let kind: String
    let title: String?
    let message: String?
    let metrics: [ChatResponseMetric]?
    let items: [ChatResponseInsight]?
    let severity: String?
    let code: String?
    let reasonCode: String?
    let missingFields: [String]?
    let allowFreeText: Bool?
    let tableID: String?
    let rowCount: Int?
    let columns: [ChatResponseColumn]?
    let previewRows: [[String: ChatJSONValue]]?

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case message
        case metrics
        case items
        case severity
        case code
        case reasonCode = "reason_code"
        case missingFields = "missing_fields"
        case allowFreeText = "allow_free_text"
        case tableID = "table_id"
        case rowCount = "row_count"
        case columns
        case previewRows = "preview_rows"
    }
}

/// AG-UI 快照和历史消息共同使用的结构化回复片段。
struct ChatAgentResponse: Decodable {
    let version: Int
    let domain: String?
    let task: String?
    let resultStatus: String?
    let resultID: String?
    let sourceTurnID: String
    let parts: [ChatResponsePart]
    let actions: [ChatResponseAction]

    enum CodingKeys: String, CodingKey {
        case version
        case domain
        case task
        case resultStatus = "result_status"
        case resultID = "result_id"
        case sourceTurnID = "source_turn_id"
        case parts
        case actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        task = try container.decodeIfPresent(String.self, forKey: .task)
        resultStatus = try container.decodeIfPresent(String.self, forKey: .resultStatus)
        resultID = try container.decodeIfPresent(String.self, forKey: .resultID)
        sourceTurnID = try container.decode(String.self, forKey: .sourceTurnID)
        parts = try container.decodeIfPresent([ChatResponsePart].self, forKey: .parts) ?? []
        actions = try container.decodeIfPresent([ChatResponseAction].self, forKey: .actions) ?? []
    }

    var supportedParts: [ChatResponsePart] {
        guard version == 1, !sourceTurnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return parts.prefix(6).filter { part in
            switch part.kind {
            case "table":
                return !(part.columns?.isEmpty ?? true)
            case "summary":
                return !(part.metrics?.isEmpty ?? true)
                    || !(part.message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            case "insights":
                return !(part.items?.isEmpty ?? true)
            case "notice":
                return !(part.message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    && ["info", "warning", "error"].contains(part.severity ?? "")
            case "clarification":
                return !(part.message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            default:
                return false
            }
        }
    }

    var supportedActions: [ChatResponseAction] {
        guard version == 1, !sourceTurnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return actions.prefix(6).filter { action in
            let label = action.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = action.params?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !action.actionID.isEmpty, !label.isEmpty, !message.isEmpty,
                  action.sourceTurnID == sourceTurnID else { return false }

            if action.kind == "clarify" {
                return !(action.params?.candidateID?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            return action.kind == "prompt"
        }
    }
}

/// 点击确认候选后随下一次 AG-UI 请求回传的交互上下文。
struct ChatInteraction: Encodable {
    let kind = "clarification_choice"
    let sourceTurnID: String
    let candidateID: String

    enum CodingKeys: String, CodingKey {
        case kind
        case sourceTurnID = "source_turn_id"
        case candidateID = "candidate_id"
    }
}

struct ChatFailure: Equatable {
    let message: String
    let code: String?
    let retryable: Bool
}

struct ChatApproval: Equatable {
    let approvalID: String
    let toolLabel: String
    let message: String
    let expiresAt: String
    let runID: String
    let lastEventID: String
}

/// 页面使用的统一消息模型，可由历史消息转换而来。
struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var content: String
    var responseParts: [ChatResponsePart]
    var responseActions: [ChatResponseAction]
    var responseStatus: String?
    var failure: ChatFailure?
    var approval: ChatApproval?

    init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        responseParts: [ChatResponsePart] = [],
        responseActions: [ChatResponseAction] = [],
        responseStatus: String? = nil,
        failure: ChatFailure? = nil,
        approval: ChatApproval? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.responseParts = responseParts
        self.responseActions = responseActions
        self.responseStatus = responseStatus
        self.failure = failure
        self.approval = approval
    }

    init?(historyMessage: ChatHistoryMessage) {
        guard historyMessage.role == "user" || historyMessage.role == "assistant" else {
            return nil
        }
        id = historyMessage.id
        role = historyMessage.role == "user" ? .user : .assistant
        content = historyMessage.content
        responseParts = historyMessage.responseParts
        responseActions = historyMessage.responseActions
        responseStatus = historyMessage.responseStatus
        failure = historyMessage.failure
        approval = nil
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
