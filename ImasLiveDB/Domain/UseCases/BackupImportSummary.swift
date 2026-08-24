import Foundation

/// バックアップ復元 (引き継ぎコード / ファイル) の結果をユーザー向け文面にする。
///
/// 文面の組み立て本体は imas-core (Rust) の `domain/backup_import_summary.rs` にある。
/// 「主目的の担当/投票は 0 件でも出す」「マイタグ/スキップは入ったときだけ出す」
/// という判断と行順の安定性はそちらでテスト済み。
/// ここは Swift の `Int` を FFI の `Int64` へ橋渡しするだけの薄いラッパ
/// (生成バインディングの同名関数とは引数型で区別されるオーバーロード)。
func backupImportSummary(
    addedMarks: Int,
    addedVotes: Int,
    addedPersonalTags: Int,
    skippedMarks: Int,
    deviceIdRestored: Bool
) -> String {
    backupImportSummary(
        addedMarks: Int64(addedMarks),
        addedVotes: Int64(addedVotes),
        addedPersonalTags: Int64(addedPersonalTags),
        skippedMarks: Int64(skippedMarks),
        deviceIdRestored: deviceIdRestored
    )
}
