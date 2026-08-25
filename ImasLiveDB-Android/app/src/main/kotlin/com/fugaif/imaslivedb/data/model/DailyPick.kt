package com.fugaif.imaslivedb.data.model

import java.time.LocalDate
import uniffi.imas_core.dailyPickDayKey

/**
 * 「日替わり」ものの共通ルール。日付キーは**端末ローカル日**。
 *
 * 表記そのものは imas-core (Rust) の `domain/daily_pick.rs` が持ち、iOS の `DailyPick` と
 * 同じ実装を共有する。ここは「既定値 [LocalDate.now] の注入」と「前日の算出」だけを担う
 * 薄いラッパ (iOS `Domain/UseCases/DailyPick.swift` と同じ役割)。
 *
 * 前日を引くのがコアでなくラッパの責務なのは、コアの chrono がグレゴリオ暦固定で、
 * 夏時間・暦法差を吸収できるのは OS の暦だけだから (iOS `previousDayKey` と同じ契約)。
 * `LocalDate.minusDays(1)` を通してから日付成分をコアへ渡す。
 *
 * 連続クリア日数や日替わりピックは「そのユーザーの 1 日」が単位なので端末ローカル。
 * 公演日との比較に使う JST 固定の [JstDay] とは意味が違うので統合しない。
 *
 * `date` を差せるのはテストで日付境界を再現するため (既定は実時刻)。
 *
 * 「今日の 1 曲」(`dailyPickSongIndex` / `dailyPickSongIndices`) もコアにあるが、
 * Android には該当画面 (iOS の `DailySongVoteSheet` / ウィジェット) がまだ無いので
 * ラッパも置かない。実装する時にここへ足す。
 */
object DailyPick {

    /** 端末ローカルの `"yyyy-MM-dd"`。連続記録の保存キーと同じ表記。 */
    fun dayKey(date: LocalDate = LocalDate.now()): String =
        dailyPickDayKey(localYear = date.year, localMonth = date.monthValue, localDay = date.dayOfMonth)

    /** 端末ローカルの前日。連続記録が途切れたかの判定に使う。 */
    fun previousDayKey(date: LocalDate = LocalDate.now()): String = dayKey(date.minusDays(1))
}
