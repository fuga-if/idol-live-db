package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.runtime.Immutable

// =============================================================================
// セトリと予想の行 (docs/DESIGN_SYSTEM.md §5.6・§5.8)。iOS `ImasSetlistRows.swift` の移植。
//
// ImasSetlistRow  セトリの 1 曲。曲順・ジャケ・曲名・歌唱者・役割の札・事実 (初披露・回収)。
// ImasForecastRow 予想・機械予測の 1 曲。順位・ジャケ・曲名・根拠・確率 (または票)。
//                 推測なので確率は「%」付きで出し、事実の行 (セトリ) と同じ札を使わない。
//
// どちらもデータは素の値で受け取る (画面の ViewModel が組む)。見た目だけを持つ。
// =============================================================================

/**
 * 歌唱者 1 人ぶんの表示データ (iOS `ImasPerformer`)。
 *
 * @param color イメージカラーの hex。
 * @param isAbsent 欠席 (オリメンだがこの公演に出ない)。
 * @param iconLabel 判子に入れる短い名前 (アイドルの略称)。アイドルでない人 (アイドル情報の無い歌唱者) は null。
 * @param imageUrl 写真の URL。
 * @param entityId アイドルの id。渡すと端末に取り込んだ写真を引く (Android は写真を id で引くため。iOS は URL で渡す)。
 */
@Immutable
data class ImasPerformer(
    val id: String,
    val name: String,
    val color: String? = null,
    val isAbsent: Boolean = false,
    val iconLabel: String? = null,
    val imageUrl: String? = null,
    val entityId: String? = null
)

/** 札 1 枚ぶんのデータ (iOS `ImasBadgeSpec`。行の部品に並べて渡す)。[seed] は色 hex。 */
@Immutable
data class ImasBadgeSpec(
    val text: String,
    val kind: ImasBadgeKind,
    val seed: String? = null
) {
    val id: String get() = "$text-$kind"
}
