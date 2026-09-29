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
/// 差分規則の本体は imas-core (Rust) の `domain/setlist_diff.rs` にあり、
/// なぜ差分にするか (実測 606 ops → 1 op)・何を送らないかの設計意図もそちらに記載。
/// ここはエンティティ → 射影 Record (`SetlistItemDiffRow`) への詰め替えと、
/// 返ってきた index で自国の配列を引くことだけを担う薄いラッパ (1 操作 1 FFI 呼び出し)。
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
        let rows = items.map {
            SetlistItemDiffRow(id: $0.id, songId: $0.songId,
                               position: Int64($0.position), section: $0.section)
        }
        let originalRows = original.map { id, snapshot in
            SetlistItemDiffRow(id: id, songId: snapshot.songId,
                               position: Int64(snapshot.position), section: snapshot.section)
        }
        return setlistItemIndexesNeedingSync(items: rows, original: originalRows)
            .map { items[Int($0)] }
    }

    /// 送る必要のある出演者だけ返す (新規追加のみ)。順序は入力のまま。
    ///
    /// recordName の生成規則は呼び出し側の所有物なので、規則をここで適用して
    /// 文字列列にしてから 1 回の FFI 呼び出しで判定する。
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
        setlistPerformerIndexesNeedingSync(
            recordNames: performers.map(recordName),
            initialRecordNames: Array(initialRecordNames)
        ).map { performers[Int($0)] }
    }
}
