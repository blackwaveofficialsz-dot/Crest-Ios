import Foundation

/// 侧边栏展示的对话历史摘要。
struct ChatSessionSummary: Decodable, Identifiable {
    let sessionID: String
    let title: String
    let isPinned: Bool
    let createdAt: String
    let updatedAt: String

    var id: String { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case title
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        title = try container.decode(String.self, forKey: .title)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

/// 服务端返回的单条历史消息。
struct ChatHistoryMessage: Decodable {
    private struct Metadata: Decodable {
        let agentResponse: ChatAgentResponse?
        let deliveryStatus: String?

        enum CodingKeys: String, CodingKey {
            case agentResponse = "agent_response"
            case deliveryStatus = "delivery_status"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // 历史消息可能来自旧协议；结构化回复损坏时忽略按钮，不影响正文加载。
            agentResponse = try? container.decode(ChatAgentResponse.self, forKey: .agentResponse)
            deliveryStatus = try? container.decode(String.self, forKey: .deliveryStatus)
        }
    }

    let id: String
    let role: String
    let content: String
    let createdAt: String
    let responseParts: [ChatResponsePart]
    let responseActions: [ChatResponseAction]
    let responseStatus: String?
    let failure: ChatFailure?

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        let metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
        let agentResponse = metadata?.agentResponse
        responseParts = agentResponse?.supportedParts ?? []
        responseActions = agentResponse?.supportedActions ?? []
        let deliveryStatus = metadata?.deliveryStatus == "completed" ? "ok" : metadata?.deliveryStatus
        responseStatus = agentResponse?.resultStatus ?? deliveryStatus
        failure = metadata?.deliveryStatus == "failed"
            ? ChatFailure(message: content, code: nil, retryable: true)
            : nil
    }
}

/// 打开历史会话时返回的完整对话内容。
struct ChatSessionDetail: Decodable {
    let sessionID: String
    let title: String
    let messages: [ChatHistoryMessage]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case title
        case messages
    }
}

/// 将服务端流式事件转换成页面可直接消费的类型。
enum ChatStreamEvent {
    case text(String)
    case parts([ChatResponsePart])
    case actions([ChatResponseAction])
    case responseStatus(String?)
    case cursor(String)
    case failure(ChatFailure)
    case approval(ChatApproval)
    case metadata(sessionID: String?)
    case stage(String)
    case done
}

private struct ChatRequest: Encodable {
    struct ForwardedProps: Encodable {
        let interaction: ChatInteraction?
        let afterEventID: String?

        enum CodingKeys: String, CodingKey {
            case interaction
            case afterEventID = "afterEventId"
        }
    }

    struct Message: Encodable {
        let id: String
        let role = "user"
        let content: String
    }

    let threadID: String
    let runID: String
    let messages: [Message]
    let interaction: ChatInteraction?
    let afterEventID: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case runID = "runId"
        case parentRunID = "parentRunId"
        case state
        case messages
        case tools
        case context
        case forwardedProps
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(runID, forKey: .runID)
        try container.encodeNil(forKey: .parentRunID)
        try container.encode([String: String](), forKey: .state)
        try container.encode(messages, forKey: .messages)
        try container.encode([String](), forKey: .tools)
        try container.encode([String](), forKey: .context)
        try container.encode(
            ForwardedProps(interaction: interaction, afterEventID: afterEventID),
            forKey: .forwardedProps
        )
    }
}

private struct ChatStreamState {
    let threadID: String
    let runID: String
    var textMessageID: String?
    var hasReceivedText = false
    var seenEventIDs: Set<String> = []
    var lastEventID: String?
}

private struct ParsedChatStreamEvent {
    let events: [ChatStreamEvent]
    let isTerminal: Bool
}

private struct AgentRunCancelRequest: Encodable {
    let runID: String
    let requestID: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case requestID = "request_id"
        case reason
    }
}

private struct AgentRunApprovalRequest: Encodable {
    let runID: String
    let requestID: String
    let decision: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case requestID = "request_id"
        case decision
        case note
    }
}

private struct ChatSessionUpdateRequest: Encodable {
    let title: String?
    let isPinned: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case isPinned = "is_pinned"
    }
}

