import os
import SwiftUI

/// 自分の編集 batch 一覧 (`GET /me/edits`) と、本人による各 batch の revert (`POST /edits/:batchId/revert`)。
///
/// 確定モデル: 即時オープン編集 + 事後モデレーション。本人 revert を v1 で開放しているため、
/// ユーザーは自分が行った編集を後から打ち消せる (誤編集の自己修正)。
/// - revert は CloudKit ハード削除を伝播しないため、サーバ側で soft delete / before
///   スナップショットへの forceUpdate として安全に逆適用される (契約 v2 #1)。
/// - 既に revert 済み / revert 操作自体の batch は再 revert させない (`EditFeedEntry.isRevertable`)。
/// - revert 成功後はその行を「差戻し済み」状態に楽観更新し、リストからは消さずに残す
///   (履歴の連続性を保つ。サーバも revert を新規 edit_history として記録する)。
struct MyEditsView: View {
    @State private var entries: [EditFeedEntry] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    /// revert 確認中の対象 batch。
    @State private var revertTarget: EditFeedEntry?
    /// revert 実行中の batchId (二度押し防止 + スピナー表示)。
    @State private var revertingId: Int?
    /// 楽観的に revert 済みへ倒した batchId 群 (サーバ反映成功で確定)。
    @State private var locallyReverted: Set<Int> = []

    private let limit = 20

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(entries) { entry in
                    MyEditRow(
                        entry: entry,
                        isReverted: isReverted(entry),
                        isReverting: revertingId == entry.id,
                        onRevert: { revertTarget = entry }
                    )
                    .onAppear { maybeLoadMore(currentItem: entry) }
                }

                if isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DS.bg)
        .navigationTitle("自分の編集")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("my_edits")
        .overlay {
            if isLoading && entries.isEmpty {
                ProgressView("読み込み中...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if entries.isEmpty && !isLoading {
                EmptyStateCard(
                    icon: "square.and.pencil",
                    title: "まだ編集がありません",
                    message: "ライブ・楽曲・セトリを編集すると、ここに履歴が残り、後から取り消せます。"
                )
            }
        }
        .refreshable { await reload() }
        .task {
            if entries.isEmpty { await reload() }
        }
        .confirmationDialog(
            "この編集を取り消しますか？",
            isPresented: Binding(
                get: { revertTarget != nil },
                set: { if !$0 { revertTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: revertTarget
        ) { target in
            Button("取り消す", role: .destructive) {
                Task { await revert(target) }
            }
            Button("やめる", role: .cancel) { revertTarget = nil }
        } message: { target in
            Text(revertMessage(for: target))
        }
        .alert("エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - State resolution

    private func isReverted(_ entry: EditFeedEntry) -> Bool {
        entry.reverted || locallyReverted.contains(entry.id)
    }

    private func revertMessage(for entry: EditFeedEntry) -> String {
        let label = EditFeedFormat.recordTypeLabel(entry.recordType)
        return "「\(entry.summary ?? label)」を編集前の状態に戻します。この操作も履歴に記録されます。"
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        page = 1
        do {
            let result = try await EditFeedService.shared.fetchEdits(
                page: 1, limit: limit, mine: true
            )
            entries = result.items
            locallyReverted.removeAll()
            hasMore = result.items.count >= limit
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func maybeLoadMore(currentItem: EditFeedEntry) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard let idx = entries.firstIndex(where: { $0.id == currentItem.id }),
              idx >= entries.count - 3 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        do {
            let result = try await EditFeedService.shared.fetchEdits(
                page: next, limit: limit, mine: true
            )
            let existing = Set(entries.map(\.id))
            let fresh = result.items.filter { !existing.contains($0.id) }
            entries.append(contentsOf: fresh)
            page = next
            hasMore = result.items.count >= limit
        } catch {
            Logger.community.error("my_edits_load_more_failed: \(error.localizedDescription)")
            hasMore = false
        }
    }

    // MARK: - Revert

    private func revert(_ entry: EditFeedEntry) async {
        revertTarget = nil
        guard revertingId == nil else { return }
        revertingId = entry.id
        defer { revertingId = nil }
        do {
            let outcome = try await AdminModerationService.shared.revertBatch(batchId: entry.id)
            switch outcome {
            case .reverted, .alreadyReverted:
                // 楽観反映: 行は消さず「差戻し済み」へ。実データは次回同期で戻る。
                locallyReverted.insert(entry.id)
            case .skippedConflict:
                // 後続編集があり巻き戻せなかった (本人 revert は競合スキップ固定)。状態は変えない。
                errorMessage = "別のユーザーがこの後に編集したため取り消せませんでした。"
            default:
                errorMessage = "取り消せませんでした (\(outcome.label))。"
            }
        } catch {
            if case APIClientError.notAuthorized = error {
                errorMessage = "認証の有効期限が切れています。再度サインインしてください。"
            } else {
                errorMessage = "取り消しに失敗しました: \(error.localizedDescription)"
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        if case APIClientError.rateLimited = error {
            return "操作が多すぎます。しばらく待ってからお試しください。"
        }
        return "読み込みに失敗しました: \(error.localizedDescription)"
    }
}

// MARK: - Row

private struct MyEditRow: View {
    let entry: EditFeedEntry
    let isReverted: Bool
    let isReverting: Bool
    let onRevert: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EditTypeIcon(recordType: entry.recordType)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    OpBadge(op: entry.op)
                    if isReverted {
                        Text("差戻し済み")
                            .font(.imasScaled(11).weight(.semibold))
                            .foregroundStyle(DS.ink2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(DS.fill, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Text(EditFeedFormat.relativeTime(entry.createdDate))
                        .font(.imasScaled(11))
                        .foregroundStyle(DS.ink2)
                }

                Text(entry.summary ?? EditFeedFormat.recordTypeLabel(entry.recordType))
                    .font(.imasSubhead)
                    .foregroundStyle(isReverted ? AnyShapeStyle(DS.ink2) : AnyShapeStyle(DS.ink))
                    .strikethrough(isReverted, color: DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                footer
            }
        }
        .padding(14)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if entry.goodCount > 0 {
                Label("\(entry.goodCount)", systemImage: "hands.clap.fill")
                    .font(.imasCaption)
                    .foregroundStyle(.pink)
            }
            Spacer()
            if isReverting {
                ProgressView()
            } else if entry.isRevertable && !isReverted {
                Button(role: .destructive) {
                    AppAnalytics.tap("my_edits.revert")
                    onRevert()
                } label: {
                    Label("取り消す", systemImage: "arrow.uturn.backward")
                        .font(.imasCaption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Shared small components

/// record_type のアイコンチップ (RecentEditsView の EditRecordIcon と同一の見た目)。
struct EditTypeIcon: View {
    let recordType: String

    var body: some View {
        let design = EditFeedFormat.recordTypeDesign(recordType)
        Circle()
            .fill(design.color.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: design.icon)
                    .font(.imasScaled( 16, weight: .medium))
                    .foregroundStyle(design.color)
            }
            .accessibilityHidden(true)
    }
}

/// op バッジ (RecentEditsView の EditOpBadge と同一の見た目)。
struct OpBadge: View {
    let op: String

    var body: some View {
        let (label, color) = EditFeedFormat.opDesign(op)
        Text(label)
            .font(.imasScaled(11).weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
