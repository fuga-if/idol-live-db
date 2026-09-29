package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.community.SetlistPredictionService
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import uniffi.imas_core.SetlistForecastRecord

/**
 * セトリの機械予測の読み取り口。iOS `SetlistForecastReading` と 1:1。
 *
 * 点数・順位・理由・公演の印はすべてコア (`imas-core` の `setlist_forecast`) の判断なので、
 * ここは公演 id と件数を渡して 1 回で受け取るだけ。
 */
interface SetlistForecastReading {
    /**
     * 点数の高い順に最大 [limit] 曲。予測の対象でない公演 (リアルライブでない等) なら null。
     * 初回は下ごしらえと学習で数百 ms かかるので、実装はメインスレッドの外で計算すること。
     */
    suspend fun setlistForecast(showId: String, limit: Int): SetlistForecastRecord?
}

/** セトリ予想 (みんなの予想) への投票の口。iOS `SetlistPredictionVoting` と 1:1。 */
interface SetlistPredictionVoting {
    /** その曲に 1 票入れる。上限は [SetlistPredictionService.VoteLimitReached] で投げる。 */
    suspend fun vote(showId: String, songId: String)
}

/** [SetlistForecastReading] のコア実装。計算は [SnapshotStoreProvider.query] が Default に逃がす。 */
class CoreSetlistForecastRepository(private val snapshots: SnapshotStoreProvider) : SetlistForecastReading {
    override suspend fun setlistForecast(showId: String, limit: Int): SetlistForecastRecord? =
        snapshots.query { it.setlistForecast(showId, limit.coerceAtLeast(0).toUInt()) }
}

/** [SetlistPredictionVoting] を [SetlistPredictionService] に繋ぐ口。 */
class PredictionServiceVoting(private val service: SetlistPredictionService) : SetlistPredictionVoting {
    override suspend fun vote(showId: String, songId: String) = service.vote(showId, songId)
}
