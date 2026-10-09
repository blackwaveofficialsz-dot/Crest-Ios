package com.blackwave.crest.feature.auth

import com.blackwave.crest.ui.localization.L

import android.content.Context
import android.app.Activity
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import com.blackwave.crest.ui.components.CrestAlertDialog as AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import androidx.core.view.WindowCompat
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.core.session.userMessage
import com.blackwave.crest.ui.theme.CrestRoundedFontFamily
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil

private enum class AuthStep { PHONE, PASSWORD, VERIFICATION, RESET_PASSWORD }
private enum class VerificationPurpose(val wireValue: String) {
    LOGIN("login"), REGISTER("personal_register"), RESET_PASSWORD("reset_password")
}

private class AuthController(context: Context, private val session: SessionStore) {
    private val preferences = context.getSharedPreferences("crest_auth_flow", Context.MODE_PRIVATE)
    var step by mutableStateOf(AuthStep.PHONE)
    var purpose by mutableStateOf(VerificationPurpose.LOGIN)
    var phone by mutableStateOf("")
    var password by mutableStateOf("")
    var code by mutableStateOf("")
    var newPassword by mutableStateOf("")
    var confirmPassword by mutableStateOf("")
    var isBusy by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var notice by mutableStateOf<String?>(null)
    var resendAtMillis by mutableLongStateOf(preferences.getLong(KEY_RESEND_AT, 0L))
    var cooldownSeconds by mutableIntStateOf(remainingSeconds())

    fun updatePhone(value: String) {
        var digits = value.filter(Char::isDigit)
        if (digits.length > 11 && digits.startsWith("86")) digits = digits.drop(2)
        phone = digits.take(11)
    }

    suspend fun continueWithPhone() {
        if (isBusy) return
        isBusy = true
        error = null
        var nextPurpose: VerificationPurpose? = null
        try {
            val status = session.api.phoneStatus(phone)
            when {
                status.isRegistered && status.hasPassword -> step = AuthStep.PASSWORD
                status.isRegistered -> nextPurpose = VerificationPurpose.LOGIN
                else -> nextPurpose = VerificationPurpose.REGISTER
            }
        } catch (failure: Exception) {
            error = failure.userMessage(L("手机号状态查询失败"))
        } finally {
            isBusy = false
        }
        nextPurpose?.let { beginVerification(it) }
    }

    suspend fun loginWithPassword() = runBusy(L("登录失败")) { session.signIn(phone, password) }

    suspend fun beginVerification(nextPurpose: VerificationPurpose) {
        val remaining = remainingSeconds()
        val storedPhone = preferences.getString(KEY_PHONE, "")
        val storedPurpose = preferences.getString(KEY_PURPOSE, "")
        val storedChallenge = preferences.getString(KEY_CHALLENGE, "")
        if (remaining > 0 && storedPhone == phone && storedPurpose == nextPurpose.wireValue && !storedChallenge.isNullOrBlank()) {
            purpose = nextPurpose
            code = ""
            step = AuthStep.VERIFICATION
            cooldownSeconds = remaining
            return
        }
        if (remaining > 0) {
            error = L("操作频繁，请稍等 %lld 秒后再试。", remaining)
            return
        }
        purpose = nextPurpose
        code = ""
        step = AuthStep.VERIFICATION
        sendCode()
    }

    suspend fun sendCode() = runBusy(L("验证码发送失败")) {
        val startedAt = System.currentTimeMillis()
        persistChallenge("", startedAt + 60_000)
        try {
            val response = session.api.sendPhoneCode(phone, purpose.wireValue)
            persistChallenge(response.challengeId, startedAt + response.resendAfter * 1_000L)
        } catch (error: Exception) {
            persistChallenge("", 0)
            step = if (purpose == VerificationPurpose.REGISTER) AuthStep.PHONE else AuthStep.PASSWORD
            throw error
        }
    }

