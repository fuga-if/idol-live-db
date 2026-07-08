package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS

// タグ画面群 (TagListScreen / TagDetailScreen / TagCreateSheet / TagEditSheet / TagFilterSheet /
// SongTagPickerSheet) 共通のカテゴリ定義・色・順位バッジ。iOS Views/Tags/*.swift の移植。

val TAG_CATEGORIES: List<Pair<String, String>> = listOf(
    "" to "なし", "mood" to "ムード", "scene" to "シーン", "special" to "特別", "free" to "フリー"
)

fun tagCategoryLabel(category: String?): String =
    TAG_CATEGORIES.firstOrNull { it.first == category }?.second ?: (category ?: "")

fun tagCategoryColor(category: String?): Color = when (category) {
    "mood" -> Color(0xFFAF52DE)
    "scene" -> Color(0xFF0A84FF)
    "special" -> Color(0xFFFF9F0A)
    "free" -> Color(0xFF34C759)
    else -> DS.ink2
}

/** 人気ランキングの順位バッジ。上位3つはメダル色 (金/銀/銅)。iOS TagRankBadge の移植。 */
@Composable
fun TagRankBadge(rank: Int) {
    val medal = when (rank) {
        1 -> Color(0xFFE8A800)
        2 -> Color(0xFFA8B0B8)
        3 -> Color(0xFFCC8033)
        else -> null
    }
    val textColor = medal ?: DS.ink2
    val bg = (medal ?: DS.ink3).copy(alpha = 0.16f)
    Text(
        "$rank",
        color = textColor,
        fontWeight = FontWeight.Bold,
        fontSize = 12.sp,
        modifier = Modifier
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(999.dp))
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 2.dp)
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
