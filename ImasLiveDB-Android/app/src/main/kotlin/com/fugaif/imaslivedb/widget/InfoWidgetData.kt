package com.fugaif.imaslivedb.widget

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.DailyPick
import com.fugaif.imaslivedb.data.model.JstDay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
 * 情報ウィジェット 3 種のデータを Room から計算する層。
 * iOS `ImasLiveDB/Services/InfoWidgetBridge.swift` に対応する。
 *
 * ## iOS との違い: スナップショット JSON を挟まない
 *
 * iOS のウィジェット拡張は別プロセス・別サンドボックスでアプリの GRDB を開けないため、
 * アプリ側が計算結果を App Group の JSON に書き出し、拡張はそれを読むだけだった。
 * Android のウィジェットはアプリと同じ UID・同じプロセスなので Room を直接読める。
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

    /** 「次のライブ」に数えるイベント種別。iOS `kinds: [.live, .festival]` と同じ。 */
    private val NEXT_SHOW_KINDS = setOf("live", "festival")

    /** 日替わりピックの母集団から外すブランド (ブランドの代表曲ではないため。起動シートと同条件)。 */
    private const val EXCLUDED_BRAND_ID = "other"

    /**
     * 今日以降で最も近いライブ 1 件。
     * 公演が 1 本も無いイベント (first_date が null) は自然に外れる。
     */
    suspend fun nextShow(context: Context): NextShowInfo? = withContext(Dispatchers.IO) {
        runCatching {
            val database = AppDatabase.getInstance(context)
            val today = JstDay.today()
            // 一覧クエリの行は kind を持たない (ライブ一覧が kind で絞らないため)。
            // ここは live/festival だけを見たいので、種別はイベント本体から引き直す。
            val kindById = database.eventDao().fetchEvents().associate { it.id to it.kind }
            val next = database.eventDao().fetchEventsWithFirstDate()
                .asSequence()
                .filter { kindById[it.id] in NEXT_SHOW_KINDS }
                .filter { (it.firstDate ?: "") >= today && !it.firstDate.isNullOrEmpty() }
                .minByOrNull { it.firstDate.orEmpty() }
                ?: return@runCatching null

            val brandColor = database.brandDao().fetchBrands().firstOrNull { it.id == next.brandId }?.color
            NextShowInfo(
                eventId = next.id,
                eventName = next.name,
                firstDate = next.firstDate.orEmpty(),
                brandColorHex = brandColor
            )
        }.onFailure { Log.w(TAG, "次のライブの取得に失敗", it) }.getOrNull()
    }

    /**
     * 今日の 1 曲。
     *
     * **アプリ内の起動シート ([com.fugaif.imaslivedb.ui.games.DailyPickSheet]) と必ず同じ曲**に
     * なる必要がある。そのために揃えるものは 2 つだけ:
     * - 候補列 … `fetchDailyPickSongIds` (シートと同じクエリ = 同じ順序・同じ除外条件)
     * - 何番目を引くか … [DailyPick.songIndices] (共有コアが持つ唯一の実装)
     *
     * ブランドごとの番号は互いに独立に解かれる (種は `"日付|ブランドID"`) ので、
     * 1 ブランドだけ渡してもシートの一括呼び出しと同じ答えになる。
     *
     * ウィジェットに出すのは 1 曲だけなので、候補を持つ最初のブランド (= ブランド順の先頭) の
     * ピックを代表として使う (iOS も同じ)。シートは全ブランド分を縦に並べるが、その先頭と一致する。
     */
    suspend fun todaySong(context: Context): TodaySongInfo? = withContext(Dispatchers.IO) {
        runCatching {
            val database = AppDatabase.getInstance(context)
            val dayKey = DailyPick.dayKey()
            // fetchBrands() は sort_order 順。
            val brands = database.brandDao().fetchBrands().filter { it.id != EXCLUDED_BRAND_ID }
            for (brand in brands) {
                val songIds = database.songDao().fetchDailyPickSongIds(brand.id)
                if (songIds.isEmpty()) continue
                val index = DailyPick.songIndices(dayKey, listOf(brand.id to songIds.size)).firstOrNull()
                val song = index?.let { songIds.getOrNull(it) }?.let { database.songDao().fetchSong(it) }
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
                AppDatabase.getInstance(context).eventDao().fetchEvents()
                    .mapNotNull { event ->
                        val deadline = event.ticketDeadline?.takeIf { it >= today } ?: return@mapNotNull null
                        TicketDeadlineInfo(event.id, event.name, deadline)
                    }
                    .sortedBy { it.deadline }
                    .take(limit)
            }.onFailure { Log.w(TAG, "チケット締切の取得に失敗", it) }.getOrDefault(emptyList())
        }
}
