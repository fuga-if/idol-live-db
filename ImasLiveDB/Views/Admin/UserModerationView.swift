import os
import SwiftUI

/// admin 専用: 1 ユーザーのモデレーション画面。
///
/// 確定モデル (即時オープン編集 + 事後モデレーション) における荒らし対処の中枢。
///   1. そのユーザーの編集履歴を一覧 (`GET /admin/users/:id/edits`) して被害範囲を確認
///   2. BAN (書き込み遮断) … `POST /admin/ban`
///   3. 全編集の一括 revert (データ修復) … `POST /admin/revert-user`
///      - まず dryRun=true でプレビュー (CloudKit を触らず巻き戻し対象 + 予測 outcome を集計)
///      - 確認後 dryRun=false で実行。同時 BAN も選べる
///      - 他ユーザーの後続編集はサーバ既定で常に保護 (巻き戻し対象から自動除外)
///
/// 遷移元: 確定契約 §1 で公開フィードは編集者匿名性のため editorId を返さないため、
/// admin は MyPage の管理者セクションから対象ユーザー ID を指定して開く。
/// admin 判定は AuthService.isAdmin (起動時 refreshMe で最新化) で UI ゲートし、
/// 実権限はサーバ checkIsAdmin が再判定する (二重ガード)。
struct UserModerationView: View {
    let userId: String
    /// 表示用の編集者ラベル (呼び出し側が分かっていれば渡す。通常はサーバの
    /// `GET /admin/users/:id/edits` の user.displayName で上書きされる)。
    var displayName: String?

    @State private var edits: [AdminUserEdit] = []
    @State private var total = 0
    /// サーバ権威の表示名 (GET /admin/users/:id/edits の user.displayName)。
    @State private var serverDisplayName: String?
    @State private var isLoading = false
    @State private var loadError: String?

    // revert フロー
    @State private var alsoBan = true
    @State private var preview: UserRevertResult?
    /// preview が dry_run プレビュー由来 (true) か実行結果 (false) かを区別する。
    @State private var isPreviewSnapshot = false
    @State private var isPreviewing = false
    @State private var isExecuting = false
    @State private var showExecuteConfirm = false
    @State private var resultMessage: String?

    // 単独 BAN
    @State private var isBanning = false
    @State private var didBan = false

    @State private var actionError: String?

