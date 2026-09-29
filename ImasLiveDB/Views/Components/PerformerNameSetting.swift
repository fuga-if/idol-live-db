import Foundation

/// セトリの歌唱者をどの名前で出すか — 閲覧者の好み。
///
/// **モードの列挙もラベルも保存値もここに無い。** 順・`raw`・文言はすべて
/// imas-core の `performerNameOptions()` が持ち、主/副の決め方は
/// `performerDisplayName` が持つ。ここにあるのは保存先の鍵と、
/// `PerformerRow` をコアの Record へ移す配管だけ。
///
/// 4 モードを Swift の enum に書き写していた頃は、同じラベルが
/// Swift / Kotlin / TS に 3 本あった (文言を直すと 1 面だけ古いまま残る)。
enum PerformerNamePref {
    /// `@AppStorage` の鍵。iOS / Android / Web で同じ文字列を使う。
    static let storageKey = "performer_name_mode"

    /// 設定画面に並べる選択肢 (順・保存値・文言)。
    static let options: [PerformerNameOption] = performerNameOptions()

    /// 未設定のときの保存値。コアの既定モードに対応する `raw`。
    static let defaultRaw: String = {
        let fallback = performerNameModeFromRaw(raw: nil)
        return options.first { $0.mode == fallback }?.raw ?? ""
    }()

    /// 保存値からモードへ。未知の値・未設定は既定 (アイドル名)。
    static func mode(_ raw: String) -> PerformerNameMode {
        performerNameModeFromRaw(raw: raw)
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
        _ mode: PerformerNameMode,
        isCharacterLive: Bool
    ) -> PerformerDisplayName {
        performerDisplayName(
            record: performerRecord,
            mode: mode,
            isCharacterLive: isCharacterLive
        )
    }
}

extension PerformerDisplayName {
    /// 2 段に積めない場所 (簡易表示・共有文) 向けの 1 行表記。
    /// 括弧の書き方はコアが決める (端末ごとに違う見た目にしない)。
    var joined: String { performerDisplayNameJoined(name: self) }
}

/// アイドルと、そのモードでの表示名を 1 組にしたもの。
///
/// 「アイドルの並び」と「歌唱者の行」を別々に持ち回ると、2 本が同じ人・同じ並びだと
/// いう不変条件を人が守ることになる。組むのは 1 箇所 (`SetlistRowView`) にする。
struct ResolvedPerformer: Identifiable {
    let idol: Idol
    let name: PerformerDisplayName

    var id: String { idol.id }
}
