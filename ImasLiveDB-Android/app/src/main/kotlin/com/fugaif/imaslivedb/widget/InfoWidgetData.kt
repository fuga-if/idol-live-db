package com.fugaif.imaslivedb.widget

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.model.DailyPick
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.nextShowIndex

/** 次のライブ 1 件。 */
data class NextShowInfo(
    val eventId: String,
    val eventName: String,
    /** 初日 (YYYY-MM-DD)。 */
    val firstDate: String,
    val brandColorHex: String?
)

/** 今日の 1 曲。 */
data class TodaySongInfo(
    val songId: String,
    val title: String,
    val artistLabel: String?,
    val artworkUrl: String?,
    val brandColorHex: String?
)

/** チケット締切が近いイベント 1 件。 */
data class TicketDeadlineInfo(
    val eventId: String,
    val eventName: String,
    /** 締切日 (YYYY-MM-DD)。 */
    val deadline: String
)

/**
 * 情報ウィジェット 3 種のデータを共有コアのスナップショットから引く層。
 * iOS `ImasLiveDB/Services/InfoWidgetBridge.swift` に対応する。
 *
 * ## iOS との違い: スナップショット JSON を挟まない
 *
 * iOS のウィジェット拡張は別プロセス・別サンドボックスでアプリの GRDB を開けないため、
 * アプリ側が計算結果を App Group の JSON に書き出し、拡張はそれを読むだけだった。
 * Android のウィジェットはアプリと同じ UID・同じプロセスなのでスナップショットを直接読める。
 * 中間ファイルを挟むと「アプリが書き出すまでウィジェットが古いまま」という状態を
 * 自前で管理することになるので挟まない。
 *
 * ## 日付の基準が 2 種類ある (統合しないこと)
 *
 * - 公演日・チケット締切との比較は [JstDay] (JST 固定)。ライブの開催日は日本時間の
 *   日付なので、端末が海外にあると端末ローカル日では 1 日ずれる。
 * - 「今日の 1 曲」は [DailyPick] (端末ローカル日)。ユーザーの 1 日が単位で、
 *   かつアプリ内の起動シートと同じ日付キーでないと違う曲が出る。
 */
object InfoWidgetData {

    private const val TAG = "ImasWidget"

    /** 日替わりピックの母集団から外すブランド (ブランドの代表曲ではないため。起動シートと同条件)。 */
    private const val EXCLUDED_BRAND_ID = "other"

    /**
     * 今日以降で最も近いライブ 1 件。母集合 (ライブ・フェスで公演のあるイベント) も
     * 「今日以降でいちばん早い」の選び方もコア (eventsWithFirstDate の既定の種別 / nextShowIndex)。
     */
    suspend fun nextShow(context: Context): NextShowInfo? = withContext(Dispatchers.IO) {
        runCatching {
            val module = AppModule.from(context)
            val events = module.snapshotStoreProvider.query { store ->
                store.eventsWithFirstDate(null, false, false, null)
            }
            val index = nextShowIndex(events.map { it.firstDate.orEmpty() }, JstDay.today())
                ?: return@runCatching null
            val next = events[index.toInt()]
            NextShowInfo(
                eventId = next.event.id,
                eventName = next.event.name,
                firstDate = next.firstDate.orEmpty(),
                brandColorHex = next.event.brandId?.let { module.statsRepository.fetchBrands().firstOrNull { b -> b.id == it } }?.color
            )
        }.onFailure { Log.w(TAG, "次のライブの取得に失敗", it) }.getOrNull()
    }

    /**
     * 今日の 1 曲。
     *
     * **アプリ内の起動シート ([com.fugaif.imaslivedb.ui.games.DailyPickSheet]) と必ず同じ曲**に
     * なる必要がある。そのために揃えるものは 2 つだけ、どちらも共有コアが唯一の実装を持つ:
     * - 候補列 … `SnapshotStore.dailyPickSongIds`
     * - 何番目を引くか … [DailyPick.songIndices]
     *
     * ブランドごとの番号は互いに独立に解かれる (種は `"日付|ブランドID"`) ので、
     * 1 ブランドだけ渡してもシートの一括呼び出しと同じ答えになる。
     *
     * ウィジェットに出すのは 1 曲だけなので、候補を持つ最初のブランド (= ブランド順の先頭) の
     * ピックを代表として使う (iOS も同じ)。シートは全ブランド分を縦に並べるが、その先頭と一致する。
     */
    suspend fun todaySong(context: Context): TodaySongInfo? = withContext(Dispatchers.IO) {
        runCatching {
            val module = AppModule.from(context)
            val dayKey = DailyPick.dayKey()
            // fetchBrands() は sort_order 順。
            val brands = module.statsRepository.fetchBrands().filter { it.id != EXCLUDED_BRAND_ID }
            val snapshots = module.snapshotStoreProvider
            for (brand in brands) {
                // 候補列はアプリの「今日の1曲」と同じくコアが正本 (読み込めなければ runCatching で null)。
                val songIds = snapshots.query {
                    it.dailyPickSongIds(brand.id, includeCovers = false, excludeRemixes = true)
                }
                if (songIds.isEmpty()) continue
                val index = DailyPick.songIndices(dayKey, listOf(brand.id to songIds.size)).firstOrNull()
                val song = index?.let { songIds.getOrNull(it) }?.let { module.songRepository.fetchSong(it) }
                    ?: continue
                return@runCatching TodaySongInfo(
                    songId = song.id,
                    title = song.title,
                    artistLabel = song.singerLabel,
                    artworkUrl = song.artworkUrl,
                    brandColorHex = brand.color
                )
            }
            null
        }.onFailure { Log.w(TAG, "今日の1曲の取得に失敗", it) }.getOrNull()
    }

    /** 締切が今日以降のイベントを、締切が近い順に [limit] 件。 */
    suspend fun ticketDeadlines(context: Context, limit: Int = 3): List<TicketDeadlineInfo> =
        withContext(Dispatchers.IO) {
            runCatching {
                val today = JstDay.today()
                AppModule.from(context).eventRepository.fetchEvents()
                    .mapNotNull { event ->
                        val deadline = event.ticketDeadline?.takeIf { it >= today } ?: return@mapNotNull null
                        TicketDeadlineInfo(event.id, event.name, deadline)
                    }
                    .sortedBy { it.deadline }
                    .take(limit)
            }.onFailure { Log.w(TAG, "チケット締切の取得に失敗", it) }.getOrDefault(emptyList())
        }
}
