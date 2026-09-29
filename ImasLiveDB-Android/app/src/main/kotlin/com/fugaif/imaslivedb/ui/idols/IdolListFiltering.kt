package com.fugaif.imaslivedb.ui.idols

import com.fugaif.imaslivedb.data.model.Idol
import uniffi.imas_core.IdolListEntry
import uniffi.imas_core.IdolListFilterCriteria
import uniffi.imas_core.IdolSearchTargetCounts
import uniffi.imas_core.IdolSortKind
import uniffi.imas_core.IdolSortOrderMeta
import uniffi.imas_core.filterIdolList
import uniffi.imas_core.idolSearchTargetCounts
import uniffi.imas_core.idolSortOrderTable
import uniffi.imas_core.sortIdolListRows

/**
 * アイドル一覧の並び順。
 *
 * 既定方向・ブランド区切りの扱い・ラベル文言の本体は imas-core の
 * domain/idol_list_filtering.rs (`IdolSortKind` / `IdolSortOrderMeta`)。
 * なぜ公式順以外でブランドの区切りを外すか (通し並び) もそちらに記載。
 * この enum が残るのは、定数名が SharedPreferences の保存値・フィルタシートの
 * `entries` 列挙という Kotlin 側の顔だから。各プロパティは起動後 1 回の FFI で
 * 引いたメタ表 (`idolSortOrderTable`) を参照するだけで、判定は持たない。
 */
enum class IdolSortOrder(internal val kind: IdolSortKind) {
    OFFICIAL(IdolSortKind.OFFICIAL),
    NAME_KANA(IdolSortKind.NAME_KANA),
    AGE(IdolSortKind.AGE),
    HEIGHT(IdolSortKind.HEIGHT),
    WEIGHT(IdolSortKind.WEIGHT),
    BIRTHDAY(IdolSortKind.BIRTHDAY),
    DEBUT(IdolSortKind.DEBUT);

    private val meta: IdolSortOrderMeta get() = META.getValue(this)

    /** 並び順そのものの表示名 (例:「五十音順」)。コアの `displayName`。 */
    val label: String get() = meta.displayName

    /** 未指定時の並び方向。数値系は「大きい順」の方が知りたい形 (背が高い順・年上順)。 */
    val defaultAscending: Boolean get() = meta.defaultAscending

    /** ブランド別セクションを維持するか。 */
    val keepsBrandGrouping: Boolean get() = meta.keepsBrandGrouping

    /** 昇順の言い回し (「年下から」等)。 */
    val ascendingLabel: String get() = meta.ascendingLabel

    /** 降順の言い回し (「年上から」等)。 */
    val descendingLabel: String get() = meta.descendingLabel

    private companion object {
        /**
         * Rust から一括で引いたメタ表。ケースごとに引くと 7 回の FFI ループになるため
         * 1 回取得してキャッシュする。全種別が必ず載っていることは Rust 側のテストが保証する。
         */
        val META: Map<IdolSortOrder, IdolSortOrderMeta> by lazy {
            val table = idolSortOrderTable().associateBy { it.kind }
            IdolSortOrder.entries.associateWith { table.getValue(it.kind) }
        }
    }
}

/**
 * アイドル一覧を指定の並び順で整列する。
 *
 * 本体は imas-core の domain/idol_list_filtering.rs (`sort_idol_list`)。値なしを並び方向に
 * かかわらず末尾へ送る理由・同値を公式順 (sortOrder) で安定させる理由もそちらに記載。
 * ここはエンティティ全体を FFI へ渡さないための薄いラッパ: `Idol` を判定に要る
 * フィールドの射影 (`IdolListEntry`) へ落とし、返ってきた index 列で自前の配列を
 * 引き直すだけ。`ascending` 未指定 (null) の既定方向解決も Rust 側が担う。
 */
fun sortIdols(idols: List<Idol>, order: IdolSortOrder, ascending: Boolean? = null): SortedIdols {
    val rows = sortIdolListRows(idols.map(::idolListEntry), order.kind, ascending)
    return SortedIdols(
        idols = rows.map { idols[it.index.toInt()] },
        metricById = rows.mapNotNull { row -> row.metricLabel?.let { idols[row.index.toInt()].id to it } }.toMap()
    )
}

/** 並べ替えた結果と、行に添える指標 (idol id → `17歳` / `158cm` / `4月3日` 等。文言はコア)。 */
data class SortedIdols(val idols: List<Idol>, val metricById: Map<String, String>)

/**
 * アイドル一覧へブランド/属性/マイマーク/テキスト検索の絞り込みを適用する。
 *
 * 本体は imas-core の domain/idol_list_filtering.rs (`filter_idol_list`)。別名 (フルネーム)
 * や愛称まで検索対象に含める理由・検索語を trim しない理由もそちらに記載。
 * ここは射影 (`IdolListEntry`) へ落とし、返ってきた index 列で自前の配列を引き直すだけ。
 */
fun filterIdols(idols: List<Idol>, criteria: IdolListFilterCriteria): List<Idol> =
    filterIdolList(idols.map(::idolListEntry), criteria).map { idols[it.toInt()] }

/**
 * 検索欄の語を「アイドル名として」「CV 名として」引いたときの件数。切替に添える。
 * 検索以外の軸は [criteria] のとおり効かせる (本体は imas-core の `idol_search_target_counts`)。
 */
fun idolSearchCounts(idols: List<Idol>, criteria: IdolListFilterCriteria, text: String): IdolSearchTargetCounts =
    idolSearchTargetCounts(idols.map(::idolListEntry), criteria, text)

/**
 * FFI 射影: 絞り込み・並べ替えの判定に要るフィールドだけを `IdolListEntry` へ落とす。
 * `aliases` は生のカンマ区切りのまま渡す (分割規則も Rust 側が一次実装)。
 */
private fun idolListEntry(idol: Idol): IdolListEntry = IdolListEntry(
    idolId = idol.id,
    brandId = idol.brandId,
    name = idol.name,
    nameKana = idol.nameKana,
    nickname = idol.nickname,
    aliases = idol.aliases,
    attribute = idol.attribute,
    sortOrder = idol.sortOrder.toLong(),
    age = idol.age?.toLong(),
    height = idol.height,
    weight = idol.weight,
    birthday = idol.birthday,
    debutDate = idol.debutDate
)