    suspend fun verifyCode() = runBusy(L("验证码校验失败")) {
        val challenge = preferences.getString(KEY_CHALLENGE, "").orEmpty()
        if (challenge.isBlank()) throw IllegalStateException(L("验证码已失效，请重新获取验证码。"))
        val confirmation = session.api.confirmPhoneCode(challenge, code)
        preferences.edit { remove(KEY_CHALLENGE) }
        when (purpose) {
            VerificationPurpose.LOGIN -> session.signInWithCode(confirmation.verificationToken)
            VerificationPurpose.REGISTER -> session.registerPersonal(confirmation.verificationToken)
            VerificationPurpose.RESET_PASSWORD -> {
                preferences.edit { putString(KEY_RESET_TOKEN, confirmation.verificationToken) }
                newPassword = ""
                confirmPassword = ""
                step = AuthStep.RESET_PASSWORD
            }
        }
    }

    suspend fun submitResetPassword() = runBusy(L("密码重置失败")) {
        if (newPassword.length !in 7..16) throw IllegalArgumentException(L("新密码需要 7 至 16 位。"))
        if (newPassword != confirmPassword) throw IllegalArgumentException(L("两次输入的密码不一致。"))
        val token = preferences.getString(KEY_RESET_TOKEN, "").orEmpty()
        if (token.isBlank()) throw IllegalStateException(L("重置凭据已失效，请重新获取验证码。"))
        val response = session.api.resetPassword(token, newPassword)
        preferences.edit { remove(KEY_RESET_TOKEN) }
        password = ""
        newPassword = ""
        confirmPassword = ""
        step = AuthStep.PASSWORD
        notice = response.message
    }

    fun back() {
        error = null
        when (step) {
            AuthStep.PHONE -> Unit
            AuthStep.PASSWORD -> { password = ""; step = AuthStep.PHONE }
            AuthStep.VERIFICATION -> {
                code = ""
                step = if (purpose == VerificationPurpose.REGISTER) AuthStep.PHONE else AuthStep.PASSWORD
            }
            AuthStep.RESET_PASSWORD -> { newPassword = ""; confirmPassword = ""; step = AuthStep.PASSWORD }
        }
    }

    fun tickCooldown() { cooldownSeconds = remainingSeconds() }

    private suspend fun runBusy(fallback: String, block: suspend () -> Unit) {
        if (isBusy) return
        isBusy = true
        error = null
        try { block() } catch (failure: Exception) {
            error = failure.userMessage(fallback)
            if (code.length == 6) code = ""
        } finally { isBusy = false }
    }

    private fun persistChallenge(challenge: String, resendAt: Long) {
        resendAtMillis = resendAt
        cooldownSeconds = remainingSeconds()
        preferences.edit {
            putString(KEY_PHONE, phone)
            putString(KEY_PURPOSE, purpose.wireValue)
            putString(KEY_CHALLENGE, challenge)
            putLong(KEY_RESEND_AT, resendAt)
        }
    }

    private fun remainingSeconds(): Int =
        ceil((resendAtMillis - System.currentTimeMillis()).coerceAtLeast(0) / 1_000.0).toInt()

    private companion object {
        const val KEY_PHONE = "phone"
        const val KEY_PURPOSE = "purpose"
        const val KEY_CHALLENGE = "challenge"
        const val KEY_RESEND_AT = "resend_at"
        const val KEY_RESET_TOKEN = "reset_token"
    }
}

