import Foundation

@MainActor
/// 管理登录状态、令牌刷新和需要鉴权的请求重试。
final class SessionStore: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isRestoringSession: Bool
    @Published private(set) var username = ""
    @Published private(set) var userID = ""
    @Published private(set) var displayName = ""
    @Published private(set) var avatarData: Data?
    @Published private(set) var tenantID: String?
    @Published private(set) var role = ""
    @Published private(set) var hasPassword = false
    @Published private(set) var workspaceType: WorkspaceType = .personal
    @Published private(set) var activeWorkspaceID = "personal"
    @Published private(set) var workspaces: [WorkspaceSummary] = []
    @Published private(set) var isLoadingWorkspaces = false
    @Published private(set) var isSwitchingWorkspace = false

    private let api = APIClient()
    private let keychain = KeychainStore(service: "com.blackwave.crest")
    // 访问令牌只保存在内存，刷新令牌由 KeychainStore 持久保存。
    private var accessToken: String?
    private var refreshTask: Task<LoginResponse, Error>?
    private var didAttemptRestore = false
    private var sessionEpoch = 0

    private static let lastWorkspaceKeyPrefix = "com.blackwave.crest.lastWorkspace."

    init() {
        isRestoringSession = keychain.readRefreshToken() != nil
    }

    var accountDisplayName: String {
        displayName.isEmpty
            ? (username.isEmpty ? AppLocalization.string("Crest 用户") : username)
            : displayName
    }

    func signIn(phone: String, password: String) async throws {
        do {
            let response = try await api.login(phone: phone, password: password)
            try startSession(with: response)
            await loadAccountData()
        } catch {
            clearLocalSession()
            throw error
        }
    }

    func signInWithCode(verificationToken: String) async throws {
        do {
            let response = try await api.loginWithCode(verificationToken: verificationToken)
            try startSession(with: response)
            await loadAccountData()
        } catch {
            clearLocalSession()
            throw error
        }
    }

    func registerPersonal(verificationToken: String) async throws {
        do {
            let response = try await api.registerPersonal(verificationToken: verificationToken)
            try startSession(with: response)
            await loadAccountData()
        } catch {
            clearLocalSession()
            throw error
        }
    }

    func setInitialPassword(_ newPassword: String) async throws {
        let response = try await withAuthenticatedSession { token in
            try await api.setInitialPassword(newPassword, accessToken: token)
        }
        hasPassword = response.hasPassword
    }

    func loadAccountProfile() async throws {
        let profile = try await withAuthenticatedSession { token in
            try await api.accountProfile(accessToken: token)
        }
        username = profile.username
        displayName = profile.displayName
        avatarData = profile.hasAvatar
            ? try await withAuthenticatedSession { token in
                try await api.accountAvatar(accessToken: token)
            }
            : nil
    }

    func updateDisplayName(_ newDisplayName: String) async throws {
        let profile = try await withAuthenticatedSession { token in
            try await api.updateDisplayName(newDisplayName, accessToken: token)
        }
        displayName = profile.displayName
    }

    func updateAvatar(_ imageData: Data) async throws {
        _ = try await withAuthenticatedSession { token in
            try await api.uploadAccountAvatar(imageData, accessToken: token)
        }
        avatarData = imageData
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        _ = try await withAuthenticatedSession { token in
            try await api.changePassword(
                oldPassword: oldPassword,
                newPassword: newPassword,
                accessToken: token
            )
        }
    }

    /// 应用启动时使用 Keychain 中的刷新令牌恢复会话，仅尝试一次。
    func restoreSession() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        defer { isRestoringSession = false }

        guard keychain.readRefreshToken() != nil else {
            clearLocalSession()
            return
        }
        if await refreshStoredSession() {
            await loadAccountData()
        } else {
            accessToken = nil
            username = ""
            userID = ""
            displayName = ""
            avatarData = nil
            tenantID = nil
            role = ""
            hasPassword = false
            workspaceType = .personal
            activeWorkspaceID = "personal"
            workspaces = []
            isSignedIn = false
        }
    }

    func loadWorkspaces() async throws {
        guard !isLoadingWorkspaces else { return }
        isLoadingWorkspaces = true
        defer { isLoadingWorkspaces = false }

        let response = try await withAuthenticatedSession { token in
            try await api.listWorkspaces(accessToken: token)
        }
        workspaces = response.items
    }

    func acceptInvitation(code: String) async throws -> AcceptInvitationResponse {
        let response = try await withAuthenticatedSession { token in
            try await api.acceptInvitation(inviteToken: code, accessToken: token)
        }
        if let index = workspaces.firstIndex(where: {
            $0.workspaceID == response.workspace.workspaceID
        }) {
            workspaces[index] = response.workspace
        } else {
            workspaces.append(response.workspace)
        }
        return response
    }

    func switchWorkspace(to workspaceID: String) async throws {
        guard workspaceID != activeWorkspaceID, !isSwitchingWorkspace else { return }
        isSwitchingWorkspace = true
        defer { isSwitchingWorkspace = false }

        let response = try await withAuthenticatedSession { token in
            guard let refreshToken = keychain.readRefreshToken() else {
                throw APIError.invalidSession
            }
            return try await api.switchWorkspace(
                workspaceID: workspaceID,
                refreshToken: refreshToken,
                accessToken: token
            )
        }
        try startSession(with: response)
        rememberActiveWorkspace()
        await loadAccountData()
    }

    func signOut() {
        let refreshToken = keychain.readRefreshToken()
        clearLocalSession()

        Task {
            try? await AnalyticsCache.shared.clearAll()
            guard let refreshToken else { return }
            try? await api.logout(refreshToken: refreshToken)
        }
    }

    /// 提供有效访问令牌；遇到 401 时刷新令牌并将原请求重试一次。
    func withAuthenticatedSession<Result>(
        _ operation: (String) async throws -> Result
    ) async throws -> Result {
        if shouldRefreshAccessToken(accessToken) {
            _ = await refreshStoredSession()
        }
        guard let token = accessToken, isSignedIn else {
            throw APIError.invalidSession
        }

        do {
            return try await operation(token)
        } catch let error as APIError where error.isUnauthorized {
            let refreshed: Bool
            if accessToken != token {
                refreshed = true
            } else {
                refreshed = await refreshStoredSession()
            }
            guard refreshed, let retryToken = accessToken else {
                clearLocalSession()
                throw APIError.invalidSession
            }

            do {
                return try await operation(retryToken)
            } catch let retryError as APIError where retryError.isUnauthorized {
                clearLocalSession()
                throw APIError.invalidSession
            }
        }
    }

    private func startSession(with response: LoginResponse) throws {
        sessionEpoch += 1
        refreshTask?.cancel()
        refreshTask = nil
        try apply(response)
    }

    private func apply(_ response: LoginResponse) throws {
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw APIError.invalidSession
        }
        try keychain.saveRefreshToken(refreshToken)
        accessToken = response.token
        username = response.username
        userID = response.userID
        tenantID = response.tenantID
        role = response.role
        hasPassword = response.hasPassword
        workspaceType = response.workspaceType
        activeWorkspaceID = response.activeWorkspaceID
        isSignedIn = true
    }

    private func loadAccountData() async {
        do {
            try await loadWorkspaces()
            if await restoreRememberedWorkspaceIfNeeded() {
                return
            }
        } catch {}
        try? await loadAccountProfile()
    }

    private func restoreRememberedWorkspaceIfNeeded() async -> Bool {
        guard !userID.isEmpty,
              let rememberedWorkspaceID = UserDefaults.standard.string(
                  forKey: Self.lastWorkspaceKeyPrefix + userID
              )
        else {
            rememberActiveWorkspace()
            return false
        }
        guard rememberedWorkspaceID != activeWorkspaceID else { return false }
        guard workspaces.contains(where: { $0.workspaceID == rememberedWorkspaceID }) else {
            rememberActiveWorkspace()
            return false
        }

        do {
            try await switchWorkspace(to: rememberedWorkspaceID)
            return true
        } catch {
            return false
        }
    }

    private func rememberActiveWorkspace() {
        guard !userID.isEmpty else { return }
        UserDefaults.standard.set(
            activeWorkspaceID,
            forKey: Self.lastWorkspaceKeyPrefix + userID
        )
    }

    private func refreshStoredSession() async -> Bool {
        let epoch = sessionEpoch
        do {
            let response = try await refreshResponse()
            guard epoch == sessionEpoch else { return false }
            try apply(response)
            return true
        } catch {
            guard epoch == sessionEpoch else { return false }
            if let apiError = error as? APIError, apiError.invalidatesSession {
                clearLocalSession()
            }
            return false
        }
    }

    /// 复用正在执行的刷新任务，避免并发请求重复刷新同一会话。
    private func refreshResponse() async throws -> LoginResponse {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refreshToken = keychain.readRefreshToken() else {
            throw APIError.invalidSession
        }

        let task = Task {
            try await api.refreshSession(refreshToken: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func clearLocalSession() {
        sessionEpoch += 1
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        keychain.deleteSessionTokens()
        username = ""
        userID = ""
        displayName = ""
        avatarData = nil
        tenantID = nil
        role = ""
        hasPassword = false
        workspaceType = .personal
        activeWorkspaceID = "personal"
        workspaces = []
        isLoadingWorkspaces = false
        isSwitchingWorkspace = false
        isSignedIn = false
    }

    /// JWT 距离过期不足六小时则提前刷新，解析失败时交由服务端 401 兜底。
    private func shouldRefreshAccessToken(_ token: String?) -> Bool {
        guard let token else { return false }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return false }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiration = object["exp"] as? NSNumber
        else {
            return false
        }
        return expiration.doubleValue - Date().timeIntervalSince1970 <= 6 * 60 * 60
    }
}
