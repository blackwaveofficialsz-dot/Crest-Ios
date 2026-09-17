import SwiftUI

/// 独立的历史对话搜索页，只过滤当前已经加载的会话标题。
struct ConversationSearchView: View {
    @FocusState.Binding var isSearchFocused: Bool

    let sessions: [ChatSessionSummary]
    let activeSessionID: String?
    let isLoading: Bool
    let onOpenSidebar: () -> Void
    let onSelectSession: (ChatSessionSummary) -> Void

    @State private var searchText = ""

    private var filteredSessions: [ChatSessionSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider()
                .overlay(AppColors.border)

            results
        }
        .foregroundStyle(AppColors.primaryText)
        .background(AppColors.background.ignoresSafeArea())
        .task {
            await Task.yield()
            isSearchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            SidebarOpenButton(action: onOpenSidebar)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.secondaryText)

                TextField("搜索对话内容", text: $searchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.tertiaryText)
                    }
                    .accessibilityLabel("清除搜索内容")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var results: some View {
        if isLoading && sessions.isEmpty {
            ProgressView()
                .tint(AppColors.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSessions.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text(searchText.isEmpty ? "最近" : "搜索结果")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)

                    ForEach(filteredSessions) { item in
                        Button {
                            onSelectSession(item)
                        } label: {
                            Text(item.title)
                                .font(.body)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(
                                    item.sessionID == activeSessionID
                                        ? AppColors.surface
                                        : .clear,
                                    in: RoundedRectangle(cornerRadius: 25, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
