import Foundation

/// 過去の披露実績から出した「この曲まわりの傾向」。**予想ではなく実績**。
///
/// 共有コア (`imas-core/src/domain/performance_stats.rs`) がセトリ 13,777 件・
/// 出演者 60,383 件を走査して出す。事前計算も保存もしない (保存すると master 更新の
/// たびに作り直す手間と、古い値を配る事故が増える)。スナップショットが無いときは
/// 同じ数え方の SQL (`AppDatabase+PerformanceEvidenceQueries`) が同じ値を出す。
///
/// ⚠️ 表示の約束 1: 画面に出すときは**必ず回数を添える**こと。回数を隠して
/// 「よく一緒に来る」とだけ書くと、次のライブで外れたときに嘘になる。分母
/// (`performances` / `total`) まで出せば、12/15 回 (ほぼ必ず一緒) と 12/300 回
/// (たまたま) を読み手が自分で区別できる。型名を Insights ではなく Evidence に
/// してあるのも、これが「予測」ではなく「証拠」だと呼ぶ側に思い出させるため。
///
/// ⚠️ 表示の約束 2: **`coOccurring` と `singers` は数える単位が違う**。
/// 前者は公演数、後者はセトリ行数 (曲詳細の「総披露 N 回」と同じ)。同じ「披露」と
/// いう語で両方を書くと、共起行の「39」とその曲を開いた先の「64」が食い違って
/// 見える (同梱 master で 48 曲がこのズレを持つ)。単位を明示して書き分けること。
///
/// (`SongPerformanceInsights` の名は UniFFI 生成レコードが既に使っている。生成 Swift は
///  アプリと同一モジュールにコンパイルされるので、同名にすると再宣言エラーになる。)
struct SongPerformanceEvidence: Sendable, Equatable {
    /// 同じ公演で歌われた曲 (一緒に来た**公演数**の多い順)。
    var coOccurring: [CoOccurringSong]
    /// この曲を歌ったアイドル (歌った**セトリ行数**の多い順)。
    var singers: [SongSingerTally]

    /// 披露実績が 1 度も無い曲ではどちらも空になる。節ごと出さない合図に使う。
    var isEmpty: Bool { coOccurring.isEmpty && singers.isEmpty }

    /// 披露実績がまだ無い曲の答え。読み取りが失敗したときの安全側の既定値でもある。
    /// (供給源の有無で空になることはない。未ロードなら SQL 経路が同じ値を返す。)
    static let empty = SongPerformanceEvidence(coOccurring: [], singers: [])
}

/// 同じ公演で歌われた曲 1 件。
///
/// ⚠️ 単位は**公演**。歌唱者タリーや「総披露 N 回」の**セトリ行数**とは別物なので、
/// 同じ画面に並べるときは単位を書き分けること。
struct CoOccurringSong: Sendable, Equatable, Identifiable {
    var song: Song
    /// 元の曲と同じ公演で歌われた公演数 (根拠。UI に必ず出す)。
    /// 1 公演で 2 回演奏されても 1 と数える (アンコール再演を二重計上しないため)。
    var together: Int
    /// この曲自身の総披露公演数 (分母)。`together / performances` が「一緒に来る率」。
    var performances: Int

    var id: String { song.id }
}

/// この曲を歌ったアイドル 1 件。
///
/// ⚠️ 単位は**セトリ行数** (アンコール再演も別の 1 回)。共起の公演数とは別物。
struct SongSingerTally: Sendable, Equatable, Identifiable {
    var idol: Idol
    /// このアイドルがこの曲を歌った回数 (根拠。UI に必ず出す)。
    var times: Int
    /// この曲の総披露回数 (分母)。歌唱者が誰であれ同じ値なので節の見出しにも出せる。
    /// 曲詳細のサマリタイル「総披露 N 回」と同じ数え方。
    var total: Int

    var id: String { idol.id }
}
