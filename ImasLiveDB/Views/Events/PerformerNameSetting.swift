import Foundation

/// セトリの歌唱者をどの名前で出すか — 閲覧者の好み。
///
/// **規則は持たない。** どちらを主にしてどちらを併記するかは imas-core の
/// `performerDisplayName` が決めており、ここが持つのは保存の形と選択肢のラベルだけ。
/// `@AppStorage` に載せるので raw は String で固定する (Int 添字にすると
/// 選択肢を並べ替えた瞬間に既存ユーザーの設定が別のものに化ける)。
enum PerformerNameSetting: String, CaseIterable, Identifiable, Sendable {
    /// アイドル名だけ。既定 (これまでの簡易表示と同じ)。
    case idol
    /// 現任 CV 名だけ。
    case cast
    /// アイドル名 + CV 名。
    case both
    /// 公演に合わせる (キャラライブ = アイドル名 / 声優ライブ = CV 名)。
    case show

    /// `@AppStorage` の鍵。読む側と書く側で文字列を二重に書かないための 1 箇所。
    static let storageKey = "performer_name_mode"

    var id: String { rawValue }

    /// コアの列挙への対応。
    var mode: PerformerNameMode {
        switch self {
        case .idol: .idolOnly
        case .cast: .castOnly
        case .both: .both
        case .show: .followShow
        }
    }

    var label: String {
        switch self {
        case .idol: "アイドル名"
        case .cast: "CV名"
        case .both: "アイドル名 + CV名"
        case .show: "公演に合わせる"
        }
    }
}

extension PerformerRow {
    /// コアに渡す形。`PerformerRow.name` は SQL 側で現任 CV に解決済みの表示名。
    ///
    /// `idolId` が nil なのはアイドル行に紐づかない演者 (ゲスト等)。その場合は
    /// アイドル名も CV 名も同じ文字列になり、どのモードでも同じ名前が出る。
    private var performerRecord: SetlistPerformerRecord {
        SetlistPerformerRecord(
            idolId: idolId ?? id,
            displayName: name,
            idolName: idolName ?? name,
            idolColor: idolColor
        )
    }

    /// 選んだモードでの表示名 (主と、必要なら副)。
    func displayName(
        _ setting: PerformerNameSetting,
        isCharacterLive: Bool
    ) -> PerformerDisplayName {
        performerDisplayName(
            record: performerRecord,
            mode: setting.mode,
            isCharacterLive: isCharacterLive
        )
    }
}

extension PerformerDisplayName {
    /// 1 行に収めるときの表記。副があれば括弧で添える。
    ///
    /// シンプル表示やコピー用の文字列のように、2 段に積めない場所で使う。
    /// 積める場所 (通常行のチップ) は `primary` / `secondary` をそのまま出す。
    var joined: String {
        guard let secondary else { return primary }
        return "\(primary)(\(secondary))"
    }
}
