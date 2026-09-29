package com.fugaif.imaslivedb.ui.theme

import uniffi.imas_core.BrandRecord

/**
 * ブランド ID → マスタ (`brands.color`) の色 hex。
 *
 * 以前は ID → 色の表を Kotlin に手書きしていた (iOS にも同じ表があった)。表は OS に
 * 持たず、スナップショットのブランドから引いて覚える。描画から同期で呼ぶので、
 * スナップショットがまだ無い間は null (= ニュートラル) を返し、覚えない。
 * 色からテーマへの導き方 (アイドル色 → ブランド色 → ニュートラル) はコアの `themeDerive`。
 * iOS `BrandColors` と同じ。
 */
object BrandColors {

    /** 読み込み済みスナップショットの (世代, ブランド)。まだ無ければ null。 */
    fun interface Source {
        fun current(): Pair<Long, List<BrandRecord>>?
    }

    @Volatile private var source: Source? = null
    @Volatile private var cached: Pair<Long, Map<String, String>>? = null

    /** アプリの組み立て (AppModule) で 1 回つなぐ。 */
    fun install(source: Source) {
        this.source = source
    }

    /** そのブランドの色 hex。未知の ID・色の無いブランド・null は null。 */
    fun hex(brandId: String?): String? {
        if (brandId == null) return null
        return table()?.get(brandId)
    }

    private fun table(): Map<String, String>? {
        val (generation, records) = source?.current() ?: return cached?.second
        cached?.let { (gen, table) -> if (gen == generation) return table }
        val table = records.mapNotNull { r -> r.color?.let { r.id to it } }.toMap()
        cached = generation to table
        return table
    }
}
