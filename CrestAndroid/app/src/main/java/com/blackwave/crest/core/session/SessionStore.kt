package com.blackwave.crest.core.session

import com.blackwave.crest.ui.localization.L

import android.content.Context
import android.icu.text.BreakIterator
import androidx.core.content.edit
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.blackwave.crest.core.model.LoginResponse
import com.blackwave.crest.core.model.WorkspaceSummary
import com.blackwave.crest.core.network.ApiClient
import com.blackwave.crest.core.network.ApiException
import com.blackwave.crest.core.security.SecureTokenStore
import com.blackwave.crest.feature.analytics.AnalyticsSnapshotCache
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.Locale

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
    internal val analyticsCache = AnalyticsSnapshotCache(context.applicationContext)
    private val preferences = context.getSharedPreferences("crest_preferences", Context.MODE_PRIVATE)
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
    private var sessionEpoch = 0

    suspend fun restore() {
        val epoch = ++sessionEpoch
        state = SessionState.Restoring
        val refreshToken = tokenStore.read()
        if (refreshToken == null) {
            state = SessionState.SignedOut
            return
        }
        try {
            val response = api.refreshSession(refreshToken)
            ensureSession(epoch)
            applySession(response, refreshToken)
            loadAccountData()
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: ApiException) {
            ensureSession(epoch)
            if (error.isUnauthorized) {
                clearLocalSession()
            } else {
                state = SessionState.RestoreError(error.message)
            }
        } catch (_: Exception) {
            ensureSession(epoch)
            state = SessionState.RestoreError(L("暂时无法连接服务器，请检查网络后重试。"))
        }
    }

    suspend fun signIn(phone: String, password: String) {
        val epoch = ++sessionEpoch
        val response = api.login(phone, password)
        ensureSession(epoch)
        applySession(response, null)
        loadAccountData()
    }

    suspend fun signInWithCode(verificationToken: String) {
        val epoch = ++sessionEpoch
        val response = api.loginWithCode(verificationToken)
        ensureSession(epoch)
        applySession(response, null)
        loadAccountData()
    }

    suspend fun registerPersonal(verificationToken: String) {
        val epoch = ++sessionEpoch
        val response = api.registerPersonal(verificationToken)
        ensureSession(epoch)
        applySession(response, null)
        loadAccountData()
    }

    suspend fun <T> authenticated(block: suspend (String) -> T): T {
        val epoch = sessionEpoch
        val firstToken = currentAccessToken(forceRefresh = false)
        ensureSession(epoch)
        return try {
            block(firstToken).also { ensureSession(epoch) }
        } catch (error: ApiException) {
            ensureSession(epoch)
            if (!error.isUnauthorized) throw error
            val refreshedToken = currentAccessToken(forceRefresh = true, rejectedToken = firstToken)
            ensureSession(epoch)
            try {
                block(refreshedToken).also { ensureSession(epoch) }
            } catch (second: ApiException) {
                ensureSession(epoch)
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
        } catch (cancel: CancellationException) { throw cancel
        } catch (error: Exception) {
            workspaceError = error.userMessage(L("工作空间加载失败"))
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
        val characters = BreakIterator.getCharacterInstance(Locale.getDefault()).apply { setText(normalized) }
        var count = 0
        while (characters.next() != BreakIterator.DONE) count++
        require(count in 1..30) { L("昵称长度需为 1 至 30 个字符") }
        val profile = authenticated { api.updateDisplayName(normalized, it) }
        updateSignedInUser { user ->
            user.copy(username = profile.username, displayName = profile.displayName)
        }
    }

    suspend fun updateAvatar(imageData: ByteArray) {
        require(imageData.isNotEmpty() && imageData.size <= 1024 * 1024) { L("头像需为不超过 1 MB 的图片") }
        authenticated { api.uploadAccountAvatar(imageData, it) }
        avatarData = imageData
    }

    suspend fun setInitialPassword(newPassword: String) {
        require(newPassword.length in 7..16) { L("密码长度需为 7 至 16 位") }
        val response = authenticated { api.setInitialPassword(newPassword, it) }
        updateSignedInUser { it.copy(hasPassword = response.hasPassword) }
    }

    suspend fun changePassword(oldPassword: String, newPassword: String) {
        require(oldPassword.isNotEmpty()) { L("请输入当前密码") }
        require(newPassword.length in 7..16) { L("密码长度需为 7 至 16 位") }
        authenticated { api.changePassword(oldPassword, newPassword, it) }
    }

    suspend fun acceptInvitation(inviteToken: String): String {
        val normalized = inviteToken.trim()
        require(normalized.isNotEmpty()) { L("请输入邀请码") }
        val response = authenticated { api.acceptInvitation(normalized, it) }
        workspaces = workspaces
            .filterNot { it.workspaceId == response.workspace.workspaceId }
            .plus(response.workspace)
        return response.message
    }

    suspend fun switchWorkspace(workspaceId: String) {
        val current = (state as? SessionState.SignedIn)?.user ?: return
        if (current.activeWorkspaceId == workspaceId) return
        val refreshToken = tokenStore.read() ?: throw ApiException(message = L("登录状态无效，请重新登录"))
        val response = authenticated { token ->
            api.switchWorkspace(workspaceId, refreshToken, token)
        }
        sessionEpoch++
        applySession(response, refreshToken)
        preferences.edit { putString("lastWorkspace.${response.userId}", response.activeWorkspaceId) }
        loadWorkspaces()
        try { loadAccountProfile() } catch (cancel: CancellationException) { throw cancel } catch (_: Exception) { }
    }

    private suspend fun loadAccountData() {
        loadWorkspaces()
        val user = (state as? SessionState.SignedIn)?.user ?: return
        val remembered = preferences.getString("lastWorkspace.${user.userId}", null)
        if (remembered != null && remembered != user.activeWorkspaceId && workspaces.any { it.workspaceId == remembered }) {
            try { switchWorkspace(remembered); return }
            catch (cancel: CancellationException) { throw cancel }
            catch (_: Exception) { /* Keep the current authorized workspace when restoration fails. */ }
        }
        if (remembered == null || workspaces.none { it.workspaceId == remembered }) {
            preferences.edit { putString("lastWorkspace.${user.userId}", user.activeWorkspaceId) }
        }
        try { loadAccountProfile() } catch (cancel: CancellationException) { throw cancel } catch (_: Exception) { }
    }

    private fun ensureSession(epoch: Int) {
        if (epoch != sessionEpoch) throw CancellationException("Session changed")
    }

    fun signOut() {
        val refreshToken = tokenStore.read()
        clearLocalSession()
        if (refreshToken != null) {
            scope.launch { runCatching { api.logout(refreshToken) } }
        }
    }

    private suspend fun currentAccessToken(forceRefresh: Boolean, rejectedToken: String? = null): String = refreshMutex.withLock {
        val epoch = sessionEpoch
        val current = accessToken
        if (forceRefresh && current != null && current != rejectedToken) return@withLock current
        if (!forceRefresh && current != null && !jwtExpiresWithin(current, REFRESH_AHEAD_SECONDS)) {
            return@withLock current
        }
        val refreshToken = tokenStore.read()
        if (refreshToken == null) {
            expireSession()
            throw ApiException(statusCode = 401, message = L("登录状态无效，请重新登录"))
        }
        try {
            val response = api.refreshSession(refreshToken)
            ensureSession(epoch)
            applySession(response, refreshToken)
            response.token
        } catch (error: ApiException) {
            ensureSession(epoch)
            if (error.isUnauthorized) expireSession()
            throw error
        }
    }

    private fun applySession(response: LoginResponse, existingRefreshToken: String?) {
        val previous = (state as? SessionState.SignedIn)?.user
        val refreshToken = response.refreshToken ?: existingRefreshToken
            ?: throw ApiException(message = L("服务器未返回有效登录凭据"))
        tokenStore.write(refreshToken)
        accessToken = response.token
        state = SessionState.SignedIn(
            SessionUser(
                username = response.username,
                displayName = previous?.takeIf { it.userId == response.userId }?.displayName ?: response.username,
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
        analyticsCache.clear()
        sessionEpoch++
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
