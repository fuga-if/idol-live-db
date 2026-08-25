package com.fugaif.imaslivedb.ui.events

import com.fugaif.imaslivedb.data.model.EventWithDateRange
import uniffi.imas_core.EventFilterCriteria
import uniffi.imas_core.EventFilterItem
import uniffi.imas_core.filterEventIndices
import uniffi.imas_core.groupEventIndicesByYear

/** イベント一覧の「年度グループ」。[groupEventsByYear] の出力単位 (iOS `YearGroup` と同じ形)。 */
data class YearGroup(
    val year: String,
    val events: List<EventWithDateRange>
)

/**
 * イベント一覧へブランド/kind/検索/参加状態/お気に入り/メモ/会場絞り込みを適用する。
 *
 * 本体は imas-core の domain/event_list_filtering.rs (合同ブランド判定・未知 kind の
 * live フォールバック・venue の on/off 判定もそちら参照)。ここはエンティティ全体を
 * FFI へ渡さないための薄いラッパ: [EventWithDateRange] を判定に要る 5 フィールドの射影
 * ([EventFilterItem]) へ落とし、返ってきた index 列で自前の配列を引き直すだけ。
 */
fun filterEvents(
    events: List<EventWithDateRange>,
    criteria: EventFilterCriteria
): List<EventWithDateRange> =
    filterEventIndices(events.map(::eventFilterItem), criteria).map { events[it.toInt()] }

/**
 * 時系列フィルタ (今後/開催済み) + 年度グルーピング。
 *
 * 本体は imas-core の domain/event_grouping.rs。今後/開催済みの境界判定・部分日付
 * ("YYYY" 等) の桁合わせ・「年度不明」を末尾に置く規則・グループ内の時系列整列も
 * そちらに記載。ここは firstDate の射影を 1 回の FFI に渡し、返った index 列で
 * 表示用の [YearGroup] を組み立てるだけ (件数によらず 1 呼び出し)。
 *
 * `todayKey` に既定値を持たせないのは呼び出し側に JST を強制するため
 * (公演日は日本の開催日なので、端末ローカル日で切ると海外で 1 日ずれる)。
 */
fun groupEventsByYear(
    events: List<EventWithDateRange>,
    upcoming: Boolean,
    todayKey: String
): List<YearGroup> =
    groupEventIndicesByYear(events.map { it.firstDate }, upcoming, todayKey)
        .map { group -> YearGroup(year = group.year, events = group.indices.map { events[it.toInt()] }) }

/**
 * FFI 射影: 絞り込み判定に要るフィールドだけを [EventFilterItem] へ落とす。
 * `jointBrandIds` は生のカンマ区切りのまま渡す (分割規則も Rust 側が一次実装)。
 *
 * `kind` は一覧の母集合 SQL (EventDao.fetchEventsWithFirstDate) が SELECT していないため
 * 実際には Event の既定値 "live" が入る。一覧に kind 絞り込みの UI が無く
 * `excludedKinds` を常に空で渡すので判定に影響しないが、kind チップを足すときは
 * 母集合の SELECT に kind を加えるところから直すこと。
 */
private fun eventFilterItem(ew: EventWithDateRange): EventFilterItem = EventFilterItem(
    id = ew.event.id,
    brandId = ew.event.brandId,
    jointBrandIds = ew.event.jointBrandIds,
    name = ew.event.name,
    kind = ew.event.kind
)
