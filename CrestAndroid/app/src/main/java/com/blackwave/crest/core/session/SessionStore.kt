package com.blackwave.crest.core.session

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.blackwave.crest.core.model.LoginResponse
import com.blackwave.crest.core.model.WorkspaceSummary
import com.blackwave.crest.core.network.ApiClient
import com.blackwave.crest.core.network.ApiException
import com.blackwave.crest.core.security.SecureTokenStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class SessionUser(
    val username: String,
    val displayName: String,
    val userId: String,
    val tenantId: String?,
    val role: String,
    val hasPassword: Boolean,
    val workspaceType: String,
    val activeWorkspaceId: String,
)

sealed interface SessionState {
    data object Restoring : SessionState
    data object SignedOut : SessionState
    data class SignedIn(val user: SessionUser) : SessionState
    data class RestoreError(val message: String) : SessionState
}

class SessionStore(
    context: Context,
    val api: ApiClient = ApiClient(),
) {
    private val tokenStore = SecureTokenStore(context.applicationContext)
    private val refreshMutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var state by mutableStateOf<SessionState>(SessionState.Restoring)
        private set
    var workspaces by mutableStateOf<List<WorkspaceSummary>>(emptyList())
        private set
    var isLoadingWorkspaces by mutableStateOf(false)
        private set
    var workspaceError by mutableStateOf<String?>(null)
        private set
    var avatarData by mutableStateOf<ByteArray?>(null)
        private set

    private var accessToken: String? = null

    suspend fun restore() {
        state = SessionState.Restoring
        val refreshToken = tokenStore.read()
        if (refreshToken == null) {
            state = SessionState.SignedOut
            return
        }
        try {
            applySession(api.refreshSession(refreshToken), refreshToken)
            loadWorkspaces()
            runCatching { loadAccountProfile() }
        } catch (error: ApiException) {
            if (error.isUnauthorized) {
                clearLocalSession()
            } else {
                state = SessionState.RestoreError(error.message)
            }
        } catch (_: Exception) {
            state = SessionState.RestoreError("暂时无法连接服务器，请检查网络后重试。")
        }
    }

    suspend fun signIn(phone: String, password: String) {
        applySession(api.login(phone, password), null)
        loadWorkspaces()
        runCatching { loadAccountProfile() }
    }

    suspend fun signInWithCode(verificationToken: String) {
        applySession(api.loginWithCode(verificationToken), null)
        loadWorkspaces()
        runCatching { loadAccountProfile() }
    }

    suspend fun registerPersonal(verificationToken: String) {
        applySession(api.registerPersonal(verificationToken), null)
        loadWorkspaces()
        runCatching { loadAccountProfile() }
    }

    suspend fun <T> authenticated(block: suspend (String) -> T): T {
        val firstToken = currentAccessToken(forceRefresh = false)
        return try {
            block(firstToken)
        } catch (error: ApiException) {
            if (!error.isUnauthorized) throw error
            val refreshedToken = currentAccessToken(forceRefresh = true)
            try {
                block(refreshedToken)
            } catch (second: ApiException) {
                if (second.isUnauthorized) expireSession()
                throw second
            }
        }
    }

    suspend fun loadWorkspaces() {
        if (state !is SessionState.SignedIn) return
        isLoadingWorkspaces = true
        workspaceError = null
        try {
            val response = authenticated { api.listWorkspaces(it) }
            workspaces = response.items
        } catch (error: Exception) {
            workspaceError = error.userMessage("工作空间加载失败")
        } finally {
            isLoadingWorkspaces = false
        }
    }

    suspend fun loadAccountProfile() {
        val profile = authenticated { api.accountProfile(it) }
        updateSignedInUser {
            it.copy(username = profile.username, displayName = profile.displayName)
        }
        avatarData = if (profile.hasAvatar) {
            authenticated { api.accountAvatar(it) }
        } else {
            null
        }
    }

    suspend fun updateDisplayName(displayName: String) {
        val normalized = displayName.trim()
        require(normalized.length in 1..30) { "昵称长度需为 1 至 30 个字符" }
        val profile = authenticated { api.updateDisplayName(normalized, it) }
        updateSignedInUser { user ->
            user.copy(username = profile.username, displayName = profile.displayName)
        }
    }

    suspend fun setInitialPassword(newPassword: String) {
        require(newPassword.length in 7..16) { "密码长度需为 7 至 16 位" }
        val response = authenticated { api.setInitialPassword(newPassword, it) }
        updateSignedInUser { it.copy(hasPassword = response.hasPassword) }
    }

    suspend fun changePassword(oldPassword: String, newPassword: String) {
        require(oldPassword.isNotEmpty()) { "请输入当前密码" }
        require(newPassword.length in 7..16) { "密码长度需为 7 至 16 位" }
        authenticated { api.changePassword(oldPassword, newPassword, it) }
    }

    suspend fun acceptInvitation(inviteToken: String): String {
        val normalized = inviteToken.trim()
        require(normalized.isNotEmpty()) { "请输入邀请码" }
        val response = authenticated { api.acceptInvitation(normalized, it) }
        workspaces = workspaces
            .filterNot { it.workspaceId == response.workspace.workspaceId }
            .plus(response.workspace)
        return response.message
    }

    suspend fun switchWorkspace(workspaceId: String) {
        val refreshToken = tokenStore.read() ?: throw ApiException(message = "登录状态无效，请重新登录")
        val response = authenticated { token ->
            api.switchWorkspace(workspaceId, refreshToken, token)
        }
        applySession(response, refreshToken)
        loadWorkspaces()
        runCatching { loadAccountProfile() }
    }

    fun signOut() {
        val refreshToken = tokenStore.read()
        clearLocalSession()
        if (refreshToken != null) {
            scope.launch { runCatching { api.logout(refreshToken) } }
        }
    }

    private suspend fun currentAccessToken(forceRefresh: Boolean): String = refreshMutex.withLock {
        val current = accessToken
        if (!forceRefresh && current != null && !jwtExpiresWithin(current, REFRESH_AHEAD_SECONDS)) {
            return@withLock current
        }
        val refreshToken = tokenStore.read()
        if (refreshToken == null) {
            expireSession()
            throw ApiException(statusCode = 401, message = "登录状态无效，请重新登录")
        }
        try {
            val response = api.refreshSession(refreshToken)
            applySession(response, refreshToken)
            response.token
        } catch (error: ApiException) {
            if (error.isUnauthorized) expireSession()
            throw error
        }
    }

    private fun applySession(response: LoginResponse, existingRefreshToken: String?) {
        val refreshToken = response.refreshToken ?: existingRefreshToken
            ?: throw ApiException(message = "服务器未返回有效登录凭据")
        tokenStore.write(refreshToken)
        accessToken = response.token
        state = SessionState.SignedIn(
            SessionUser(
                username = response.username,
                displayName = response.username,
                userId = response.userId,
                tenantId = response.tenantId,
                role = response.role,
                hasPassword = response.hasPassword,
                workspaceType = response.workspaceType,
                activeWorkspaceId = response.activeWorkspaceId,
            ),
        )
    }

    private fun updateSignedInUser(transform: (SessionUser) -> SessionUser) {
        val signedIn = state as? SessionState.SignedIn ?: return
        state = SessionState.SignedIn(transform(signedIn.user))
    }

    private fun expireSession() {
        clearLocalSession()
    }

    private fun clearLocalSession() {
        accessToken = null
        tokenStore.clear()
        workspaces = emptyList()
        workspaceError = null
        avatarData = null
        state = SessionState.SignedOut
    }

    private companion object {
        const val REFRESH_AHEAD_SECONDS = 6 * 60 * 60L
    }
}

fun Throwable.userMessage(fallback: String): String = when (this) {
    is ApiException -> message
    is IllegalArgumentException, is IllegalStateException -> message ?: fallback
    else -> fallback
}
