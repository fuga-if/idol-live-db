package com.fugaif.imaslivedb.data.model

import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId

/**
 * 「今日」の判定を JST に固定するための共通ルール。iOS の `JSTDay` と 1:1。
 *
 * ## なぜ JST 固定か
 *
 * DB に入っている公演日 (`shows.date`) は **日本のライブの開催日**で `"yyyy-MM-dd"` の文字列。
 * これを「今日」と文字列比較して「未来公演か」「次の公演はどれか」を出している。
 * 端末ローカルのタイムゾーンで「今日」を作ると、海外にいるユーザーだけ判定が 1 日ずれる
 * (例: ハワイ (UTC-10) では日本の 7/26 10:00 がまだ 7/25 なので、日本では終わった公演が
 * 「これから」に出る)。`StatsRepository` は元から JST 固定で、それが本来の方針。
 *
 * ## なぜ都度計算し、なぜ `clock` を渡せるか
 *
 * 定数に持つとアプリを開いたまま日付が変わったときに「今日」が古いままになる。都度計算する。
 * `clock` を差せるようにしているのはテストで日付境界を再現するため (既定は実時刻)。
 *
 * 日替わりピックや連続クリア日数は「そのユーザーの 1 日」が単位なので端末ローカルのまま。
 * 意味が違うのでここには寄せない ([GameProgressStore] 参照)。
 */
object JstDay {
    val zone: ZoneId = ZoneId.of("Asia/Tokyo")

    /** JST での「今日」。 */
    fun date(clock: Clock = Clock.systemUTC()): LocalDate = LocalDate.now(clock.withZone(zone))

    /** JST での「今日」を `"yyyy-MM-dd"` で返す。公演日 (TEXT) との文字列比較用。 */
    fun today(clock: Clock = Clock.systemUTC()): String = date(clock).toString()

    /**
     * 公演日が「今日以降」か。当日は未来として扱う (開催日当日はまだ終わっていない)。
     *
     * @param date `"yyyy-MM-dd"` の公演日。空文字は未来ではない。
     */
    fun isTodayOrLater(date: String, clock: Clock = Clock.systemUTC()): Boolean =
        date.isNotEmpty() && date >= today(clock)
}