@Composable
fun AuthScreen(session: SessionStore) {
    val context = LocalContext.current
    DisposableEffect(context) {
        val activity = context as? Activity
        if (activity == null) onDispose {} else {
            val window = activity.window
            val bars = WindowCompat.getInsetsController(window, window.decorView)
            val lightStatus = bars.isAppearanceLightStatusBars
            val lightNavigation = bars.isAppearanceLightNavigationBars
            val navigationColor = window.navigationBarColor
            val navigationContrast = if (Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced else null
            bars.isAppearanceLightStatusBars = false
            bars.isAppearanceLightNavigationBars = false
            window.navigationBarColor = android.graphics.Color.BLACK
            if (Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
            onDispose {
                bars.isAppearanceLightStatusBars = lightStatus
                bars.isAppearanceLightNavigationBars = lightNavigation
                window.navigationBarColor = navigationColor
                if (Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = navigationContrast == true
            }
        }
    }
    val controller = remember(session) { AuthController(context, session) }
    LaunchedEffect(controller.resendAtMillis) {
        while (controller.cooldownSeconds > 0) { delay(1_000); controller.tickCooldown() }
    }
    LaunchedEffect(controller.code) {
        if (controller.code.length == 6 && !controller.isBusy) controller.verifyCode()
    }

    Box(Modifier.fillMaxSize()) {
        AnimatedLoginBackground()
        Column(
            modifier = Modifier.fillMaxSize().safeDrawingPadding().imePadding().padding(horizontal = 18.dp),
        ) {
            if (controller.step == AuthStep.PHONE) {
                Spacer(Modifier.padding(top = 12.dp).height(44.dp))
            } else {
                AuthTopBar(controller.step, controller::back)
            }
            Spacer(Modifier.weight(1f))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 22.dp)
                    .background(Color.White.copy(alpha = 0.09f), RoundedCornerShape(28.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(28.dp))
                    .padding(20.dp),
            ) {
                when (controller.step) {
                    AuthStep.PHONE -> PhoneStep(controller)
                    AuthStep.PASSWORD -> PasswordStep(controller)
                    AuthStep.VERIFICATION -> VerificationStep(controller)
                    AuthStep.RESET_PASSWORD -> ResetPasswordStep(controller)
                }
            }
        }
    }

    controller.error?.let { message ->
        AlertDialog(
            onDismissRequest = { controller.error = null },
            confirmButton = { TextButton(onClick = { controller.error = null }) { Text(L("好")) } },
            title = { Text(L("操作失败")) }, text = { Text(message) },
        )
    }
    controller.notice?.let { message ->
        AlertDialog(
            onDismissRequest = { controller.notice = null },
            confirmButton = { TextButton(onClick = { controller.notice = null }) { Text(L("好")) } },
            title = { Text(L("操作成功")) }, text = { Text(message) },
        )
    }
}

@Composable
private fun AuthTopBar(step: AuthStep, onBack: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp).height(44.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(44.dp).background(Color.White.copy(.08f), CircleShape)
                .border(1.dp, Color.White.copy(.16f), CircleShape).clickable(onClick = onBack),
            contentAlignment = Alignment.Center,
        ) { BackChevron() }
        Spacer(Modifier.weight(1f))
        Text(
            when (step) {
                AuthStep.PASSWORD -> L("已识别账号")
                AuthStep.VERIFICATION -> L("验证码登录")
                AuthStep.RESET_PASSWORD -> L("重置密码")
                AuthStep.PHONE -> ""
            },
            color = Color.White.copy(.62f), fontSize = 12.sp,
        )
    }
}

@Composable
private fun PhoneStep(controller: AuthController) {
    Text(
        "Crest",
        color = Color.White,
        fontSize = 42.sp,
        fontWeight = FontWeight.SemiBold,
        fontFamily = CrestRoundedFontFamily,
    )
    Text(
        L("纷繁之上，洞察经营"), modifier = Modifier.padding(top = 8.dp, bottom = 26.dp),
        color = Color.White.copy(.72f), fontSize = 14.sp, fontWeight = FontWeight.Medium,
    )
    AuthInputField {
        Text("+86", color = Color.White.copy(.72f), fontSize = 16.sp)
        Box(Modifier.width(1.dp).height(20.dp).background(Color.White.copy(.18f)))
        AuthTextField(
            controller.phone, controller::updatePhone, L("请输入手机号"), Modifier.weight(1f), KeyboardType.Phone,
        )
    }
    AuthPrimaryButton(
        if (controller.isBusy) L("识别中") else "Get start", controller.isBusy,
        controller.phone.length == 11, Modifier.padding(top = 14.dp), controller::continueWithPhone,
    )
}

