package com.fugaif.imaslivedb.data.model

import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId
import uniffi.imas_core.jstIsTodayOrLater
import uniffi.imas_core.jstToday

/**
 * 「今日」の判定を JST に固定するための共通ルール。
 *
 * 判定本体は imas-core (Rust) の `jst_day.rs` にあり、iOS の `JSTDay` と同じ実装を共有する。
 * ここは「既定値 [Clock.systemUTC] の注入」と「Kotlin らしい呼び口の維持」だけを担う薄いラッパ。
 * なぜ JST 固定か・なぜ都度計算かの設計意図は imas-core/src/jst_day.rs に記載。
 *
 * `clock` を差せるようにしているのはテストで日付境界を再現するため (既定は実時刻)。
 *
 * 日替わりピックや連続クリア日数は「そのユーザーの 1 日」が単位なので端末ローカルのまま。
 * 意味が違うのでここには寄せない ([com.fugaif.imaslivedb.data.games.GameProgressStore] 参照)。
 */
object JstDay {
    val zone: ZoneId = ZoneId.of("Asia/Tokyo")

    /** JST での「今日」。 */
    fun date(clock: Clock = Clock.systemUTC()): LocalDate = LocalDate.parse(today(clock))

    /** JST での「今日」を `"yyyy-MM-dd"` で返す。公演日 (TEXT) との文字列比較用。 */
    fun today(clock: Clock = Clock.systemUTC()): String =
        jstToday(clock.instant().epochSecond)

    /**
     * 公演日が「今日以降」か。当日は未来として扱う (開催日当日はまだ終わっていない)。
     *
     * @param date `"yyyy-MM-dd"` の公演日。空文字は未来ではない。
     */
    fun isTodayOrLater(date: String, clock: Clock = Clock.systemUTC()): Boolean =
        jstIsTodayOrLater(date, clock.instant().epochSecond)
}
