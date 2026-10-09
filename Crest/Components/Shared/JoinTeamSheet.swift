import SwiftUI

struct JoinTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @State private var tenantCode = ""
    @State private var isSubmitting = false
    @State private var alertTitle: String?
    @State private var alertMessage = ""
    @State private var dismissAfterAlert = false
    @FocusState private var isCodeFocused: Bool

    private var normalizedCode: String {
        tenantCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("邀请码")
                        .font(.headline)

                    TextField("输入邮件中的邀请码", text: $tenantCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($isCodeFocused)
                        .onSubmit(submit)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.border, lineWidth: 1)
                        }

                    Text("邀请码区分大小写，验证成功后即可加入对应工作空间。")
                        .font(.footnote)
                        .foregroundStyle(AppColors.secondaryText)
                }

                Button(action: submit) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("加入团队", systemImage: "person.badge.plus")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedCode.isEmpty || isSubmitting)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppColors.background.ignoresSafeArea())
            .foregroundStyle(AppColors.primaryText)
            .navigationTitle("加入新团队")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                        .disabled(isSubmitting)
                }
            }
        }
        .task {
            isCodeFocused = true
        }
        .alert(
            alertTitle ?? AppLocalization.string("加入团队"),
            isPresented: Binding(
                get: { alertTitle != nil },
                set: { if !$0 { alertTitle = nil } }
            )
        ) {
            Button("好") {
                alertTitle = nil
                if dismissAfterAlert {
                    dismiss()
                }
            }
        } message: {
            Text(AppLocalization.string(alertMessage))
        }
    }

    private func submit() {
        let code = normalizedCode
        guard !code.isEmpty, !isSubmitting else { return }

        isCodeFocused = false
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let response = try await session.acceptInvitation(code: code)
                alertTitle = AppLocalization.string("已加入团队")
                alertMessage = AppLocalization.string(response.message)
                dismissAfterAlert = true
            } catch {
                alertTitle = AppLocalization.string("加入团队失败")
                alertMessage = AppLocalization.string(error.localizedDescription)
                dismissAfterAlert = false
            }
        }
    }
}
