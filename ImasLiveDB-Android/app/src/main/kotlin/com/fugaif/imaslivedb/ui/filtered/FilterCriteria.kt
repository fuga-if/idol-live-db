package com.fugaif.imaslivedb.ui.filtered

/**
 * 絞り込み一覧 (iOS Views/Filtered/) のルート引数 `kind` の値。
 *
 * `NavRoutes.Filtered*.createRoute` が受け付ける文字列の唯一の定義。呼び出し側 (詳細画面) と
 * 受け側 (ViewModel) がリテラルを別々に書くと、片方の綴りを直したときにもう片方が静かに
 * 「未知の kind = 空リスト」に落ちるので、両者がここだけを参照する。
 *
 * 値そのものは iOS の `SongFilterCriterion` 等の case 名に対応する。
 */
object SongFilterKind {
    /** value = cd_series の完全一致文字列。 */
    const val CD_SERIES = "cd_series"

    /** value = series_group の完全一致文字列 (例: "LIVE THE@TER PERFORMANCE")。 */
    const val SERIES_GROUP = "series_group"

    /** value = "YYYY"。 */
    const val RELEASE_YEAR = "release_year"

    /** value = brand_id。 */
    const val BRAND = "brand"

    /** value = 作詞・作曲・編曲いずれかのクレジット名 (1 人ぶん)。 */
    const val CREATOR = "creator"

    /** value = songs.song_type の生値 (solo / unit / all …)。 */
    const val SONG_TYPE = "song_type"
}

object EventFilterKind {
    /** value = brand_id。 */
    const val BRAND = "brand"

    /** value = "YYYY"。 */
    const val YEAR = "year"
}

object ShowFilterKind {
    /**
     * value = 会場マスタの ID (`venue_...`)。ID を持たない古い公演のために、
     * 引く側 (EventRepository.fetchShowsAtVenue) は生の会場文字列との OR にしてある。
     */
    const val VENUE = "venue"

    /** value = "YYYY-MM-DD"。 */
    const val DATE = "date"
}

object IdolFilterKind {
    /** value = brand_id。 */
    const val BRAND = "brand"

    /** value = idols.constellation の生値 (例: "おひつじ座")。 */
    const val CONSTELLATION = "constellation"

    /** value = idols.birth_place の生値 (例: "東京都")。 */
    const val BIRTH_PLACE = "birth_place"

    /** value = idols.blood_type の生値 (例: "A")。 */
    const val BLOOD_TYPE = "blood_type"
}
