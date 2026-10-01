package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.ui.designsystem.ImasRankBadge
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.VocabularyTerm

// タグ画面群 (TagListScreen / TagDetailScreen / TagCreateSheet / TagEditSheet / TagFilterSheet /
// SongTagPickerSheet) 共通のカテゴリ定義・色・順位バッジ。iOS Views/Tags/*.swift の移植。

/** タグの作成先プール。曲タグ (tags) / アイドルタグ (idol_tag_master) / ユニットタグ (unit_tag_master) は
 * それぞれ別マスタなので、UI は共通のままこのフラグで作成 API・カテゴリ候補だけ切り替える。iOS TagDomain の移植。 */
enum class TagDomain { SONG, IDOL, UNIT }

/** タグのカテゴリの候補 (先頭は「なし」= 空文字)。語と並びはコアの vocabulary。 */
private fun categoryOptions(terms: List<VocabularyTerm>): List<Pair<String, String>> =
    listOf("" to Vocab.table.tagCategoryNoneLabel) + terms.map { it.value to it.label }

/** 曲タグのカテゴリ候補。 */
val TAG_CATEGORIES: List<Pair<String, String>> get() = categoryOptions(Vocab.table.songTagCategories)

/** アイドルタグのカテゴリ候補。曲タグとは語彙が別。 */
val TAG_CATEGORIES_IDOL: List<Pair<String, String>> get() = categoryOptions(Vocab.table.idolTagCategories)

/** ユニットタグのカテゴリ候補。 */
val TAG_CATEGORIES_UNIT: List<Pair<String, String>> get() = categoryOptions(Vocab.table.unitTagCategories)

fun tagCategoryOptions(domain: TagDomain): List<Pair<String, String>> = when (domain) {
    TagDomain.IDOL -> TAG_CATEGORIES_IDOL
    TagDomain.UNIT -> TAG_CATEGORIES_UNIT
    TagDomain.SONG -> TAG_CATEGORIES
}

fun tagCategoryLabel(category: String?): String =
    TAG_CATEGORIES.firstOrNull { it.first == category }?.second ?: (category ?: "")

@Composable
fun tagCategoryColor(category: String?): Color = when (category) {
    "mood" -> Color(0xFFAF52DE)
    "scene" -> Color(0xFF0A84FF)
    "special" -> Color(0xFFFF9F0A)
    "free" -> Color(0xFF34C759)
    else -> DS.ink2
}

fun idolTagCategoryLabel(category: String?): String =
    TAG_CATEGORIES_IDOL.firstOrNull { it.first == category }?.second ?: (category ?: "")

@Composable
fun idolTagCategoryColor(category: String?): Color = when (category) {
    "personality" -> Color(0xFFFF375F)
    "charm" -> Color(0xFFBF5AF2)
    "talent" -> Color(0xFF30D158)
    "free" -> Color(0xFF34C759)
    else -> DS.ink2
}

fun unitTagCategoryLabel(category: String?): String =
    TAG_CATEGORIES_UNIT.firstOrNull { it.first == category }?.second ?: (category ?: "")

@Composable
fun unitTagCategoryColor(category: String?): Color = when (category) {
    "concept" -> Color(0xFF5E5CE6)
    "mood" -> Color(0xFFAF52DE)
    "charm" -> Color(0xFFBF5AF2)
    "free" -> Color(0xFF34C759)
    else -> DS.ink2
}

/**
 * 人気ランキングの順位の札 (iOS `TagRankBadge` → DS `ImasRankBadge`)。
 * 色で順位を飾らない (メダル色の塗り分けはしない。1〜3 位は墨の太字、それ以降は灰)。
 */
@Composable
fun TagRankBadge(rank: Int) {
    ImasRankBadge(rank)
}

/** カテゴリ選択チップ。TagCreateSheet/TagEditSheet 共通 (色チップ・タグチップと同じ見た目に統一)。 */
@Composable
fun CategoryChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        label,
        fontSize = 13.5.sp,
        fontWeight = FontWeight.SemiBold,
        color = if (selected) Color.White else DS.ink2,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) DS.pick else DS.fill)
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 7.dp)
    )
}

/** タグ色の丸スウォッチ (一覧・詳細のドット)。 */
@Composable
fun TagColorDot(hex: String?, size: androidx.compose.ui.unit.Dp = 8.dp) {
    if (hex.isNullOrEmpty()) return
    androidx.compose.foundation.layout.Box(
        modifier = Modifier.size(size).clip(CircleShape)
            .background(com.fugaif.imaslivedb.ui.theme.hexToColor(hex))
    )
}
