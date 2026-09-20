import Foundation

/// 登录、注册和刷新会话共用的服务端响应。
struct LoginResponse: Decodable {
    let token: String
    let username: String
    let tenantID: String?
    let userID: String
    let role: String
    let hasPassword: Bool
    let workspaceType: WorkspaceType
    let activeWorkspaceID: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case token
        case username
        case tenantID = "tenant_id"
        case userID = "user_id"
        case role
        case hasPassword = "has_password"
        case workspaceType = "workspace_type"
        case activeWorkspaceID = "active_workspace_id"
        case refreshToken = "refresh_token"
    }
}

enum WorkspaceType: String, Decodable {
    case personal
    case tenant
}

struct WorkspaceSummary: Decodable, Identifiable {
    let workspaceID: String
    let workspaceType: WorkspaceType
    let name: String
    let tenantID: String?
    let role: String
    let isActive: Bool

    var id: String { workspaceID }

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case workspaceType = "workspace_type"
        case name
        case tenantID = "tenant_id"
        case role
        case isActive = "is_active"
    }
}

struct WorkspaceListResponse: Decodable {
    let activeWorkspaceID: String
    let items: [WorkspaceSummary]

    enum CodingKeys: String, CodingKey {
        case activeWorkspaceID = "active_workspace_id"
        case items
    }
}

private struct WorkspaceSwitchRequest: Encodable {
    let workspaceID: String
    let clientType = "mobile"
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case clientType = "client_type"
        case refreshToken = "refresh_token"
    }
}

private struct JoinTenantRequest: Encodable {
    let tenantCode: String

    enum CodingKeys: String, CodingKey {
        case tenantCode = "tenant_code"
    }
}

struct JoinTenantResponse: Decodable {
    let status: String
    let message: String
}

/// 短信验证码用途，原始值必须与后端接口约定一致。
enum PhoneVerificationPurpose: String, Encodable {
    case login
    case register = "personal_register"
    case resetPassword = "reset_password"
}

struct PhoneRegistrationStatusRequest: Encodable {
    let phone: String
    let countryCode: String
    let clientType: String

    enum CodingKeys: String, CodingKey {
        case phone
        case countryCode = "country_code"
        case clientType = "client_type"
    }
}

struct PhoneRegistrationStatusResponse: Decodable {
    let isRegistered: Bool
    let hasPassword: Bool

    enum CodingKeys: String, CodingKey {
        case isRegistered = "is_registered"
        case hasPassword = "has_password"
    }
}

struct VerificationCreateRequest: Encodable {
    let channel = "sms"
    let purpose: PhoneVerificationPurpose
    let target: String
    let inviteToken: String

    enum CodingKeys: String, CodingKey {
        case channel
        case purpose
        case target
        case inviteToken = "invite_token"
    }
}

struct VerificationCreateResponse: Decodable {
    let challengeID: String
    let message: String
    let expiresIn: Int
    let resendAfter: Int

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case message
        case expiresIn = "expires_in"
        case resendAfter = "resend_after"
    }
}

struct VerificationConfirmRequest: Encodable {
    let code: String
}

struct VerificationConfirmResponse: Decodable {
    let verificationToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
        case expiresIn = "expires_in"
    }
}

struct CodeLoginRequest: Encodable {
    let verificationToken: String
    let clientType: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
        case clientType = "client_type"
        case deviceName = "device_name"
    }
}

struct PersonalRegisterRequest: Encodable {
    let verificationToken: String
    let clientType: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
        case clientType = "client_type"
        case deviceName = "device_name"
    }
}

struct InitialPasswordRequest: Encodable {
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case newPassword = "new_password"
    }
}

struct InitialPasswordResponse: Decodable {
    let message: String
    let hasPassword: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case hasPassword = "has_password"
    }
}

struct AccountProfileResponse: Decodable {
    let userID: String
    let username: String
    let displayName: String
    let hasAvatar: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case hasAvatar = "has_avatar"
    }
}

private struct AccountProfileUpdateRequest: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct ChangePasswordRequest: Encodable {
    let oldPassword: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case oldPassword = "old_password"
        case newPassword = "new_password"
    }
}