    var body: some View {
        List {
            summarySection
            moderationSection
            if let preview { previewSection(preview) }
            editsSection
        }
        .navigationTitle("ユーザー管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { if edits.isEmpty { await loadEdits() } }
        .refreshable { await loadEdits() }
        .confirmationDialog(
            "全編集を取り消しますか？",
            isPresented: $showExecuteConfirm,
            titleVisibility: .visible
        ) {
            Button(alsoBan ? "取り消して BAN する" : "取り消す", role: .destructive) {
                AppAnalytics.tap("user_moderation.execute_revert")
                Task { await executeRevert() }
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text(executeConfirmMessage)
        }
        .alert("完了", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("エラー", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .trackScreen("user_moderation")
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(serverDisplayName ?? displayName ?? "ユーザー")
                    .font(.imasHeadline)
                Text("ID: …\(userIdSuffix)")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .textSelection(.enabled)
                if didBan {
                    Label("BAN 済み", systemImage: "nosign")
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("対象ユーザー")
        } footer: {
            Text("編集件数: \(total) 件")
        }
    }

    // MARK: - Moderation actions

    @ViewBuilder
    private var moderationSection: some View {
        Section {
            Toggle("取り消しと同時に BAN する", isOn: $alsoBan)

            Button {
                AppAnalytics.tap("user_moderation.preview_revert")
                Task { await runPreview() }
            } label: {
                HStack {
                    Label("取り消し対象をプレビュー", systemImage: "list.bullet.rectangle")
                    if isPreviewing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPreviewing || isExecuting)

            Button(role: .destructive) {
                AppAnalytics.tap("user_moderation.revert_tap")
                showExecuteConfirm = true
            } label: {
                HStack {
                    Label("全編集を取り消す", systemImage: "arrow.uturn.backward.circle")
                    if isExecuting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExecuting || isPreviewing || total == 0)

            Button(role: .destructive) {
                AppAnalytics.tap("user_moderation.ban_only")
                Task { await banOnly() }
            } label: {
                HStack {
                    Label(didBan ? "BAN 済み" : "BAN のみ (書き込み遮断)", systemImage: "nosign")
                    if isBanning {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isBanning || didBan)
        } header: {
            Text("モデレーション")
        } footer: {
            Text("他ユーザーが後から編集した項目は自動で保護され、巻き戻し対象から除外されます。")
        }
    }

    // MARK: - Preview (dry run)

    @ViewBuilder
    private func previewSection(_ p: UserRevertResult) -> some View {
        Section {
            revertCounts(p)
            ForEach(p.items.prefix(50)) { item in
                HStack(spacing: 10) {
                    Image(systemName: outcomeIcon(item.outcome))
                        .font(.imasCaption)
                        .foregroundStyle(item.outcome.color)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("編集 #\(item.batchId)")
                            .font(.imasSubhead.monospacedDigit())
                        if let reason = item.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(item.outcome.label)
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(item.outcome.color)
                }
            }
        } header: {
            Text(isPreviewSnapshot ? "取り消しプレビュー (未実行)" : "取り消し結果")
        }
    }

    private func outcomeIcon(_ outcome: RevertOutcome) -> String {
        if outcome.isReverted { return "arrow.uturn.backward.circle.fill" }
        if outcome.isFailed { return "exclamationmark.triangle.fill" }
        return "shield.lefthalf.filled" // 保護スキップ系
    }

    @ViewBuilder
    private func revertCounts(_ p: UserRevertResult) -> some View {
        // スキップ = 競合保護 (skipped) + 既 revert (alreadyReverted)。どちらも巻き戻しを
        // 安全に見送ったケースなので 1 つの「スキップ」にまとめて見せる。
        HStack(spacing: 16) {
            countPill("巻き戻し", p.reverted, .green)
            countPill("スキップ", p.skipped + p.alreadyReverted, .secondary)
            countPill("失敗", p.failed, .red)
        }
        .frame(maxWidth: .infinity)
    }

    private func countPill(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.imasTitle3.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edits list

    @ViewBuilder
    private var editsSection: some View {
        Section("最近の編集") {
            if isLoading && edits.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let loadError, edits.isEmpty {
                Text(loadError)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
            } else if edits.isEmpty {
                Text("編集はありません")
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
            } else {
                ForEach(edits) { edit in
                    HStack(spacing: 10) {
                        Image(systemName: EditFeedFormat.recordTypeDesign(edit.recordType).icon)
                            .font(.imasCallout)
                            .foregroundStyle(EditFeedFormat.recordTypeDesign(edit.recordType).color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(EditFeedFormat.recordTypeLabel(edit.recordType))
                                    .font(.imasSubhead)
                                    .lineLimit(1)
                                if edit.opCount > 1 {
                                    Text("\(edit.opCount)件")
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                }
                            }
                            Text(EditFeedFormat.relativeTime(edit.createdDate))
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                        }
                        Spacer()
                        if edit.reverted {
                            Text("差戻し済み")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var userIdSuffix: String {
        String(userId.suffix(8))
    }

    private var executeConfirmMessage: String {
        var msg = "このユーザーの編集 \(total) 件を編集前の状態に戻します。他ユーザーが後から編集した項目は自動で保護されます。"
        if alsoBan { msg += " 同時にこのユーザーを BAN します。" }
        return msg
    }

    // MARK: - Actions

    private func loadEdits() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await AdminModerationService.shared.userEdits(userId: userId, offset: 0, limit: 50)
            edits = page.edits
            total = page.total
            serverDisplayName = page.user?.displayName
            // サーバ権威の BAN 状態を反映 (既に BAN 済みのユーザーは BAN ボタンを畳む)。
            if page.user?.isBanned == true { didBan = true }
        } catch {
            loadError = friendlyError(error)
            Logger.community.error("admin_user_edits_failed: \(error.localizedDescription)")
        }
    }

    private func runPreview() async {
        guard !isPreviewing else { return }
        isPreviewing = true
        defer { isPreviewing = false }
        do {
            // dry_run はプレビューのみ。CloudKit を一切叩かず予測 outcome だけ集計する
            // (banned=false 固定)。同時 BAN は実行時にだけ効かせるため alsoBan=false で呼ぶ。
            let result = try await AdminModerationService.shared.revertUser(
                userId: userId,
                alsoBan: false,
                dryRun: true
            )
            preview = result
            isPreviewSnapshot = true
        } catch {
            actionError = friendlyError(error)
        }
    }

    private func executeRevert() async {
        guard !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }
        do {
            let result = try await AdminModerationService.shared.revertUser(
                userId: userId,
                alsoBan: alsoBan,
                dryRun: false
            )
            preview = result
            isPreviewSnapshot = false
            if result.banned { didBan = true }
            let skippedTotal = result.skipped + result.alreadyReverted
            resultMessage = "巻き戻し \(result.reverted) 件 / スキップ \(skippedTotal) 件 / 失敗 \(result.failed) 件"
                + (result.banned ? "\nこのユーザーを BAN しました。" : "")
            await loadEdits()
        } catch {
            actionError = friendlyError(error)
        }
    }

    private func banOnly() async {
        guard !isBanning else { return }
        isBanning = true
        defer { isBanning = false }
        do {
            try await AdminModerationService.shared.ban(userId: userId)
            didBan = true
            resultMessage = "このユーザーを BAN しました (書き込み遮断)。編集の巻き戻しは別途実行できます。"
        } catch {
            actionError = friendlyError(error)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if case APIClientError.notAuthorized = error {
            return "権限がありません (管理者のみ)。"
        }
        return "操作に失敗しました: \(error.localizedDescription)"
    }
}
