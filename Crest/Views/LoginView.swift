import SwiftUI

/// 编排手机号、密码、验证码和重置密码四段认证流程。
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    private enum AuthStep: Hashable {
        case phone
        case password
        case verification
        case resetPassword
    }

    private struct AuthNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private let api = APIClient()
    private let countryCode = "+86"

    @State private var step: AuthStep = .phone
    @State private var verificationPurpose: PhoneVerificationPurpose = .login
    @State private var phone = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var resetToken = ""
    @State private var isPasswordVisible = false
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var isLoading = false
    @State private var isSendingCode = false
    @State private var isVerifying = false
    // 冷却状态写入本地，返回上一页或重启后仍沿用同一次倒计时。
    @AppStorage("auth.sms.phone") private var storedVerificationPhone = ""
    @AppStorage("auth.sms.purpose") private var storedVerificationPurpose = ""
    @AppStorage("auth.sms.challengeID") private var storedVerificationChallengeID = ""
    @AppStorage("auth.sms.resendAvailableAt") private var storedResendAvailableAt = 0.0
    @State private var notice: AuthNotice?
    @State private var shouldReturnAfterNotice = false
    @FocusState private var focusedField: AuthFocusField?

    private var canContinueWithPhone: Bool {
        !isLoading && phone.count == 11
    }

    private var canSubmitPassword: Bool {
        !isLoading && !password.isEmpty
    }

    private var canSubmitReset: Bool {
        !isLoading && !resetToken.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty
    }

    private var resendAvailableAt: Date {
        Date(timeIntervalSince1970: storedResendAvailableAt)
    }

    var body: some View {
        ZStack {
            AnimatedLoginBackground()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                }

            VStack(spacing: 0) {
                Group {
                    if step == .phone {
                        Color.clear
                            .frame(height: 44)
                    } else {
                        authTopBar
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 0)

                panelContent
                    .id(step)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 20)
                    .animation(.easeInOut(duration: 0.28), value: step)
                    .padding(.bottom, 22)
            }
            .padding(.horizontal, 18)
        }
        .tint(.white)
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好")) {
                    if shouldReturnAfterNotice {
                        shouldReturnAfterNotice = false
                        goBack()
                    }
                }
            )
        }
        .onChange(of: phone) { _, value in
            let digits = normalizedPhone(value)
            if digits != value {
                phone = digits
            }
        }
        .onChange(of: verificationCode) { _, value in
            let digits = String(value.filter { $0.isNumber }.prefix(6))
            if digits != value {
                verificationCode = digits
                return
            }
            // 六位输入完成后自动提交，失败时 verifyCode 会清空并重新聚焦。
            if digits.count == 6 && !isSendingCode && !isVerifying {
                Task { await verifyCode() }
            }
        }
    }

    private var authTopBar: some View {
        AuthTopBar(label: stepLabel, onBack: goBack)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch step {
        case .phone:
            phonePanel
        case .password:
            passwordPanel
        case .verification:
            verificationPanel
        case .resetPassword:
            resetPasswordPanel
        }
    }

    private var phonePanel: some View {
        PhoneLoginPanel(
            countryCode: countryCode,
            phone: $phone,
            isLoading: isLoading,
            canContinue: canContinueWithPhone,
            focusedField: $focusedField
        ) {
            Task { await continueWithPhone() }
        }
    }

    private var passwordPanel: some View {
        PasswordLoginPanel(
            formattedPhone: formattedPhone,
            password: $password,
            isPasswordVisible: $isPasswordVisible,
            isLoading: isLoading,
            isSendingCode: isSendingCode,
            canSubmit: canSubmitPassword,
            focusedField: $focusedField,
            onLoginWithCode: {
                Task { await beginVerification(.login) }
            },
            onForgotPassword: {
                Task { await beginVerification(.resetPassword) }
            },
            onSubmit: {
                Task { await submitPassword() }
            }
        )
    }

    private var verificationPanel: some View {
        VerificationLoginPanel(
            title: verificationTitle,
            copy: verificationCopy,
            code: $verificationCode,
            resendAvailableAt: resendAvailableAt,
            isSendingCode: isSendingCode,
            isVerifying: isVerifying,
            focusedField: $focusedField
        ) {
            Task {
                if await sendVerificationCode() {
                    await verifyCode()
                }
            }
        }
    }

    private var resetPasswordPanel: some View {
        ResetPasswordPanel(
            newPassword: $newPassword,
            confirmPassword: $confirmPassword,
            isNewPasswordVisible: $isNewPasswordVisible,
            isConfirmPasswordVisible: $isConfirmPasswordVisible,
            isLoading: isLoading,
            canSubmit: canSubmitReset,
            focusedField: $focusedField
        ) {
            Task { await submitResetPassword() }
        }
    }

    private var stepLabel: String {
        switch step {
        case .phone:
            return ""
        case .password:
            return AppLocalization.string("已识别账号")
        case .verification:
            switch verificationPurpose {
            case .login:
                return AppLocalization.string("验证码登录")
            case .register:
                return AppLocalization.string("创建个人账号")
            case .resetPassword:
                return AppLocalization.string("找回密码")
            }
        case .resetPassword:
            return AppLocalization.string("重置密码")
        }
    }

    private var verificationTitle: String {
        switch verificationPurpose {
        case .login:
            return AppLocalization.string("输入验证码")
        case .register:
            return AppLocalization.string("验证手机号")
        case .resetPassword:
            return AppLocalization.string("确认是你")
        }
    }

    private var verificationCopy: String {
        switch verificationPurpose {
        case .login:
            return AppLocalization.format("验证码已发送至 %@", maskedPhone)
        case .register:
            return AppLocalization.string("完成验证后将直接进入 Crest")
        case .resetPassword:
            return AppLocalization.format("请输入发送至 %@ 的验证码", maskedPhone)
        }
    }

    private var formattedPhone: String {
        guard phone.count == 11 else { return phone }
        let start = phone.index(phone.startIndex, offsetBy: 3)
        let end = phone.index(start, offsetBy: 4)
        return "\(phone[..<start]) \(phone[start..<end]) \(phone[end...])"
    }

    private var maskedPhone: String {
        guard phone.count >= 7 else { return "\(countryCode) \(phone)" }
        return "\(countryCode) \(phone.prefix(3)) **** \(phone.suffix(4))"
    }

    private func normalizedPhone(_ value: String) -> String {
        var digits = String(value.filter { $0.isNumber })
        if digits.count > 11 && digits.hasPrefix("86") {
            digits.removeFirst(2)
        }
        return String(digits.prefix(11))
    }

    /// 根据手机号注册状态决定进入密码登录、验证码登录或新用户注册。
    private func continueWithPhone() async {
        guard canContinueWithPhone else { return }
        isLoading = true
        defer { isLoading = false }

        let request = PhoneRegistrationStatusRequest(
            phone: phone,
            countryCode: countryCode,
            clientType: "mobile"
        )
        do {
            let status = try await api.phoneRegistrationStatus(request)
            if status.isRegistered && status.hasPassword {
                withAnimation(.easeInOut(duration: 0.28)) {
                    step = .password
                }
            } else if status.isRegistered {
                await beginVerification(.login)
            } else {
                await beginVerification(.register)
            }
        } catch {
            notice = AuthNotice(
                title: AppLocalization.string("查询失败"),
                message: AppLocalization.string(error.localizedDescription)
            )
        }
    }

    private func submitPassword() async {
        guard canSubmitPassword else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await session.signIn(phone: phone, password: password)
        } catch {
            notice = AuthNotice(
                title: AppLocalization.string("登录失败"),
                message: AppLocalization.string(error.localizedDescription)
            )
        }
    }

    /// 先进入验证码页，再异步发送短信，避免用户点击后感觉页面卡顿。
    private func beginVerification(_ purpose: PhoneVerificationPurpose) async {
        let remaining = verificationCooldownRemaining()
        if remaining > 0 {
            guard
                storedVerificationPhone == phone,
                storedVerificationPurpose == purpose.rawValue,
                !storedVerificationChallengeID.isEmpty
            else {
                showVerificationCooldownNotice(remaining: remaining)
                return
            }

            verificationPurpose = purpose
            verificationCode = ""
            withAnimation(.easeInOut(duration: 0.28)) {
                step = .verification
            }
            return
        }

        verificationPurpose = purpose
        verificationCode = ""
        withAnimation(.easeInOut(duration: 0.28)) {
            step = .verification
        }
        if await sendVerificationCode() {
            await verifyCode()
        }
    }

    @discardableResult
    /// 发送前立即保存冷却时间；请求失败时撤销倒计时并返回上一页。
    private func sendVerificationCode() async -> Bool {
        guard !isSendingCode && !isVerifying else { return false }

        let remaining = verificationCooldownRemaining()
        guard remaining == 0 else {
            showVerificationCooldownNotice(remaining: remaining)
            return false
        }

        verificationCode = ""
        storedVerificationPhone = phone
        storedVerificationPurpose = verificationPurpose.rawValue
        storedVerificationChallengeID = ""
        let sendStartedAt = Date()
        storedResendAvailableAt = sendStartedAt.addingTimeInterval(60).timeIntervalSince1970

        isSendingCode = true
        defer { isSendingCode = false }

        do {
            let response = try await api.sendPhoneCode(
                phone: phone,
                purpose: verificationPurpose
            )
            storedVerificationChallengeID = response.challengeID
            storedResendAvailableAt = sendStartedAt
                .addingTimeInterval(TimeInterval(response.resendAfter))
                .timeIntervalSince1970
            return true
        } catch {
            storedVerificationChallengeID = ""
            storedResendAvailableAt = 0
            shouldReturnAfterNotice = true
            notice = AuthNotice(
                title: AppLocalization.string("验证码发送失败"),
                message: AppLocalization.string(error.localizedDescription)
            )
            return false
        }
    }

    private func verificationCooldownRemaining(at date: Date = Date()) -> Int {
        max(0, Int(ceil(resendAvailableAt.timeIntervalSince(date))))
    }

    private func showVerificationCooldownNotice(remaining: Int) {
        notice = AuthNotice(
            title: AppLocalization.string("操作频繁"),
            message: AppLocalization.format("请稍等 %lld 秒后再试。", Int64(remaining))
        )
    }

    /// 校验成功后按照用途完成登录、注册或进入重置密码页面。
    private func verifyCode() async {
        guard verificationCode.count == 6, !isSendingCode, !isVerifying else { return }
        guard !storedVerificationChallengeID.isEmpty else {
            verificationCode = ""
            notice = AuthNotice(
                title: AppLocalization.string("验证码已失效"),
                message: AppLocalization.string("请重新获取验证码。")
            )
            focus(after: .verification)
            return
        }

        isVerifying = true
        defer { isVerifying = false }

        do {
            let response = try await api.confirmPhoneCode(
                challengeID: storedVerificationChallengeID,
                code: verificationCode
            )
            storedVerificationChallengeID = ""

            switch verificationPurpose {
            case .login:
                try await session.signInWithCode(verificationToken: response.verificationToken)
            case .resetPassword:
                resetToken = response.verificationToken
                newPassword = ""
                confirmPassword = ""
                withAnimation(.easeInOut(duration: 0.28)) {
                    step = .resetPassword
                }
            case .register:
                try await session.registerPersonal(
                    verificationToken: response.verificationToken
                )
            }
        } catch {
            verificationCode = ""
            notice = AuthNotice(
                title: AppLocalization.string("验证码错误"),
                message: AppLocalization.string(error.localizedDescription)
            )
            focus(after: .verification)
        }
    }

    private func submitResetPassword() async {
        guard canSubmitReset else { return }
        guard (7...16).contains(newPassword.count) else {
            notice = AuthNotice(
                title: AppLocalization.string("密码格式不正确"),
                message: AppLocalization.string("新密码需要 7 至 16 位。")
            )
            return
        }
        guard newPassword == confirmPassword else {
            notice = AuthNotice(
                title: AppLocalization.string("两次密码不一致"),
                message: AppLocalization.string("请重新确认新密码。")
            )
            confirmPassword = ""
            focusedField = .confirmPassword
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.resetPassword(
                verificationToken: resetToken,
                newPassword: newPassword
            )
            password = ""
            newPassword = ""
            confirmPassword = ""
            resetToken = ""
            verificationCode = ""
            withAnimation(.easeInOut(duration: 0.28)) {
                step = .password
            }
            notice = AuthNotice(
                title: AppLocalization.string("密码重置成功"),
                message: AppLocalization.string(response.message)
            )
        } catch {
            notice = AuthNotice(
                title: AppLocalization.string("密码重置失败"),
                message: AppLocalization.string(error.localizedDescription)
            )
        }
    }

    private func goBack() {
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.28)) {
            switch step {
            case .phone:
                break
            case .password:
                password = ""
                step = .phone
            case .verification:
                verificationCode = ""
                step = verificationPurpose == .register ? .phone : .password
            case .resetPassword:
                resetToken = ""
                newPassword = ""
                confirmPassword = ""
                step = .password
            }
        }
    }

    private func focus(after target: AuthStep) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            switch target {
            case .phone:
                focusedField = .phone
            case .password:
                focusedField = .password
            case .verification:
                focusedField = .verificationCode
            case .resetPassword:
                focusedField = .newPassword
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(SessionStore())
}
