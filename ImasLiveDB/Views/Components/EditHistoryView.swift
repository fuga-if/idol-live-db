import os
import SwiftUI

/// 任意のマスタレコード (Event / Show / Song / Idol / SetlistItem 等) の編集履歴ビューア。
/// `GET /master/:recordType/:recordName/history` を新しい順で読み、誰がいつ何を変えたかを見せる。
///
/// 各 DetailView の toolbar / メニューから `EditHistoryView(recordType:recordName:title:)` を
/// sheet または NavigationLink で開く。オープン編集モデルでは「相互監視」が荒らし抑止の柱なので、
/// 履歴をユーザーに広く公開する (誰でも閲覧可。編集者は表示名のみ・メール非露出)。
///
/// 表示方針:
/// - update: 変更されたフィールドを「ラベル: 旧 → 新」で列挙 (changed_fields + before/after diff)。
/// - create: 「新規追加」。delete: 「削除」。snapshot: 「セットリスト更新」(ShowSetlist 丸ごと)。
/// - revert 済みの編集には「差戻し済み」ラベルを付ける。
struct EditHistoryView: View {
    let recordType: String
    let recordName: String
    /// 画面タイトルに添えるレコード名 (例: 公演名 / 曲名)。省略時は record_type ラベル。
    var title: String?

    @State private var entries: [RecordHistoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(entries) { entry in
                    HistoryRow(entry: entry, recordType: recordType)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DS.bg)
        .navigationTitle("編集履歴")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && entries.isEmpty {
                ProgressView("読み込み中...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if entries.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateCard(
                    icon: "clock.arrow.circlepath",
                    title: "編集履歴はありません",
                    message: "このデータがまだ一度も編集されていないか、編集が反映待ちです。"
                )
            } else if let errorMessage, entries.isEmpty {
                EmptyStateCard(
                    icon: "exclamationmark.triangle",
                    title: "読み込みに失敗しました",
                    message: errorMessage,
                    actionLabel: "再試行",
                    action: { Task { await reload() } }
                )
            }
        }
        .refreshable { await reload() }
        .task {
            if entries.isEmpty { await reload() }
        }
        .trackScreen("edit_history")
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = try await EditFeedService.shared.recordHistory(
                recordType: recordType,
                recordName: recordName
            )
        } catch {
            errorMessage = error.localizedDescription
            Logger.community.error("record_history_failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - History row

private struct HistoryRow: View {
    let entry: RecordHistoryEntry
    let recordType: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 編集者 + op バッジ + 相対時刻
            HStack(spacing: 6) {
                Text(entry.editorDisplayLabel)
                    .font(.imasSubhead.weight(.semibold))
                    .lineLimit(1)
                OpBadge(op: entry.op)
                if entry.source == "revert" || entry.source == "admin", entry.op != "revert" {
                    sourceBadge
                }
                if entry.reverted {
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

            diffBody
        }
        .padding(14)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var sourceBadge: some View {
        Text(entry.source == "admin" ? "運営" : "巻き戻し")
            .font(.imasScaled(11).weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private var diffBody: some View {
        switch entry.op {
        case "create":
            Text("新規追加されました")
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
        case "delete":
            Text("削除されました")
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
        case "snapshot":
            Text("セットリスト全体が更新されました")
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
        default:
            updateDiff
        }
    }

    /// update の変更フィールドを「ラベル: 旧 → 新」で列挙する。
    @ViewBuilder
    private var updateDiff: some View {
        let fields = entry.changedFields
        if fields.isEmpty {
            Text("内容が更新されました")
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(fields, id: \.self) { field in
                    FieldDiffRow(
                        label: EditFieldLabel.label(for: field),
                        before: entry.before?[field],
                        after: entry.after?[field]
                    )
                }
            }
        }
    }
}

// MARK: - Field diff row

private struct FieldDiffRow: View {
    let label: String
    let before: JSONValue?
    let after: JSONValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.imasCaption.weight(.semibold))
                .foregroundStyle(DS.ink2)
            HStack(alignment: .top, spacing: 6) {
                Text(before?.displayString ?? "(なし)")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .strikethrough(true, color: DS.ink3)
                    .lineLimit(2)
                Image(systemName: "arrow.right")
                    .font(.imasScaled(11))
                    .foregroundStyle(DS.ink3)
                Text(after?.displayString ?? "(なし)")
                    .font(.imasCaption.weight(.medium))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DS.surface2, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Field label mapping

/// CloudKit フィールド名 (camelCase) → 日本語ラベル。履歴 diff の見出しに使う。
/// オープン編集で実際に編集対象になるフィールド (各 *EditView の fields) を網羅する。
/// 未知のフィールドはキー名をそのまま見せる (網羅漏れでも壊れない)。
enum EditFieldLabel {
    private static let map: [String: String] = [
        // 共通
        "modifiedAt": "更新日時",
        "deletedAt": "削除フラグ",
        "brandId": "ブランド",
        "name": "名称",
        "title": "タイトル",
        "sortOrder": "並び順",
        "position": "順番",
        // Event
        "startDate": "開始日",
        "endDate": "終了日",
        "venue": "会場",
        "city": "都市",
        "officialUrl": "公式URL",
        "eventType": "種別",
        // Show
        "eventId": "ライブ",
        "showDate": "公演日",
        "openTime": "開場",
        "startTime": "開演",
        "dayLabel": "公演ラベル",
        // Song
        "appleMusicId": "Apple Music ID",
        "artworkUrl": "ジャケット画像",
        "releaseDate": "発売日",
        "kana": "読み (かな)",
        "romaji": "ローマ字",
        // SetlistItem
        "songId": "曲",
        "showId": "公演",
        "blockLabel": "ブロック",
        "note": "メモ",
        "isEncore": "アンコール",
        "isMc": "MC",
        // SetlistPerformer / ShowCast
        "idolId": "アイドル",
        "castId": "キャスト",
        "setlistItemId": "セトリ項目",
        // Idol
        "kanaName": "読み (かな)",
        "color": "イメージカラー",
        "height": "身長",
        "birthday": "誕生日",
        "bloodType": "血液型",
        "age": "年齢",
        "cv": "CV",
    ]

    static func label(for field: String) -> String {
        map[field] ?? field
    }
}
