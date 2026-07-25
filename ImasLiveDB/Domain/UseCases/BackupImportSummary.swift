import Foundation

/// バックアップ復元 (引き継ぎコード / ファイル) の結果をユーザー向け文面にする。
///
/// 復元は「担当・お気に入り・マイタグ・投票履歴」という**クラウドに無い端末ローカル唯一
/// データ**を戻す操作で、何がどれだけ入ったかを黙っていると成功したのか分からない。
/// 一方で 0 件の項目まで並べるとノイズになるので、**入ったものだけ**を足していく。
///
/// - Parameters:
///   - addedMarks: 追加された担当/お気に入り/メモ/参加済みの件数。
///   - addedVotes: 追加された投票履歴の件数。
///   - addedPersonalTags: 追加されたマイタグの件数 (0 なら文面に出さない)。
///   - skippedMarks: 形式不正で取り込めなかった件数 (0 なら出さない)。
///   - deviceIdRestored: 端末 ID まで復元したか。
func backupImportSummary(
    addedMarks: Int,
    addedVotes: Int,
    addedPersonalTags: Int,
    skippedMarks: Int,
    deviceIdRestored: Bool
) -> String {
    var message = "担当/お気に入り等を \(addedMarks) 件、投票履歴を \(addedVotes) 件 追加しました。"
    if addedPersonalTags > 0 {
        message += "\nマイタグを \(addedPersonalTags) 件 追加しました。"
    }
    if skippedMarks > 0 {
        message += "\n(\(skippedMarks) 件は形式不正のためスキップされました)"
    }
    if deviceIdRestored {
        message += "\n端末IDも復元しました。"
    }
    return message
}
