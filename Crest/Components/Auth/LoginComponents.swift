import SwiftUI

/// 登录流程中所有可聚焦输入项的统一标识。
enum AuthFocusField: Hashable {
    case phone
    case password
    case verificationCode
    case newPassword
    case confirmPassword
}

/// 非手机号首屏使用的返回导航栏。
struct AuthTopBar: View {
    let label: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("返回")
            .systemGlassCircleButton()
            .tint(.white)

            Spacer()

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .monospacedDigit()
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
    }
}

/// 登录流程第一步，只收集并校验手机号格式。
struct PhoneLoginPanel: View {
    let countryCode: String
    @Binding var phone: String
    let isLoading: Bool
    let canContinue: Bool
    @FocusState.Binding var focusedField: AuthFocusField?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Crest")
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.26), radius: 24)

            Text("纷繁之上，洞察经营")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 8)
                .padding(.bottom, 26)

            AuthInputField {
                HStack(spacing: 10) {
                    Text(countryCode)
                        .foregroundStyle(.white.opacity(0.72))

                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 1, height: 20)

                    TextField(
                        "手机号",
                        text: $phone,
                        prompt: Text("请输入手机号").foregroundStyle(.white.opacity(0.48))
                    )
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .submitLabel(.continue)
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .phone)
                    .onSubmit(onContinue)
                }
            }

            AuthPrimaryButton(
                title: AppLocalization.string(isLoading ? "识别中" : "开始使用"),
                isLoading: isLoading,
                isEnabled: canContinue,
                action: onContinue
            )
            .padding(.top, 14)
        }
    }
}

/// 已设置密码用户的密码登录面板。
struct PasswordLoginPanel: View {
    let formattedPhone: String
    @Binding var password: String
    @Binding var isPasswordVisible: Bool
    let isLoading: Bool
    let isSendingCode: Bool
    let canSubmit: Bool
    @FocusState.Binding var focusedField: AuthFocusField?
    let onLoginWithCode: () -> Void
    let onForgotPassword: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthSectionHeader(title: AppLocalization.string("欢迎回来"), copy: formattedPhone)

            AuthPasswordInput(
                label: AppLocalization.string("密码"),
                prompt: AppLocalization.string("请输入密码"),
                text: $password,
                isVisible: $isPasswordVisible,
                focus: .password,
                isNewPassword: false,
                focusedField: $focusedField,
                onSubmit: onSubmit
            )

            HStack {
                Button("验证码登录", action: onLoginWithCode)
                    .disabled(isSendingCode)

                Spacer()

                Button("忘记密码", action: onForgotPassword)
                    .disabled(isSendingCode)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.68))
            .frame(minHeight: 44)
            .padding(.horizontal, 3)

            AuthPrimaryButton(
                title: AppLocalization.string(isLoading ? "登录中" : "登录"),
                isLoading: isLoading,
                isEnabled: canSubmit,
                action: onSubmit
            )
        }
    }
}

/// 验证码输入、自动校验和重新发送倒计时面板。
struct VerificationLoginPanel: View {
    let title: String
    let copy: String
    @Binding var code: String
    let resendAvailableAt: Date
    let isSendingCode: Bool
    let isVerifying: Bool
    @FocusState.Binding var focusedField: AuthFocusField?
    let onResend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthSectionHeader(title: title, copy: copy)

            VerificationCodeInput(
                code: $code,
                isVerifying: isVerifying,
                focusedField: $focusedField
            )

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(resendAvailableAt.timeIntervalSince(context.date))))

                Button(action: onResend) {
                    Group {
                        if isVerifying {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.72))
                        } else {
                            Text(
                                remaining > 0
                                    ? AppLocalization.format("%llds 后可重新发送", Int64(remaining))
                                    : AppLocalization.string("重新发送验证码")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(remaining > 0 ? .regular : .semibold))
                .foregroundStyle(.white.opacity(remaining > 0 ? 0.58 : 1))
                .disabled(remaining > 0 || isSendingCode || isVerifying)
            }
        }
    }
}

