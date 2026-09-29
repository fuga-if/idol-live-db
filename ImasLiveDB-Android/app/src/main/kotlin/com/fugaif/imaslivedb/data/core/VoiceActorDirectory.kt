package com.fugaif.imaslivedb.data.core

import uniffi.imas_core.SnapshotStore

/**
 * アイドル → 現任の声優名 (iOS `VoiceActorDirectory` と同じ)。
 *
 * 声優は `idol_voice_actors` の**期間つきの履歴**が正で、現任の選び方はコア (`idolCastNames`)。
 * Room の `idols.voice_actors` 列は seed に無い派生列で、reseed のたびに NULL になるので使わない。
 * 一覧や行は `Idol` しか持たず、行ごとにコアを引くと N+1 になるので、スナップショットの
 * 世代ごとに 1 回まとめて読んで覚える。スナップショットがまだ無い間は空 (= 出さない) で、覚えない。
 *
 * ⚠️ 「現任」は `valid_to IS NULL` の人。後任が未定の間は誰も居ない (null)。
 */
object VoiceActorDirectory {

    /** 読み込み済みのスナップショットと、その世代。まだ無ければ null。 */
    fun interface Source {
        fun current(): Pair<Long, SnapshotStore>?
    }

    @Volatile private var source: Source? = null
    @Volatile private var cached: Pair<Long, Map<String, String>>? = null

    /** アプリの組み立て (AppModule) で 1 回つなぐ。 */
    fun install(source: Source) {
        this.source = source
        cached = null
    }

    /** 現任の声優名。居なければ・まだ読めなければ null。 */
    fun current(idolId: String): String? = table()[idolId]

    /** 全員ぶん (一覧の CV 名検索・表示用)。 */
    fun all(): Map<String, String> = table()

    private fun table(): Map<String, String> {
        val (generation, store) = source?.current() ?: return cached?.second.orEmpty()
        cached?.let { (gen, table) -> if (gen == generation) return table }
        val table = runCatching { store.idolCastNames() }.getOrNull() ?: return cached?.second.orEmpty()
        cached = generation to table
        return table
    }
}
