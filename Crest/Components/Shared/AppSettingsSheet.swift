import PhotosUI
import SwiftUI
import UIKit

/// 从底部展示的账户和主题设置面板。
struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.systemColorScheme) private var systemColorScheme
    @EnvironmentObject private var session: SessionStore
    @AppStorage(AppTheme.storageKey) private var selectedTheme = AppTheme.dark.rawValue
    @State private var settingsError: String?
    @State private var isShowingJoinTeam = false
    @State private var isShowingProfile = false
    @State private var isShowingChangePassword = false
    @State private var isShowingInitialPassword = false

    private var displayName: String {
        session.accountDisplayName
    }

    private var initials: String {
        String(displayName.prefix(1)).uppercased()
    }

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .dark
    }

    /// “跟随系统”使用捕获的真实系统主题，其他选项使用用户指定主题。
    private var resolvedColorScheme: ColorScheme {
        theme.colorScheme ?? systemColorScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("设置")
                            .font(.title2.weight(.semibold))

                        Spacer()

                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("关闭设置")
                        .systemGlassProminentCircleButton()
                        .tint(.blue)
                    }

                    VStack(spacing: 12) {
                        AccountAvatarView(
                            data: session.avatarData,
                            initials: initials,
                            size: 82
                        )

                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 30)

                    settingsSection(title: "账户") {
                        Button {
                            isShowingProfile = true
                        } label: {
                            settingsRow(
                                icon: "person.crop.circle",
                                title: "个人资料",
                                value: displayName,
                                trailingIcon: "chevron.right"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .overlay(AppColors.border)
                            .padding(.leading, 58)

                        Button {
                            if session.hasPassword {
                                isShowingChangePassword = true
                            } else {
                                isShowingInitialPassword = true
                            }
                        } label: {
                            settingsRow(
                                icon: "lock",
                                title: session.hasPassword ? "修改密码" : "设置密码",
                                trailingIcon: "chevron.right"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(title: "工作空间") {
                        if session.workspaces.isEmpty && session.isLoadingWorkspaces {
                            ProgressView()
                                .tint(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 58)
                        } else {
                            ForEach(Array(session.workspaces.enumerated()), id: \.element.id) { index, workspace in
                                if index > 0 {
                                    Divider()
                                        .overlay(AppColors.border)
                                        .padding(.leading, 58)
                                }

                                Button {
                                    switchWorkspace(to: workspace.workspaceID)
                                } label: {
                                    workspaceRow(workspace)
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    workspace.workspaceID == session.activeWorkspaceID
                                        || session.isSwitchingWorkspace
                                )
                            }
                        }

                        if !session.workspaces.isEmpty {
                            Divider()
                                .overlay(AppColors.border)
                                .padding(.leading, 58)
                        }

                        Button {
                            isShowingJoinTeam = true
                        } label: {
                            settingsRow(
                                icon: "person.badge.plus",
                                title: "加入新团队",
                                trailingIcon: "chevron.right"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(title: "主题") {
                        Menu {
                            Picker("外观", selection: $selectedTheme) {
                                ForEach(AppTheme.allCases) { option in
                                    Label(option.title, systemImage: option.systemImage)
                                        .tag(option.rawValue)
                                }
                            }
                        } label: {
                            settingsRow(
                                icon: theme.systemImage,
                                title: "外观",
                                value: theme.title,
                                trailingIcon: "chevron.up.chevron.down"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            Button {
                dismiss()
                session.signOut()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        AppColors.surface,
                        in: RoundedRectangle(cornerRadius: 45, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .foregroundStyle(AppColors.primaryText)
        .background(AppColors.background.ignoresSafeArea())
        .preferredColorScheme(resolvedColorScheme)
        .tint(.blue)
        .sheet(isPresented: $isShowingJoinTeam) {
            JoinTeamSheet()
                .environmentObject(session)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingProfile) {
            AccountProfileView()
                .environmentObject(session)
        }
        .sheet(isPresented: $isShowingChangePassword) {
            ChangePasswordView()
                .environmentObject(session)
        }
        .sheet(isPresented: $isShowingInitialPassword) {
            InitialPasswordView()
                .environmentObject(session)
        }
        .task {
            do {
                try await session.loadWorkspaces()
                try await session.loadAccountProfile()
            } catch {
                settingsError = error.localizedDescription
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { settingsError != nil },
                set: { if !$0 { settingsError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(settingsError ?? "请稍后重试")
        }
    }

    /// 统一设置分区标题、间距和圆角容器。
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.secondaryText)
                .padding(.leading, 4)

            VStack(spacing: 0, content: content)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.bottom, 26)
    }

    /// 统一设置行的图标、标题、值和下拉指示样式。
    private func settingsRow(
        icon: String,
        title: String,
        value: String? = nil,
        titleColor: Color = AppColors.primaryText,
        trailingIcon: String? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(titleColor)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(titleColor)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.tertiaryText)
            }
        }
        .font(.body)
        .frame(minHeight: 58)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func workspaceRow(_ workspace: WorkspaceSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: workspace.workspaceType == .personal ? "person.crop.circle" : "building.2")
                .font(.system(size: 19, weight: .medium))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.name)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)

                Text(workspace.workspaceType == .personal ? "个人账号" : workspace.role)
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if session.isSwitchingWorkspace
                && workspace.workspaceID != session.activeWorkspaceID {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppColors.secondaryText)
            } else if workspace.workspaceID == session.activeWorkspaceID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.body)
        .frame(minHeight: 62)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func switchWorkspace(to workspaceID: String) {
        Task {
            do {
                try await session.switchWorkspace(to: workspaceID)
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }
}

private struct AccountAvatarView: View {
    let data: Data?
    let initials: String
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.39, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct AvatarCropSelection: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct AvatarCropView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gestureOffset = CGSize.zero
    @State private var errorMessage: String?

    private let maximumZoom: CGFloat = 4

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSize = min(proxy.size.width - 32, proxy.size.height - 128)
                let visibleZoom = min(max(zoom * gestureZoom, 1), maximumZoom)
                let visibleOffset = clampedOffset(
                    CGSize(
                        width: offset.width + gestureOffset.width,
                        height: offset.height + gestureOffset.height
                    ),
                    cropSize: cropSize,
                    zoom: visibleZoom
                )

                VStack(spacing: 28) {
                    Spacer(minLength: 0)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cropSize, height: cropSize)
                        .scaleEffect(visibleZoom)
                        .offset(visibleOffset)
                        .frame(width: cropSize, height: cropSize)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.9), lineWidth: 1)
                        }
                        .contentShape(Circle())
                        .simultaneousGesture(dragGesture(cropSize: cropSize))
                        .simultaneousGesture(zoomGesture(cropSize: cropSize))

                    HStack(spacing: 14) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(
                            value: Binding(
                                get: { zoom },
                                set: { newZoom in
                                    zoom = newZoom
                                    offset = clampedOffset(offset, cropSize: cropSize, zoom: newZoom)
                                }
                            ),
                            in: 1...maximumZoom
                        )
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("使用") {
                            guard let data = croppedJPEGData(
                                cropSize: cropSize,
                                zoom: visibleZoom,
                                offset: visibleOffset
                            ) else {
                                errorMessage = "无法处理所选图片"
                                return
                            }
                            dismiss()
                            onConfirm(data)
                        }
                    }
                }
            }
            .navigationTitle("调整头像")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.black)
            .preferredColorScheme(.dark)
            .alert(
                "头像处理失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请重新选择图片")
            }
        }
    }

    private func dragGesture(cropSize: CGFloat) -> some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = clampedOffset(
                    CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    ),
                    cropSize: cropSize,
                    zoom: zoom
                )
            }
    }

    private func zoomGesture(cropSize: CGFloat) -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoom) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newZoom = min(max(zoom * value, 1), maximumZoom)
                zoom = newZoom
                offset = clampedOffset(offset, cropSize: cropSize, zoom: newZoom)
            }
    }

    private func clampedOffset(_ proposed: CGSize, cropSize: CGFloat, zoom: CGFloat) -> CGSize {
        let scale = max(cropSize / image.size.width, cropSize / image.size.height)
        let width = image.size.width * scale * zoom
        let height = image.size.height * scale * zoom
        let horizontalLimit = max(0, (width - cropSize) / 2)
        let verticalLimit = max(0, (height - cropSize) / 2)

        return CGSize(
            width: min(max(proposed.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposed.height, -verticalLimit), verticalLimit)
        )
    }

    private func croppedJPEGData(cropSize: CGFloat, zoom: CGFloat, offset: CGSize) -> Data? {
        let outputSize = CGSize(width: 512, height: 512)
        let imageScale = max(cropSize / image.size.width, cropSize / image.size.height) * zoom
        let outputScale = outputSize.width / cropSize
        let drawSize = CGSize(
            width: image.size.width * imageScale * outputScale,
            height: image.size.height * imageScale * outputScale
        )
        let drawOrigin = CGPoint(
            x: (outputSize.width - drawSize.width) / 2 + offset.width * outputScale,
            y: (outputSize.height - drawSize.height) / 2 + offset.height * outputScale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let croppedImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }

        for quality in [0.82, 0.68, 0.52] {
            if let data = croppedImage.jpegData(compressionQuality: quality), data.count <= 1024 * 1024 {
                return data
            }
        }
        return nil
    }
}