struct ChangePasswordResponse: Decodable {
    let message: String
}

struct ResetPasswordRequest: Encodable {
    let verificationToken: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
        case newPassword = "new_password"
    }
}

struct ResetPasswordResponse: Decodable {
    let message: String
}

struct MobileSessionRequest: Encodable {
    let clientType = "mobile"
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientType = "client_type"
        case refreshToken = "refresh_token"
    }
}

private struct LogoutResponse: Decodable {
    let ok: Bool
}

/// 将网络层错误转换成可直接展示给用户的中文信息。
enum APIError: LocalizedError {
    case invalidResponse
    case invalidSession
    case unauthorized(String)
    case server(String)

    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    var invalidatesSession: Bool {
        switch self {
        case .invalidSession, .unauthorized:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应异常"
        case .invalidSession:
            return "登录状态无效，请重新登录"
        case .unauthorized(let message):
            return message
        case .server(let message):
            return message
        }
    }
}

/// 认证接口客户端，统一处理地址、JSON 编解码和 HTTP 错误。
struct APIClient {
    let baseURL: URL

    init(baseURL: URL = Self.defaultBaseURL) {
        self.baseURL = baseURL
    }

    private static var defaultBaseURL: URL {
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["CREST_API_BASE_URL"],
           let overrideURL = URL(string: value) {
            return overrideURL
        }
        return URL(string: "http://127.0.0.1:8010")!
#else
        return URL(string: "https://blackwave.org.cn/yuanji")!
#endif
    }

    func phoneRegistrationStatus(
        _ request: PhoneRegistrationStatusRequest
    ) async throws -> PhoneRegistrationStatusResponse {
        try await post(
            "/api/v1/auth/phone-status",
            body: request,
            fallbackError: "手机号状态查询失败"
        )
    }

    func login(phone: String, password: String) async throws -> LoginResponse {
        let body = [
            "identifier_type": "phone",
            "identifier": phone,
            "password": password,
            "client_type": "mobile",
            "device_name": "crest-ios",
        ]
        return try await post(
            "/api/v1/auth/login",
            body: body,
            fallbackError: "登录失败"
        )
    }

    func sendPhoneCode(
        phone: String,
        purpose: PhoneVerificationPurpose,
        inviteToken: String = ""
    ) async throws -> VerificationCreateResponse {
        try await post(
            "/api/v1/auth/verifications",
            body: VerificationCreateRequest(
                purpose: purpose,
                target: phone,
                inviteToken: inviteToken
            ),
            fallbackError: "验证码发送失败"
        )
    }

    func confirmPhoneCode(
        challengeID: String,
        code: String
    ) async throws -> VerificationConfirmResponse {
        try await post(
            "/api/v1/auth/verifications/\(challengeID)/confirm",
            body: VerificationConfirmRequest(code: code),
            fallbackError: "验证码校验失败"
        )
    }

    func loginWithCode(verificationToken: String) async throws -> LoginResponse {
        try await post(
            "/api/v1/auth/login/code",
            body: CodeLoginRequest(
                verificationToken: verificationToken,
                clientType: "mobile",
                deviceName: "crest-ios"
            ),
            fallbackError: "验证码登录失败"
        )
    }

    func registerPersonal(verificationToken: String) async throws -> LoginResponse {
        try await post(
            "/api/v1/auth/personal-register",
            body: PersonalRegisterRequest(
                verificationToken: verificationToken,
                clientType: "mobile",
                deviceName: "crest-ios"
            ),
            fallbackError: "个人账号创建失败"
        )
    }

    func setInitialPassword(
        _ newPassword: String,
        accessToken: String
    ) async throws -> InitialPasswordResponse {
        try await post(
            "/api/v1/auth/password/initial",
            body: InitialPasswordRequest(newPassword: newPassword),
            fallbackError: "密码设置失败",
            accessToken: accessToken
        )
    }

    func accountProfile(accessToken: String) async throws -> AccountProfileResponse {
        try await authenticatedJSONRequest(
            "/api/v1/auth/profile",
            accessToken: accessToken,
            fallbackError: "个人资料加载失败"
        )
    }

