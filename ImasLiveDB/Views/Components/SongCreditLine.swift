import Foundation

/// 1 行に出す歌唱者の表記。全体曲の長い表記 (`765 MILLION ALLSTARS 天海春香、…`) を畳む。
///
/// 回帰 (2026-10-31): 一覧の副題・関連曲・投票・タグの曲行が `singerLabel` を生で出していて、
/// 全体曲では全員の名前が行を埋めていた。規則はコア (`songCreditLabel` / `compactSingerLabel`) に
/// あるので、画面はここを通して読むだけにする。全員の顔ぶれは曲の詳細の「歌唱アイドル」が持つ。
extension Song {
    /// ユニット名 → 名義 (畳んだ `singerLabel`)。どちらも無ければ nil。
    var creditLine: String? {
        let label = songCreditLabel(unitName: unitName, singerLabel: singerLabel, artistNames: "")
        return label.isEmpty ? nil : label
    }

    /// 名義 (畳んだ `singerLabel`) → ユニット名。歌唱者の表記を先に見せたい行
    /// (関連曲・ソートメーカーなど、これまで `singerLabel ?? unitName` だった所) 用。
    var singerLine: String? {
        guard let label = singerLabel?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return unitName }
        let compact = compactSingerLabel(label: label)
        // 畳んだときはユニット名を先に使う (表記の括弧が崩れている曲でも名義が正しく出る)。
        if compact != label, let unit = unitName, !unit.isEmpty { return unit }
        return compact
    }
}
