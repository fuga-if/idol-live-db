package com.fugaif.imaslivedb.data.model

/**
 * 過去の披露実績から出した「この曲まわりの傾向」。**予想ではなく実績**。
 *
 * 共有コア (`imas-core/src/domain/performance_stats.rs`) がセトリ 13,777 件・
 * 出演者 60,383 件を走査して出す。事前計算も保存もしない (保存すると master 更新の
 * たびに作り直す手間と、古い値を配る事故が増える)。
 *
 * ⚠️ 表示の約束: 画面に出すときは**必ず回数を添える**こと。回数を隠して
 * 「よく一緒に来る」とだけ書くと、次のライブで外れたときに嘘になる。分母
 * ([CoOccurringSong.performances] / [SongSingerTally.total]) まで出せば、
 * 12/15 回 (ほぼ必ず一緒) と 12/300 回 (たまたま) を読み手が自分で区別できる。
 * 型名を Insights ではなく Evidence にしてあるのも、これが「予測」ではなく
 * 「証拠」だと呼ぶ側に思い出させるため (iOS の SongPerformanceEvidence と同名)。
 */
data class SongPerformanceEvidence(
    /** 同じ公演で歌われた曲 (一緒に来た回数の多い順)。 */
    val coOccurring: List<CoOccurringSong> = emptyList(),
    /** この曲を歌ったアイドル (歌った回数の多い順)。 */
    val singers: List<SongSingerTally> = emptyList()
) {
    /** 披露実績が 1 度も無い曲ではどちらも空になる。節ごと出さない合図に使う。 */
    val isEmpty: Boolean get() = coOccurring.isEmpty() && singers.isEmpty()

    companion object {
        /** スナップショット未ロード時の答え。エラーではなく「今は出せない」。 */
        val EMPTY = SongPerformanceEvidence()
    }
}

/** 同じ公演で歌われた曲 1 件。 */
data class CoOccurringSong(
    val song: Song,
    /**
     * 元の曲と同じ公演で歌われた公演数 (根拠。UI に必ず出す)。
     * 1 公演で 2 回演奏されても 1 と数える (アンコール再演を二重計上しないため)。
     */
    val together: Int,
    /** この曲自身の総披露公演数 (分母)。`together / performances` が「一緒に来る率」。 */
    val performances: Int
)

/** この曲を歌ったアイドル 1 件。 */
data class SongSingerTally(
    val idol: Idol,
    /** このアイドルがこの曲を歌った回数 (根拠。UI に必ず出す)。 */
    val times: Int,
    /** この曲の総披露回数 (分母)。歌唱者が誰であれ同じ値。 */
    val total: Int
)