/// 验证码通过后的新密码确认面板。
struct ResetPasswordPanel: View {
    @Binding var newPassword: String
    @Binding var confirmPassword: String
    @Binding var isNewPasswordVisible: Bool
    @Binding var isConfirmPasswordVisible: Bool
    let isLoading: Bool
    let canSubmit: Bool
    @FocusState.Binding var focusedField: AuthFocusField?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthSectionHeader(
                title: AppLocalization.string("设置新密码"),
                copy: AppLocalization.string("使用新的密码保护你的账号")
            )

            AuthPasswordInput(
                label: AppLocalization.string("新密码"),
                prompt: AppLocalization.string("请输入新密码"),
                text: $newPassword,
                isVisible: $isNewPasswordVisible,
                focus: .newPassword,
                isNewPassword: true,
                focusedField: $focusedField
            ) {
                focusedField = .confirmPassword
            }

            AuthPasswordInput(
                label: AppLocalization.string("再次输入新密码"),
                prompt: AppLocalization.string("请再次输入新密码"),
                text: $confirmPassword,
                isVisible: $isConfirmPasswordVisible,
                focus: .confirmPassword,
                isNewPassword: true,
                focusedField: $focusedField,
                onSubmit: onSubmit
            )
            .padding(.top, 12)

            AuthPrimaryButton(
                title: AppLocalization.string(isLoading ? "提交中" : "确认"),
                isLoading: isLoading,
                isEnabled: canSubmit,
                action: onSubmit
            )
            .padding(.top, 16)
        }
    }
}

/// 六格视觉输入框，实际输入由一个透明 TextField 统一接收。
private struct VerificationCodeInput: View {
    @Binding var code: String
    let isVerifying: Bool
    @FocusState.Binding var focusedField: AuthFocusField?

    var body: some View {
        ZStack {
            TextField("验证码", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .verificationCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .frame(height: 54)
                .disabled(isVerifying)
                .accessibilityLabel("六位验证码")

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let characters = Array(code)
                    let isActive = min(characters.count, 5) == index

                    Text(index < characters.count ? String(characters[index]) : "")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(isActive ? 0.72 : 0.18), lineWidth: 1)
                        }
                        .shadow(color: .white.opacity(isActive ? 0.09 : 0), radius: 8)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isVerifying {
                focusedField = .verificationCode
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct AuthSectionHeader: View {
    let title: String
    let copy: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.white)

            Text(copy)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
                .lineSpacing(3)
        }
        .padding(.bottom, 11)
    }
}

/// 登录页通用玻璃输入容器。
private struct AuthInputField<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(minHeight: 54)
            .padding(.leading, 15)
            .padding(.trailing, 8)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

/// 可切换明文显示的密码输入框。
private struct AuthPasswordInput: View {
    let label: String
    let prompt: String
    @Binding var text: String
    @Binding var isVisible: Bool
    let focus: AuthFocusField
    let isNewPassword: Bool
    @FocusState.Binding var focusedField: AuthFocusField?
    let onSubmit: () -> Void

    var body: some View {
        AuthInputField {
            HStack(spacing: 6) {
                Group {
                    if isVisible {
                        TextField(
                            label,
                            text: $text,
                            prompt: Text(prompt).foregroundStyle(.white.opacity(0.48))
                        )
                    } else {
                        SecureField(
                            label,
                            text: $text,
                            prompt: Text(prompt).foregroundStyle(.white.opacity(0.48))
                        )
                    }
                }
                .textContentType(isNewPassword ? .newPassword : .password)
                .submitLabel(isNewPassword && focus == .newPassword ? .next : .go)
                .foregroundStyle(.white)
                .focused($focusedField, equals: focus)
                .onSubmit(onSubmit)

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.67))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(
                    AppLocalization.string(isVisible ? "隐藏密码" : "显示密码")
                )
            }
        }
    }
}

/// 登录流程统一的主要操作按钮。
private struct AuthPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .tint(.black.opacity(0.78))
                }

                Text(title)
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.black.opacity(isEnabled ? 0.9 : 0.48))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.white.opacity(isEnabled ? 0.92 : 0.42), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(isEnabled ? 0.92 : 0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isEnabled ? 0.2 : 0), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