private struct AccountProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var displayName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropSelection: AvatarCropSelection?
    @State private var isSaving = false
    @State private var isUploadingAvatar = false
    @State private var errorMessage: String?

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var initials: String {
        String(session.accountDisplayName.prefix(1)).uppercased()
    }

    private var canSave: Bool {
        (1...30).contains(normalizedDisplayName.count) && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 14) {
                            AccountAvatarView(
                                data: session.avatarData,
                                initials: initials,
                                size: 96
                            )

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                if isUploadingAvatar {
                                    ProgressView()
                                } else {
                                    Label("修改头像", systemImage: "photo")
                                }
                            }
                            .disabled(isUploadingAvatar)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("输入昵称", text: $displayName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("昵称")
                } footer: {
                    Text("昵称为 1 至 30 个字符")
                }
            }
            .navigationTitle("个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveDisplayName() }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("保存")
                    .disabled(!canSave)
                }
            }
            .onAppear {
                displayName = session.accountDisplayName
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await prepareAvatarCrop(from: item) }
            }
            .fullScreenCover(item: $cropSelection) { selection in
                AvatarCropView(image: selection.image) { avatarData in
                    Task { await uploadAvatar(avatarData) }
                }
            }
            .alert(
                "个人资料修改失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请稍后重试")
            }
        }
    }

    private func saveDisplayName() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await session.updateDisplayName(normalizedDisplayName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareAvatarCrop(from item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer {
            isUploadingAvatar = false
            selectedPhoto = nil
        }

        do {
            guard
                let originalData = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: originalData)
            else {
                errorMessage = "无法读取所选图片"
                return
            }
            cropSelection = AvatarCropSelection(image: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadAvatar(_ avatarData: Data) async {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            try await session.updateAvatar(avatarData)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isSuccessAlertPresented = false

    private var validationMessage: String? {
        if !newPassword.isEmpty && !(7...16).contains(newPassword.count) {
            return "新密码长度需为 7 至 16 位"
        }
        if !confirmation.isEmpty && newPassword != confirmation {
            return "两次输入的新密码不一致"
        }
        return nil
    }

    private var canSubmit: Bool {
        !oldPassword.isEmpty
            && (7...16).contains(newPassword.count)
            && newPassword == confirmation
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("输入当前密码", text: $oldPassword)
                        .textContentType(.password)
                } header: {
                    Text("当前密码")
                }

                Section {
                    SecureField("7 至 16 位新密码", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("再次输入新密码", text: $confirmation)
                        .textContentType(.newPassword)
                } header: {
                    Text("新密码")
                } footer: {
                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("完成")
                    .disabled(!canSubmit)
                }
            }
            .alert(
                "密码修改失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请稍后重试")
            }
            .alert("密码修改成功", isPresented: $isSuccessAlertPresented) {
                Button("重新登录") {
                    session.signOut()
                    dismiss()
                }
            } message: {
                Text("为了保护账号安全，请使用新密码重新登录")
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await session.changePassword(
                oldPassword: oldPassword,
                newPassword: newPassword
            )
            isSuccessAlertPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
