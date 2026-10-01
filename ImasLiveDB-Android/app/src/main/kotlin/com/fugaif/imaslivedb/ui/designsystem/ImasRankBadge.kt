package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType

// =============================================================================
// 順位の札 (docs/DESIGN_SYSTEM.md §10.1)。iOS `Community/ImasRankBadge.swift` の移植。
//
// 数字だけの小さい順位の札。タグ・お題のランキングで、色のドットや名前と同じ行に差し込める
// (`ImasRankNumber` は行の先頭いっぱいに置く大きな数字で、こちらは文中に添える小さい版)。
// 色で順位を飾らない (メダル色の塗り分けはしない。1〜3 位は墨の太字、それ以降は灰)。
// =============================================================================

/** 小さい順位の札 (iOS `ImasRankBadge`)。読み上げは「N位」。 */
@Composable
fun ImasRankBadge(rank: Int, modifier: Modifier = Modifier) {
    Box(
        modifier
            .clearAndSetSemantics { contentDescription = "${rank}位" }
            .sizeIn(minWidth = 26.dp, minHeight = DS.Size.badge)
            .background(DS.fill, RoundedCornerShape(DS.rTag))
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            "$rank",
            style = ImasType.mono(11.sp, FontWeight.Bold).copy(fontFeatureSettings = "tnum"),
            color = if (rank <= 3) DS.ink else DS.ink2
        )
    }
}
