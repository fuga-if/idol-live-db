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
        let times = EditFeedFormat.relativeTimes(entries.map { ($0.id, $0.createdDate) })
        return ScrollView {
            LazyVStack(spacing: DS.Space.gapLoose) {
                ForEach(entries) { entry in
                    HistoryRow(entry: entry, recordType: recordType, timeLabel: times[entry.id] ?? "")
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp4)
        }
        .background(DS.bg)
        .navigationTitle("編集履歴")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && entries.isEmpty {
                ImasLoadingState(title: "読み込み中...")
            } else if entries.isEmpty && !isLoading && errorMessage == nil {
                ImasEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "編集履歴はありません",
                    message: "このデータがまだ一度も編集されていないか、編集が反映待ちです。"
                )
            } else if let errorMessage, entries.isEmpty {
                ImasEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "読み込みに失敗しました",
                    message: errorMessage,
                    actionTitle: "再試行",
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
    /// 相対時刻 (一覧がまとめて作る)。
    let timeLabel: String

    var body: some View {
        ImasCard {
            ImasRecordRow(
                systemImage: "pencil",
                title: title,
                subtitle: entry.editorDisplayLabel,
                badges: badges,
                // 時刻は独立した値として末尾に出す (長い表示名でも隠れない)。
                trailing: .value(timeLabel)
            ) {
                if case .update = Op(entry.op), !entry.changedFields.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        ForEach(entry.changedFields, id: \.self) { field in
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
    }

    /// 操作の種類 (`EditFeedFormat.opBadgeKind` と対にする、画面固有の分岐用)。
    private enum Op { case create, delete, snapshot, update
        init(_ raw: String) {
            switch raw {
            case "create": self = .create
            case "delete": self = .delete
            case "snapshot": self = .snapshot
            default: self = .update
            }
        }
    }

    private var title: String {
        switch Op(entry.op) {
        case .create: return "新規追加されました"
        case .delete: return "削除されました"
        case .snapshot: return "セットリスト全体が更新されました"
        case .update: return "内容が更新されました"
        }
    }

    private var badges: [ImasBadgeSpec] {
        var specs = [ImasBadgeSpec(text: EditFeedFormat.opLabel(entry.op), kind: EditFeedFormat.opBadgeKind(entry.op))]
        if entry.source == "revert" || entry.source == "admin", entry.op != "revert" {
            specs.append(ImasBadgeSpec(text: entry.source == "admin" ? "運営" : "巻き戻し", kind: .attention))
        }
        if entry.reverted {
            specs.append(ImasBadgeSpec(text: "差戻し済み", kind: .negative))
        }
        return specs
    }
}

// MARK: - Field diff row

private struct FieldDiffRow: View {
    let label: String
    let before: JSONValue?
    let after: JSONValue?

    var body: some View {
        ImasCard(style: .inset, padding: DS.Space.gap) {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(label).imasText(.sectionLabel)
                HStack(alignment: .top, spacing: DS.Space.gapTight) {
                    Text(before?.displayString ?? "(なし)")
                        .imasText(.meta)
                        .strikethrough(true, color: DS.ink3)
                        .lineLimit(2)
                    Image(systemName: "arrow.right").imasText(.meta)
                    Text(after?.displayString ?? "(なし)").imasText(.note, color: DS.ink).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        "releaseDate": "初出",
        "streamingDate": "配信開始日",
        "cdReleaseDate": "CD 発売日",
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