    func updateDisplayName(
        _ displayName: String,
        accessToken: String
    ) async throws -> AccountProfileResponse {
        try await authenticatedJSONRequest(
            "/api/v1/auth/profile",
            method: "PATCH",
            body: JSONEncoder().encode(AccountProfileUpdateRequest(displayName: displayName)),
            accessToken: accessToken,
            fallbackError: "昵称修改失败"
        )
    }

    func accountAvatar(accessToken: String) async throws -> Data? {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/auth/profile/avatar"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(from: data, response: http, fallbackError: "头像加载失败")
        }
        return data
    }

    func uploadAccountAvatar(
        _ imageData: Data,
        accessToken: String
    ) async throws -> AccountProfileResponse {
        let boundary = "CrestBoundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        return try await authenticatedJSONRequest(
            "/api/v1/auth/profile/avatar",
            method: "PUT",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            accessToken: accessToken,
            fallbackError: "头像上传失败"
        )
    }

    func changePassword(
        oldPassword: String,
        newPassword: String,
        accessToken: String
    ) async throws -> ChangePasswordResponse {
        try await post(
            "/api/v1/auth/change-password",
            body: ChangePasswordRequest(oldPassword: oldPassword, newPassword: newPassword),
            fallbackError: "密码修改失败",
            accessToken: accessToken
        )
    }

    func refreshSession(refreshToken: String) async throws -> LoginResponse {
        try await post(
            "/api/v1/auth/refresh",
            body: MobileSessionRequest(refreshToken: refreshToken),
            fallbackError: "登录状态刷新失败"
        )
    }

    func listWorkspaces(accessToken: String) async throws -> WorkspaceListResponse {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/auth/workspaces"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "工作空间加载失败（\(http.statusCode)）"
            if http.statusCode == 401 {
                throw APIError.unauthorized(message)
            }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(WorkspaceListResponse.self, from: data)
    }

    func joinTenant(
        tenantCode: String,
        accessToken: String
    ) async throws -> JoinTenantResponse {
        try await post(
            "/api/v1/auth/join-tenant",
            body: JoinTenantRequest(tenantCode: tenantCode),
            fallbackError: "加入团队失败",
            accessToken: accessToken
        )
    }

    func switchWorkspace(
        workspaceID: String,
        refreshToken: String,
        accessToken: String
    ) async throws -> LoginResponse {
        try await post(
            "/api/v1/auth/workspaces/switch",
            body: WorkspaceSwitchRequest(
                workspaceID: workspaceID,
                refreshToken: refreshToken
            ),
            fallbackError: "工作空间切换失败",
            accessToken: accessToken
        )
    }

    func logout(refreshToken: String) async throws {
        let response: LogoutResponse = try await post(
            "/api/v1/auth/logout",
            body: MobileSessionRequest(refreshToken: refreshToken),
            fallbackError: "退出登录失败"
        )
        guard response.ok else { throw APIError.invalidResponse }
    }

    func resetPassword(
        verificationToken: String,
        newPassword: String
    ) async throws -> ResetPasswordResponse {
        try await post(
            "/api/v1/auth/reset-password",
            body: ResetPasswordRequest(
                verificationToken: verificationToken,
                newPassword: newPassword
            ),
            fallbackError: "密码重置失败"
        )
    }

    /// 所有认证 POST 请求共用的最小请求管线。
    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        _ path: String,
        body: RequestBody,
        fallbackError: String,
        accessToken: String? = nil
    ) async throws -> ResponseBody {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

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

    private func authenticatedJSONRequest<ResponseBody: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        accessToken: String,
        fallbackError: String
    ) async throws -> ResponseBody {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(from: data, response: http, fallbackError: fallbackError)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func apiError(
        from data: Data,
        response: HTTPURLResponse,
        fallbackError: String
    ) -> APIError {
        let message = readErrorMessage(from: data) ?? "\(fallbackError)（\(response.statusCode)）"
        if response.statusCode == 401 {
            return .unauthorized(message)
        }
        return .server(message)
    }

    func readErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = object["detail"] as? String
        else {
            return nil
        }
        return detail
    }
}
