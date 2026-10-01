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