@Composable
private fun PasswordStep(controller: AuthController) {
    val scope = rememberCoroutineScope()
    var visible by remember { mutableStateOf(false) }
    AuthSectionHeader(L("欢迎回来"), formatPhone(controller.phone))
    AuthPasswordField(controller.password, { controller.password = it }, L("请输入密码"), visible, { visible = !visible })
    Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        AuthLink(L("验证码登录")) { scope.launch { controller.beginVerification(VerificationPurpose.LOGIN) } }
        Spacer(Modifier.weight(1f))
        AuthLink(L("忘记密码")) { scope.launch { controller.beginVerification(VerificationPurpose.RESET_PASSWORD) } }
    }
    AuthPrimaryButton(
        if (controller.isBusy) L("登录中") else L("登录"), controller.isBusy,
        controller.password.isNotBlank(), onClick = controller::loginWithPassword,
    )
}

@Composable
private fun AuthLink(title: String, onClick: () -> Unit) {
    Text(
        title, modifier = Modifier.clickable(onClick = onClick).padding(3.dp),
        color = Color.White.copy(.68f), fontSize = 13.sp, fontWeight = FontWeight.Medium,
    )
}

@Composable
private fun VerificationStep(controller: AuthController) {
    val scope = rememberCoroutineScope()
    val title = when (controller.purpose) {
        VerificationPurpose.LOGIN -> L("输入验证码")
        VerificationPurpose.REGISTER -> L("验证手机号")
        VerificationPurpose.RESET_PASSWORD -> L("确认是你")
    }
    val copy = when (controller.purpose) {
        VerificationPurpose.LOGIN -> L("验证码已发送至 %@", "+86 ${maskedPhone(controller.phone)}")
        VerificationPurpose.REGISTER -> L("完成验证后将直接进入 Crest")
        VerificationPurpose.RESET_PASSWORD -> L("请输入发送至 %@ 的验证码", "+86 ${maskedPhone(controller.phone)}")
    }
    AuthSectionHeader(title, copy)
    VerificationCodeField(controller.code) { controller.code = it.filter(Char::isDigit).take(6) }
    Text(
        when {
            controller.isBusy -> L("正在处理…")
            controller.cooldownSeconds > 0 -> L("%llds 后可重新发送", controller.cooldownSeconds)
            else -> L("重新发送验证码")
        },
        modifier = Modifier.fillMaxWidth().height(40.dp)
            .clickable(enabled = controller.cooldownSeconds == 0 && !controller.isBusy) { scope.launch { controller.sendCode() } }
            .padding(top = 11.dp),
        color = Color.White.copy(if (controller.cooldownSeconds > 0) .58f else 1f),
        fontSize = 13.sp, fontWeight = if (controller.cooldownSeconds > 0) FontWeight.Normal else FontWeight.SemiBold,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun ResetPasswordStep(controller: AuthController) {
    var newVisible by remember { mutableStateOf(false) }
    var confirmVisible by remember { mutableStateOf(false) }
    AuthSectionHeader(L("设置新密码"), L("使用新的密码保护你的账号"))
    AuthPasswordField(controller.newPassword, { controller.newPassword = it.take(16) }, L("请输入新密码"), newVisible, { newVisible = !newVisible })
    AuthPasswordField(
        controller.confirmPassword, { controller.confirmPassword = it.take(16) }, L("请再次输入新密码"),
        confirmVisible, { confirmVisible = !confirmVisible }, Modifier.padding(top = 12.dp),
    )
    AuthPrimaryButton(
        if (controller.isBusy) L("提交中") else L("确认"), controller.isBusy,
        controller.newPassword.length in 7..16 && controller.confirmPassword.isNotBlank(),
        Modifier.padding(top = 16.dp), controller::submitResetPassword,
    )
}

@Composable
private fun AuthSectionHeader(title: String, copy: String) {
    Text(title, color = Color.White, fontSize = 29.sp, fontWeight = FontWeight.SemiBold)
    Text(
        text = copy,
        modifier = Modifier.padding(top = 9.dp, bottom = 11.dp),
        color = Color.White.copy(.66f),
        fontSize = 14.sp,
        lineHeight = 20.sp,
    )
}

@Composable
private fun AuthInputField(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 54.dp)
            .background(Color.White.copy(.075f), RoundedCornerShape(17.dp))
            .border(1.dp, Color.White.copy(.14f), RoundedCornerShape(17.dp))
            .padding(start = 15.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp), content = content,
    )
}

