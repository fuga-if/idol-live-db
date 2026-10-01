package com.fugaif.imaslivedb.ui.components

import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.image.CustomImageStore
import com.fugaif.imaslivedb.data.image.GalleryKind
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.ImasRainbow

// =============================================================================
// ImasLiveDB — 共通コンポーネント (iOS DesignSystem/ImasComponents.swift の 1:1 移植)
// SF Symbol は ImageVector へ、Nuke は Coil へ置換。色は ImasTheme(seed) から導出。
// =============================================================================

/** 活動サマリの統計タイル (アイコン + 値 + 単位 + ラベル)。 */
@Composable
fun ImasStatTile(
    icon: ImageVector,
    value: String,
    label: String,
    unit: String? = null,
    seed: String? = null,
    brand: String? = null,
    tappable: Boolean = false,
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val t = imasThemeForBrand(seed, brand)
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier.size(30.dp).clip(RoundedCornerShape(9.dp)).background(t.chipBg),
                contentAlignment = Alignment.Center
            ) { Icon(icon, null, tint = t.chipText, modifier = Modifier.size(18.dp)) }
            Box(Modifier.weight(1f))
            if (tappable) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3, modifier = Modifier.size(12.dp))
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(value, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            if (unit != null) Text(unit, fontSize = 13.sp, color = DS.ink3, modifier = Modifier.padding(bottom = 3.dp))
        }
        Text(label, fontSize = 12.5.sp, fontWeight = FontWeight.Medium, color = DS.ink2)
    }
}

/** 横棒の統計バー (ラベル + バー + 値)。 */
@Composable
fun ImasStatBar(label: String, value: String, percent: Double, seed: String? = null, brand: String? = null) {
    val t = imasThemeForBrand(seed, brand)
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp, horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(modifier = Modifier.width(92.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(t.dot))
            Text(label, fontSize = 13.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(modifier = Modifier.weight(1f).height(8.dp).clip(RoundedCornerShape(4.dp)).background(DS.fill)) {
            Box(Modifier.fillMaxWidth((percent / 100.0).coerceIn(0.0, 1.0).toFloat()).fillMaxHeight()
                .clip(RoundedCornerShape(4.dp)).background(t.accent))
        }
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2, modifier = Modifier.width(44.dp), textAlign = TextAlign.End)
    }
}

/** セグメントバー (内部タブ切替)。 */
@Composable
fun ImasSegmented(
    labels: List<String>,
    selection: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.clip(RoundedCornerShape(10.dp)).background(DS.fill).padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        labels.forEachIndexed { idx, label ->
            val on = idx == selection
            Box(
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp))
                    .background(if (on) DS.surface else Color.Transparent)
                    .clickable { onSelect(idx) }
                    .padding(vertical = 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(label, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = if (on) DS.ink else DS.ink2)
            }
        }
    }
}

/** 空状態 (任意で投稿アクション)。 */
@Composable
fun ImasEmptyState(
    icon: ImageVector,
    title: String,
    message: String? = null,
    seed: String? = null,
    brand: String? = null,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null
) {
    val t = imasThemeForBrand(seed, brand)
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 30.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(t.chipBg),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, tint = t.chipText, modifier = Modifier.size(28.dp)) }
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, modifier = Modifier.padding(top = 14.dp))
        if (message != null) {
            Text(message, fontSize = 13.5.sp, color = DS.ink2, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
        }
        if (actionTitle != null && onAction != null) {
            androidx.compose.material3.Button(onClick = onAction, modifier = Modifier.padding(top = 14.dp)) {
                Text(actionTitle)
            }
        }
    }
}

/**
 * アバター + 名前のグリッド表示。原曲アイドル・歌唱アイドル一覧 (SongDetailScreen) と
 * タグが似ているアイドル (IdolDetailScreen) で共用する。
 * [badge] は idolId -> 共有タグ数 のマップ。渡すと名前の下に「タグN個一致」を表示する。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun IdolGridSection(
    title: String,
    idols: List<Idol>,
    onIdolClick: (String) -> Unit,
    badge: Map<String, Int>? = null
) {
    Column {
        ImasSectionHeader(title, count = "${idols.size}")
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            idols.forEach { idol ->
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.width(64.dp).clickable { onIdolClick(idol.id) }
                ) {
                    ImasAvatar(label = idol.shortName, seed = idol.color, brand = idol.brandId, size = 52.dp,
                        entityId = idol.id)
                    Text(idol.name, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = DS.ink2,
                        textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 6.dp))
                    val b = badge?.get(idol.id)
                    if (b != null) {
                        Text("タグ${b}個一致", fontSize = 10.sp, color = DS.ink3,
                            textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
