package com.fugaif.imaslivedb.data.model

import java.time.LocalDate
import uniffi.imas_core.DailyPickBrandCandidates
import uniffi.imas_core.DailyPickKind
import uniffi.imas_core.dailyPickDayKey
import uniffi.imas_core.dailyPickIdolIndices
import uniffi.imas_core.dailyPickSheetKind
import uniffi.imas_core.dailyPickSongIndices

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
 * 起動時の日替わりシート (`DailyPickSheet`) が使う「今日の 1 曲」「今日のアイドル」も
 * ここから引く。ウィジェットは Android には無いので、iOS のような
 * 「アプリとウィジェットが同じ曲を選ぶ」制約は無いが、選び方はコアに委ねたまま
 * (候補列の条件さえ揃えれば iOS と同じ日に同じ曲・同じアイドルが出る)。
 */
object DailyPick {

    /** 端末ローカルの `"yyyy-MM-dd"`。連続記録の保存キーと同じ表記。 */
    fun dayKey(date: LocalDate = LocalDate.now()): String =
        dailyPickDayKey(localYear = date.year, localMonth = date.monthValue, localDay = date.dayOfMonth)

    /** 端末ローカルの前日。連続記録が途切れたかの判定に使う。 */
    fun previousDayKey(date: LocalDate = LocalDate.now()): String = dayKey(date.minusDays(1))

    /**
     * その日の起動シートが曲とアイドルどちらを出すか (偶数日=曲 / 奇数日=アイドル)。
     *
     * 渡すのは日付キー文字列ではなく日の成分。キーの表記は端末の暦法で変わり得るが、
     * 「その月の何日目か」はどの暦でも同じ (コア側のコメント参照)。
     */
    fun sheetKind(date: LocalDate = LocalDate.now()): DailyPickKind =
        dailyPickSheetKind(localDay = date.dayOfMonth)

    /**
     * 複数ブランド分の「今日の 1 曲」を 1 回の FFI 呼び出しでまとめて解決する。
     * 返り値は [brands] と同順。呼び出し側が自国の曲 ID 配列を index で引く。
     */
    fun songIndices(dayKey: String, brands: List<Pair<String, Int>>): List<Int> =
        dailyPickSongIndices(dayKey, brands.toCandidates()).map { it.toInt() }

    /** 複数ブランド分の「今日のアイドル」([songIndices] と同じ規約)。 */
    fun idolIndices(dayKey: String, brands: List<Pair<String, Int>>): List<Int> =
        dailyPickIdolIndices(dayKey, brands.toCandidates()).map { it.toInt() }

    private fun List<Pair<String, Int>>.toCandidates(): List<DailyPickBrandCandidates> =
        map { (brandId, count) ->
            DailyPickBrandCandidates(brandId = brandId, count = count.coerceAtLeast(0).toUInt())
        }
}