/// 聊天、历史记录和流式响应接口。
extension APIClient {
    func listChatSessions(accessToken: String) async throws -> [ChatSessionSummary] {
        try await get(
            baseURL.appending(path: "api/v1/sessions"),
            accessToken: accessToken,
            fallbackError: "对话历史加载失败"
        )
    }

    func chatSessionDetail(
        sessionID: String,
        accessToken: String
    ) async throws -> ChatSessionDetail {
        try await get(
            baseURL
                .appending(path: "api/v1/sessions")
                .appending(path: sessionID),
            accessToken: accessToken,
            fallbackError: "对话加载失败"
        )
    }

    func deleteChatSession(
        sessionID: String,
        accessToken: String
    ) async throws {
        var request = URLRequest(
            url: baseURL
                .appending(path: "api/v1/sessions")
                .appending(path: sessionID)
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "对话删除失败（\(http.statusCode)）"
            if http.statusCode == 401 {
                throw APIError.unauthorized(message)
            }
            throw APIError.server(message)
        }
    }

    func updateChatSession(
        sessionID: String,
        title: String? = nil,
        isPinned: Bool? = nil,
        accessToken: String
    ) async throws -> ChatSessionSummary {
        var request = URLRequest(
            url: baseURL
                .appending(path: "api/v1/sessions")
                .appending(path: sessionID)
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatSessionUpdateRequest(title: title, isPinned: isPinned)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "对话更新失败（\(http.statusCode)）"
            if http.statusCode == 401 {
                throw APIError.unauthorized(message)
            }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(ChatSessionSummary.self, from: data)
    }

    func streamChat(
        message: String,
        sessionID: String,
        runID: String? = nil,
        userMessageID: String? = nil,
        afterEventID: String? = nil,
        interaction: ChatInteraction? = nil,
        accessToken: String,
        onEvent: (ChatStreamEvent) async -> Void
    ) async throws {
        try await streamAgentChat(
            message: message,
            sessionID: sessionID,
            runID: runID ?? UUID().uuidString,
            userMessageID: userMessageID ?? UUID().uuidString,
            afterEventID: afterEventID,
            interaction: interaction,
            accessToken: accessToken,
            onEvent: onEvent
        )
    }

    private func streamAgentChat(
        message: String,
        sessionID: String,
        runID: String,
        userMessageID: String,
        afterEventID: String?,
        interaction: ChatInteraction?,
        accessToken: String,
        onEvent: (ChatStreamEvent) async -> Void
    ) async throws {
        var streamState = ChatStreamState(threadID: sessionID, runID: runID)
        var lastEventID = afterEventID

        for attempt in 0..<3 {
            try Task.checkCancellation()
            let body = ChatRequest(
                threadID: sessionID,
                runID: runID,
                messages: [ChatRequest.Message(id: userMessageID, content: message)],
                interaction: interaction,
                afterEventID: lastEventID
            )
            var request = URLRequest(url: baseURL.appending(path: "api/v1/agui/runs"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            if let lastEventID {
                request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
            }
            request.httpBody = try JSONEncoder().encode(body)

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    var data = Data()
                    for try await byte in bytes { data.append(byte) }
                    let detail = readErrorMessage(from: data) ?? "消息发送失败（\(http.statusCode)）"
                    if http.statusCode == 401 { throw APIError.unauthorized(detail) }
                    throw APIError.server(detail)
                }
                guard http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else {
                    throw APIError.server("新对话接口未返回事件流")
                }

                var dataLines: [String] = []
                var frameID: String?
                var didComplete = false

                func flushFrame() async throws {
                    guard !dataLines.isEmpty else {
                        frameID = nil
                        return
                    }
                    let parsed = try parseChatEvent(dataLines.joined(separator: "\n"), state: &streamState)
                    if let frameID, let eventID = streamState.lastEventID, frameID != eventID {
                        throw APIError.server("事件游标与响应内容不一致")
                    }
                    if let eventID = streamState.lastEventID {
                        lastEventID = eventID
                        await onEvent(.cursor(eventID))
                    }
                    for event in parsed.events { await onEvent(event) }
                    didComplete = didComplete || parsed.isTerminal
                    dataLines.removeAll(keepingCapacity: true)
                    frameID = nil
                }

                for try await rawLine in bytes.lines {
                    try Task.checkCancellation()
                    // URLSession may preserve the CR from an SSE CRLF delimiter.
                    // Normalize it so a separator line is recognized and each event
                    // is decoded independently instead of concatenating many JSON objects.
                    let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                    if line.isEmpty {
                        try await flushFrame()
                        if didComplete { break }
                    } else if line.hasPrefix("id:") {
                        // AsyncBytes.lines may omit the empty SSE separator line.
                        // A new id still deterministically starts the next frame,
                        // so finish any pending data before accepting its cursor.
                        if !dataLines.isEmpty {
                            try await flushFrame()
                            if didComplete { break }
                        }
                        frameID = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                    }
                }
                if !didComplete { try await flushFrame() }
                if didComplete {
                    await onEvent(.done)
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError {
                throw error
            } catch {
                if attempt == 2 { throw error }
            }

            if attempt < 2 {
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 300 : 700))
            }
        }
        throw APIError.server("回复中断，请重新发送")
    }

    func cancelAgentRun(runID: String, accessToken: String) async throws {
        try await postAgentRunCommand(
            path: "api/v1/agent-runs/cancel",
            body: AgentRunCancelRequest(
                runID: runID,
                requestID: UUID().uuidString,
                reason: "user_cancelled"
            ),
            accessToken: accessToken,
            fallbackError: "停止回复失败"
        )
    }

    func decideAgentRun(
        runID: String,
        decision: String,
        accessToken: String
    ) async throws {
        try await postAgentRunCommand(
            path: "api/v1/agent-runs/approve-action",
            body: AgentRunApprovalRequest(
                runID: runID,
                requestID: UUID().uuidString,
                decision: decision,
                note: nil
            ),
            accessToken: accessToken,
            fallbackError: "提交确认失败"
        )
    }

    private func postAgentRunCommand<Body: Encodable>(
        path: String,
        body: Body,
        accessToken: String,
        fallbackError: String
    ) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "\(fallbackError)（\(http.statusCode)）"
            if http.statusCode == 401 { throw APIError.unauthorized(message) }
            throw APIError.server(message)
        }
    }

    private func get<ResponseBody: Decodable>(
        _ url: URL,
        accessToken: String,
        fallbackError: String
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "\(fallbackError)（\(http.statusCode)）"
            if http.statusCode == 401 {
                throw APIError.unauthorized(message)
            }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    /// 将标准 AG-UI 事件转换成页面现有的文本与阶段事件。
    private func parseChatEvent(
        _ raw: String,
        state: inout ChatStreamState
    ) throws -> ParsedChatStreamEvent {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw APIError.server("新对话事件不是有效 JSON") }
        guard let type = object["type"] as? String, !type.isEmpty
        else { throw APIError.server("新对话事件缺少 type") }
        guard let eventID = object["eventId"] as? String, !eventID.isEmpty
        else { throw APIError.server("新对话事件缺少 eventId") }
        guard let sequence = object["sequence"] as? Int, sequence >= 0
        else { throw APIError.server("新对话事件缺少有效 sequence") }
        guard let runID = object["runId"] as? String, !runID.isEmpty
        else { throw APIError.server("新对话事件缺少 runId") }
        guard runID == state.runID
        else { throw APIError.server("新对话事件 runId 不一致") }
        guard let threadID = object["threadId"] as? String, !threadID.isEmpty
        else { throw APIError.server("新对话事件缺少 threadId") }
        guard threadID == state.threadID
        else { throw APIError.server("新对话事件 threadId 不一致") }

        let eventIDParts = eventID.split(separator: ":", omittingEmptySubsequences: false)
        guard eventIDParts.count == 3,
              eventIDParts[0] == Substring(runID),
              eventIDParts[1] == Substring(String(sequence)),
              Int(eventIDParts[2]) != nil
        else { throw APIError.server("新对话事件 eventId 格式不正确") }

        guard state.seenEventIDs.insert(eventID).inserted else {
            return ParsedChatStreamEvent(events: [], isTerminal: false)
        }
        state.lastEventID = eventID

        switch type {
        case "RUN_STARTED":
            return ParsedChatStreamEvent(
                events: [.metadata(sessionID: state.threadID), .stage("正在处理")],
                isTerminal: false
            )
        case "TEXT_MESSAGE_START":
            guard let messageID = object["messageId"] as? String,
                  object["role"] as? String == "assistant"
            else {
                throw APIError.server("回复消息格式不匹配")
            }
            let separator: [ChatStreamEvent] = state.hasReceivedText ? [.text("\n\n")] : []
            state.textMessageID = messageID
            return ParsedChatStreamEvent(events: separator, isTerminal: false)
        case "TEXT_MESSAGE_CONTENT":
            guard let messageID = object["messageId"] as? String,
                  messageID == state.textMessageID,
                  let delta = object["delta"] as? String
            else {
                throw APIError.server("回复片段无法关联到当前消息")
            }
            state.hasReceivedText = state.hasReceivedText || !delta.isEmpty
            return ParsedChatStreamEvent(
                events: delta.isEmpty ? [] : [.text(delta)],
                isTerminal: false
            )
        case "TOOL_CALL_START":
            return ParsedChatStreamEvent(events: [.stage("正在查询数据")], isTerminal: false)
        case "STATE_SNAPSHOT":
            guard let snapshot = object["snapshot"] as? [String: Any] else {
                return ParsedChatStreamEvent(events: [], isTerminal: false)
            }
            if let approval = snapshot["approval"] as? [String: Any],
               let approvalID = approval["approval_id"] as? String,
               let toolLabel = approval["tool_label"] as? String,
               let message = approval["message"] as? String,
               let expiresAt = approval["expires_at"] as? String {
                return ParsedChatStreamEvent(
                    events: [.approval(ChatApproval(
                        approvalID: approvalID,
                        toolLabel: toolLabel,
                        message: message,
                        expiresAt: expiresAt,
                        runID: state.runID,
                        lastEventID: eventID
                    ))],
                    isTerminal: false
                )
            }
            guard let response = snapshot["agent_response"] as? [String: Any],
                  let responseData = try? JSONSerialization.data(withJSONObject: response),
                  let agentResponse = try? JSONDecoder().decode(ChatAgentResponse.self, from: responseData)
            else { return ParsedChatStreamEvent(events: [], isTerminal: false) }
            return ParsedChatStreamEvent(
                events: [
                    .parts(agentResponse.supportedParts),
                    .actions(agentResponse.supportedActions),
                    .responseStatus(agentResponse.resultStatus),
                ],
                isTerminal: false
            )
        case "TOOL_CALL_RESULT":
            if let content = object["content"] as? String,
               let data = content.data(using: .utf8),
               let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let label = result["label"] as? String,
               !label.isEmpty {
                return ParsedChatStreamEvent(events: [.stage(label)], isTerminal: false)
            }
            return ParsedChatStreamEvent(events: [], isTerminal: false)
        case "TOOL_CALL_ARGS", "TOOL_CALL_END", "TEXT_MESSAGE_END":
            return ParsedChatStreamEvent(events: [], isTerminal: false)
        case "RUN_ERROR":
            let message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = object["code"] as? String
            return ParsedChatStreamEvent(
                events: [.failure(ChatFailure(
                    message: message.flatMap { $0.isEmpty ? nil : $0 } ?? "消息处理失败",
                    code: code,
                    retryable: true
                ))],
                isTerminal: true
            )
        case "RUN_FINISHED":
            if let result = object["result"] as? [String: Any],
               result["status"] as? String == "cancelled" {
                return ParsedChatStreamEvent(events: [], isTerminal: true)
            }
            if let outcome = object["outcome"] as? [String: Any],
               outcome["type"] as? String == "interrupt" {
                return ParsedChatStreamEvent(events: [], isTerminal: true)
            }
            return ParsedChatStreamEvent(events: [], isTerminal: true)
        default:
            return ParsedChatStreamEvent(events: [], isTerminal: false)
        }
    }
}