@Composable
private fun AuthTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
    visualTransformation: VisualTransformation = VisualTransformation.None,
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        enabled = true,
        textStyle = TextStyle(color = Color.White, fontSize = 16.sp),
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Done),
        visualTransformation = visualTransformation,
        cursorBrush = Brush.verticalGradient(listOf(Color.White, Color.White)),
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, color = Color.White.copy(.48f), fontSize = 16.sp)
                inner()
            }
        },
    )
}

@Composable
private fun AuthPasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    visible: Boolean,
    onToggleVisibility: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AuthInputField(modifier) {
        AuthTextField(
            value, onValueChange, placeholder, Modifier.weight(1f), KeyboardType.Password,
            if (visible) VisualTransformation.None else PasswordVisualTransformation(),
        )
        Box(Modifier.size(44.dp).clickable(onClick = onToggleVisibility), contentAlignment = Alignment.Center) { EyeIcon(visible) }
    }
}

@Composable
private fun VerificationCodeField(value: String, onValueChange: (String) -> Unit) {
    val focusRequester = remember { FocusRequester() }
    Box(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(6) { index ->
                val active = value.length.coerceAtMost(5) == index
                Box(
                    Modifier.weight(1f).height(54.dp).background(Color.White.copy(.08f), RoundedCornerShape(14.dp))
                        .border(1.dp, Color.White.copy(if (active) .72f else .18f), RoundedCornerShape(14.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(value.getOrNull(index)?.toString().orEmpty(), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth().height(54.dp).focusRequester(focusRequester).alpha(.02f),
            textStyle = TextStyle(color = Color.Transparent),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            cursorBrush = Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent)),
        )
    }
}

@Composable
private fun AuthPrimaryButton(
    title: String,
    busy: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: suspend () -> Unit,
) {
    val scope = rememberCoroutineScope()
    Button(
        onClick = { scope.launch { onClick() } }, enabled = enabled && !busy,
        modifier = modifier.fillMaxWidth().height(54.dp), shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.White.copy(.92f), contentColor = Color.Black.copy(.9f),
            disabledContainerColor = Color.White.copy(.42f), disabledContentColor = Color.Black.copy(.48f),
        ),
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(20.dp), Color.Black.copy(.78f), strokeWidth = 2.dp)
            Spacer(Modifier.width(9.dp))
        }
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun BackChevron() {
    Canvas(Modifier.size(22.dp)) {
        val path = Path().apply {
            moveTo(size.width * .62f, size.height * .22f)
            lineTo(size.width * .35f, size.height * .5f)
            lineTo(size.width * .62f, size.height * .78f)
        }
        drawPath(path, Color.White, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
    }
}

@Composable
private fun EyeIcon(visible: Boolean) {
    Canvas(Modifier.size(22.dp)) {
        val eye = Path().apply {
            moveTo(size.width * .08f, size.height * .5f)
            cubicTo(size.width * .28f, size.height * .19f, size.width * .72f, size.height * .19f, size.width * .92f, size.height * .5f)
            cubicTo(size.width * .72f, size.height * .81f, size.width * .28f, size.height * .81f, size.width * .08f, size.height * .5f)
        }
        val color = Color.White.copy(.67f)
        drawPath(eye, color, style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round))
        drawCircle(color, 2.5.dp.toPx(), center)
        if (visible) drawLine(color, Offset(size.width * .16f, size.height * .16f), Offset(size.width * .84f, size.height * .84f), 1.6.dp.toPx(), StrokeCap.Round)
    }
}

private fun formatPhone(phone: String): String =
    if (phone.length == 11) "${phone.take(3)} ${phone.substring(3, 7)} ${phone.takeLast(4)}" else phone

private fun maskedPhone(phone: String): String =
    if (phone.length < 7) phone else "${phone.take(3)} **** ${phone.takeLast(4)}"
