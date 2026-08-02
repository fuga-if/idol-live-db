import Foundation

/// 差分判定に使う、編集前のセトリ行の状態。
///
/// サーバに送る field (`songId` / `position` / `section`) だけを持つ。
/// 表示用の曲名やジャケ URL は編集対象ではないので比較に入れない。
struct SetlistItemSnapshot: Equatable {
    var songId: String
    var position: Int
    var section: String?

    init(songId: String, position: Int, section: String?) {
        self.songId = songId
        self.position = position
        self.section = section
    }
}

/// セトリ編集で「実際に送る必要があるもの」だけを選ぶ。
///
/// ## なぜ差分にするか
///
/// 以前は 1 曲直すだけでも全曲・全出演者を送っていた。本番マスタ実測でセトリ登録済み
/// 1252 公演のうち 403 件 (32.2%) が 50 ops 超、最大 606 ops。これが
/// - 一般ユーザーの修正リクエストが op 上限で送れない
/// - admin の直接編集も上限 1000 に迫る
/// - GitHub issue が肥大してコメント分割が必要になる
/// の共通原因だった。
///
/// ## 送らないもの
///
/// - **値が変わっていない item**: 同じ値で update しても結果は変わらない。
/// - **既存の出演者すべて**: `SetlistPerformer` は `(setlistItemId, idolId)` の 2 つしか
///   持たず、recordName がその 2 つから決まる。つまり既存出演者の update は
///   「recordName に入っている値を同じ値で書く」だけで、変化しようがない。
///   出演者は新規追加 (create) と削除 (delete) しか意味を持たない。
///
/// - Note: 送らないぶん、ローカルとサーバがずれていても「全部送り直して直す」効果は
///   失われる。ずれの修復は CloudKit 同期の役目で、編集リクエストの役目ではない。
enum SetlistDiff {

    /// 送る必要のある item だけ返す (新規 + 値が変わったもの)。順序は入力のまま。
    ///
    /// - Parameters:
    ///   - items: 編集後の全 item。
    ///   - original: 編集前のスナップショット (item id → 状態)。ここに無い id は新規。
    static func itemsNeedingSync(
        items: [SetlistItem],
        original: [String: SetlistItemSnapshot]
    ) -> [SetlistItem] {
        items.filter { item in
            guard let before = original[item.id] else { return true }  // 新規
            return SetlistItemSnapshot(
                songId: item.songId, position: item.position, section: item.section
            ) != before
        }
    }

    /// 送る必要のある出演者だけ返す (新規追加のみ)。順序は入力のまま。
    ///
    /// - Parameters:
    ///   - performers: 編集後の全出演者。
    ///   - initialRecordNames: 編集前に存在した出演者の recordName 集合。
    ///   - recordName: 出演者から recordName を作る規則 (呼び出し側と同じものを渡す)。
    static func performersNeedingSync(
        performers: [SetlistPerformer],
        initialRecordNames: Set<String>,
        recordName: (SetlistPerformer) -> String
    ) -> [SetlistPerformer] {
        performers.filter { !initialRecordNames.contains(recordName($0)) }
    }
}
