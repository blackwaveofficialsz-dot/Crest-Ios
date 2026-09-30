import SwiftUI

/// 为验证码注册且尚未设置密码的用户补充首次密码。
struct InitialPasswordView: View {
    private enum Field: Hashable {
        case password
        case confirmation
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var validationMessage: String?
    @State private var errorMessage: String?
    @State private var isSuccessAlertPresented = false
    @FocusState private var focusedField: Field?

    private var canSubmit: Bool {
        (7...16).contains(password.count)
            && password == confirmation
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("7 至 16 位密码", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit(validatePassword)
                    SecureField("再次输入密码", text: $confirmation)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmation)
                        .submitLabel(.go)
                        .onSubmit {
                            guard validateConfirmation() else { return }
                            Task { await submit() }
                        }
                } header: {
                    Text("设置密码")
                } footer: {
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("完善密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .alert(
                "密码设置失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? AppLocalization.string("请稍后重试"))
            }
            .alert("密码设置成功", isPresented: $isSuccessAlertPresented) {
                Button("好") { dismiss() }
            } message: {
                Text("密码已设置完成")
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await session.setInitialPassword(password)
            isSuccessAlertPresented = true
        } catch {
            errorMessage = AppLocalization.string(error.localizedDescription)
        }
    }

    private func validatePassword() {
        guard (7...16).contains(password.count) else {
            validationMessage = AppLocalization.string("密码长度需为 7 至 16 位")
            return
        }
        validationMessage = nil
        focusedField = .confirmation
    }

    private func validateConfirmation() -> Bool {
        guard password == confirmation else {
            validationMessage = AppLocalization.string("两次输入的密码不一致")
            return false
        }
        validationMessage = nil
        return canSubmit
    }
}
