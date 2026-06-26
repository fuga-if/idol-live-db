package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

// =============================================================================
// ImasLiveDB — 共通コンポーネント (iOS DesignSystem/ImasComponents.swift の 1:1 移植)
// SF Symbol は ImageVector へ、Nuke は Coil へ置換。色は ImasTheme(seed) から導出。
// =============================================================================

/** アイドル等の円形アバター。画像があれば表示、無ければ tint 面 + モノグラム。 */
@Composable
fun ImasAvatar(
    label: String,
    seed: String? = null,
    brand: String? = null,
    size: Dp = 40.dp,
    isPick: Boolean = false,
    imageUrl: String? = null
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    val ringInset = if (isPick) 5.5.dp else 0.dp
    Box(
        modifier = Modifier.size(size + ringInset * 2),
        contentAlignment = Alignment.Center
    ) {
        if (isPick) {
            Box(Modifier.size(size + 11.dp).clip(CircleShape).background(t.gradTo))
            Box(Modifier.size(size + 7.dp).clip(CircleShape).background(t.accent))
            Box(Modifier.size(size + 4.dp).clip(CircleShape).background(DS.surface))
        }
        Box(
            modifier = Modifier.size(size).clip(CircleShape)
                .border(1.5.dp, t.ring, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (imageUrl != null) {
                SubcomposeAsyncImage(
                    model = imageUrl, contentDescription = label,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(size).clip(CircleShape),
                    loading = { Monogram(label, t, size) },
                    error = { Monogram(label, t, size) }
                )
            } else {
                Monogram(label, t, size)
            }
        }
    }
}

@Composable
private fun Monogram(label: String, t: ImasTheme, size: Dp) {
    Box(Modifier.size(size).background(t.tint), contentAlignment = Alignment.Center) {
        Text(
            label.take(2),
            color = t.accent,
            fontWeight = FontWeight.SemiBold,
            fontSize = (size.value * 0.40).sp,
            maxLines = 1
        )
    }
}

/** 楽曲ジャケット。画像があれば表示、無ければ accent 面 + 中央に曲名。 */
@Composable
fun ImasArtwork(
    title: String,
    seed: String? = null,
    brand: String? = null,
    size: Dp = 56.dp,
    imageUrl: String? = null
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    val radius = maxOf(8.dp, size * 0.16f)
    Box(
        modifier = Modifier.size(size).clip(RoundedCornerShape(radius)),
        contentAlignment = Alignment.Center
    ) {
        if (imageUrl != null) {
            SubcomposeAsyncImage(
                model = imageUrl, contentDescription = title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size),
                loading = { ArtworkFallback(title, t, size) },
                error = { ArtworkFallback(title, t, size) }
            )
        } else {
            ArtworkFallback(title, t, size)
        }
    }
}

@Composable
private fun ArtworkFallback(title: String, t: ImasTheme, size: Dp) {
    Box(Modifier.size(size).background(t.accent).padding(size * 0.12f), contentAlignment = Alignment.Center) {
        Text(
            title, color = t.onAccent, fontWeight = FontWeight.Bold,
            fontSize = maxOf(9f, size.value * 0.13f).sp,
            textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis
        )
    }
}

/** 一覧の控えめなエンティティ色マーカー (行頭の細い縦バー)。 */
@Composable
fun ImasLeadBar(seed: String? = null, brand: String? = null, height: Dp = 40.dp) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    Box(
        modifier = Modifier.size(width = 3.dp, height = height)
            .clip(RoundedCornerShape(2.dp)).background(t.bar)
    )
}

/** セクション見出し (タイトル + 件数 + すべて見る)。tight で小さめサブ見出し。 */
@Composable
fun ImasSectionHeader(
    title: String,
    count: String? = null,
    tight: Boolean = false,
    onSeeAll: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (tight) {
            Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        } else {
            Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            if (count != null) {
                Text(count, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3,
                    modifier = Modifier.padding(start = 8.dp))
            }
        }
        Box(Modifier.weight(1f))
        if (onSeeAll != null) {
            Row(Modifier.clickable(onClick = onSeeAll), verticalAlignment = Alignment.CenterVertically) {
                Text("すべて見る", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = DS.ink2)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink2, modifier = Modifier.size(16.dp))
            }
        }
    }
}

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
    val t = ImasTheme.derive(seed, brand, dark = true)
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

/** メトリクスバッジ (値 + 単位、accent 色)。 */
@Composable
fun ImasMetricBadge(value: String, unit: String = "", emphasized: Boolean = true, seed: String? = null) {
    val t = ImasTheme.derive(seed, null, dark = true)
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = if (emphasized) t.accent else DS.ink2)
        if (unit.isNotEmpty()) Text(unit, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
            color = if (emphasized) t.accent else DS.ink2, modifier = Modifier.padding(bottom = 1.dp))
    }
}

/** 横棒の統計バー (ラベル + バー + 値)。 */
@Composable
fun ImasStatBar(label: String, value: String, percent: Double, seed: String? = null, brand: String? = null) {
    val t = ImasTheme.derive(seed, brand, dark = true)
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

/** ランキング行 (順位 + lead(ジャケ/アバター) + タイトル + サブ + メトリクス)。 */
@Composable
fun ImasRankingRow(
    rank: Int, title: String, metric: String, unit: String = "回",
    sub: String? = null, seed: String? = null, brand: String? = null,
    onClick: (() -> Unit)? = null, lead: @Composable () -> Unit
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    Row(
        modifier = Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .background(DS.surface).padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("$rank", fontSize = 17.sp, fontWeight = FontWeight.Bold,
            color = if (rank <= 3) t.accent else DS.ink3, modifier = Modifier.width(26.dp))
        lead()
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        ImasMetricBadge(value = metric, unit = unit, seed = seed)
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

/** よみ / CV / 会場 等の key-value 行。 */
@Composable
fun ImasLabeledRow(
    key: String,
    value: String,
    showSwatch: Boolean = false,
    mono: Boolean = false,
    tappable: Boolean = false,
    seed: String? = null,
    brand: String? = null,
    onClick: (() -> Unit)? = null
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
    Row(
        modifier = Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .background(DS.surface)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(key, fontSize = 15.sp, color = DS.ink2)
        Box(Modifier.weight(1f))
        if (showSwatch) Box(Modifier.size(16.dp).clip(CircleShape).background(t.accent))
        Text(
            value,
            fontSize = 15.sp,
            color = if (tappable) t.accent else DS.ink,
            maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.End
        )
        if (tappable) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = t.accent, modifier = Modifier.size(13.dp))
    }
}

/** 空状態 (任意で投稿アクション)。 */
@Composable
fun ImasEmptyState(
    icon: ImageVector,
    title: String,
    message: String? = null,
    seed: String? = null,
    brand: String? = null
) {
    val t = ImasTheme.derive(seed, brand, dark = true)
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
    }
}
