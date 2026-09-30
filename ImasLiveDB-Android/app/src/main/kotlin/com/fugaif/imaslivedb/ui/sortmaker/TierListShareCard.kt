package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.share.ShareCardActionPane
import com.fugaif.imaslivedb.ui.share.ShareCardRatio
import com.fugaif.imaslivedb.ui.share.ShareCardSheet
import com.fugaif.imaslivedb.ui.share.ShareCardSize
import com.fugaif.imaslivedb.ui.share.ShareInk
import com.fugaif.imaslivedb.ui.share.SoloShareScaffold
import com.fugaif.imaslivedb.ui.share.SocialShare
import com.fugaif.imaslivedb.ui.share.rememberShareCardPalette
import com.fugaif.imaslivedb.ui.theme.DS
import androidx.compose.ui.platform.LocalContext
import uniffi.imas_core.TierListShareTier
import uniffi.imas_core.TierListTier
import uniffi.imas_core.tierListShareText

// =============================================================================
// ティアー表の共有 (画像 / テキスト)。iOS TierListShareSheet / TierListShareCard の移植。
// =============================================================================

@Composable
fun TierListShareSheet(
    title: String,
    scopeLabel: String,
    tiers: List<TierListTier>,
    rowsByTier: List<List<SortMakerItem>>,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val rows = remember(tiers, rowsByTier) { tiers.zip(rowsByTier) }

    val shareText = remember(title, scopeLabel, rows) {
        tierListShareText(
            title = title,
            scopeLabel = scopeLabel,
            tiers = rows.map { (tier, items) -> TierListShareTier(label = tier.label, names = items.map { it.title }) }
        )
    }

    ShareCardSheet(title = "ティアー表をシェア", onDismiss = onDismiss) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            ShareCardActionPane(
                ratios = listOf(ShareCardRatio.PORTRAIT),
                fileNamePrefix = "tier_list"
            ) { size ->
                TierListShareCard(title = title, scopeLabel = scopeLabel, rows = rows, size = size)
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(DS.fill)
                    .clickable { SocialShare.shareText(context, shareText) }
                    .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                Icon(Icons.Filled.TextSnippet, null, tint = DS.ink, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text("テキストでシェア", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            }
        }
    }
}

/** 画像カード。段ごとに色の札 + 名前を詰めて並べる (画像は載せない)。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TierListShareCard(
    title: String,
    scopeLabel: String,
    rows: List<Pair<TierListTier, List<SortMakerItem>>>,
    size: ShareCardSize
) {
    val palette = rememberShareCardPalette(seed = rows.firstOrNull()?.first?.colorSeed)
    /** 1 段に載せる名前の上限。超えた分は「ほかN」。 */
    val perTier = 8
    SoloShareScaffold(palette = palette, size = size, badge = "TIER LIST") {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // 利用者が付けた表の名前を主役の見出しに (固定キャンバスなので固定 sp)。
            Text(
                title, fontSize = 34.sp, fontWeight = FontWeight.Black, color = ShareInk.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 12.dp)
            )
            Text(
                scopeLabel, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                color = ShareInk.ink.copy(alpha = 0.55f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(bottom = 10.dp)
            )
            rows.forEach { (tier, items) ->
                val tierAccent = rememberShareCardPalette(seed = tier.colorSeed).accent
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(
                        modifier = Modifier.size(40.dp).clip(RoundedCornerShape(6.dp)).background(tierAccent),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            tier.label, fontSize = if (tier.label.length <= 2) 20.sp else 11.sp,
                            fontWeight = FontWeight.Black, color = ShareInk.nearBlack,
                            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(2.dp)
                        )
                    }
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        items.take(perTier).forEach { item ->
                            Text(
                                item.title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                                color = ShareInk.ink.copy(alpha = 0.92f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                            )
                        }
                        if (items.size > perTier) {
                            Text(
                                "ほか${items.size - perTier}", fontSize = 12.sp,
                                color = ShareInk.ink.copy(alpha = 0.55f),
                                modifier = Modifier.padding(vertical = 4.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}
