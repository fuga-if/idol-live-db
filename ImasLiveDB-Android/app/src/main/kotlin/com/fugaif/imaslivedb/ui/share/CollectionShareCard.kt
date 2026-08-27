package com.fugaif.imaslivedb.ui.share

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import java.util.Locale

// =============================================================================
// 機能 1: 楽曲回収率シェアカード
// 現地参加ライブで聴けた曲 (自動回収) の回収率をカード化する。
// iOS ImasLiveDB/Views/Share/CollectionShareCard.swift の移植。
// =============================================================================

/** カードに焼く回収率データ。 */
@Immutable
data class CollectionShareStats(
    val overallCollected: Int,
    val overallTotal: Int,
    /** 担当アイドル別の回収状況 (カードに乗せるのは先頭 4 人まで)。 */
    val idolLines: List<IdolLine> = emptyList()
) {
    @Immutable
    data class IdolLine(
        val id: String,
        val name: String,
        val color: String?,
        val collected: Int,
        val total: Int
    ) {
        val ratio: Double get() = if (total > 0) collected.toDouble() / total else 0.0
    }

    val overallRatio: Double get() = if (overallTotal > 0) overallCollected.toDouble() / overallTotal else 0.0
    val overallPercentText: String get() = String.format(Locale.US, "%.1f", overallRatio * 100)

    /** メンバーカラー seed: 先頭の担当カラー → なければニュートラル。 */
    val seed: String? get() = idolLines.firstOrNull()?.color

    companion object {
        /**
         * 担当アイドル別の内訳を読む。
         *
         * 全体の分子/分母はダッシュボードが既に持っているので呼び出し側から受け取り、
         * ここでは「担当のオリ曲がどれだけ回収済みか」だけを引く (集計の二重定義を作らない)。
         */
        suspend fun load(context: Context, overallCollected: Int, overallTotal: Int): CollectionShareStats {
            val module = AppModule.from(context)
            val collected = module.userMarkRepository.autoCollectedSongIds()
            val lines = module.userMarkRepository.pickedIdols().take(4).map { idol ->
                val songIds = module.songRepository.fetchIdolSongs(idol.id, role = "original").map { it.id }
                IdolLine(
                    id = idol.id,
                    name = idol.name,
                    color = idol.color,
                    collected = songIds.count { it in collected },
                    total = songIds.size
                )
            }
            return CollectionShareStats(overallCollected, overallTotal, lines)
        }
    }
}

/**
 * 回収率カード本体。
 * 曲が無いのでジャケ写なし。単色 near-black 地 + 大きな幾何透かしの編集レイアウト。
 * 巨大な回収率 % を明朝でヒーローに。メンバーカラーは担当ドット + バーの差し色のみ。
 */
@Composable
fun CollectionShareCard(stats: CollectionShareStats, size: ShareCardSize) {
    val palette = rememberShareCardPalette(stats.seed)

    SoloShareScaffold(palette = palette, size = size, badge = "楽曲回収率") {
        Spacer(Modifier.height(16.dp))

        Text(
            "ライブで聴けた曲",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.0.sp,
            color = ShareInk.ink2
        )
        Spacer(Modifier.height(4.dp))

        // ヒーロー: 巨大な回収率を明朝で。
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                stats.overallPercentText,
                fontSize = 132.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Serif,
                color = ShareInk.ink,
                maxLines = 1,
                softWrap = false
            )
            Spacer(Modifier.width(2.dp))
            Text(
                "%",
                fontSize = 44.sp,
                fontFamily = FontFamily.Serif,
                color = ShareInk.ink2,
                modifier = Modifier.padding(bottom = 18.dp)
            )
        }

        Spacer(Modifier.height(4.dp))
        Text(
            "${stats.overallCollected} / ${stats.overallTotal} 曲を回収",
            fontSize = 17.sp,
            fontWeight = FontWeight.Medium,
            color = ShareInk.ink2
        )

        Spacer(Modifier.height(20.dp))
        ShareProgressBar(ratio = stats.overallRatio, height = 10.dp, fill = palette.accent)

        if (stats.idolLines.isNotEmpty()) {
            Spacer(Modifier.height(32.dp))
            Box(Modifier.fillMaxWidth().height(0.75.dp).background(ShareInk.ink.copy(alpha = 0.14f)))
            Spacer(Modifier.height(26.dp))
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                stats.idolLines.forEach { line -> IdolRow(line, palette) }
            }
        }
    }
}

@Composable
private fun IdolRow(line: CollectionShareStats.IdolLine, palette: ShareCardPalette) {
    val fill = line.color?.let { hexToColor(it) } ?: palette.accent
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(fill))
            Spacer(Modifier.width(9.dp))
            Text(
                line.name,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = ShareInk.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "${line.collected}/${line.total}曲",
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = ShareInk.ink2
            )
        }
        ShareProgressBar(ratio = line.ratio, height = 5.dp, fill = fill)
    }
}

/** プログレスバー。塗りはメンバーカラー (差し色)、地は白の薄塗り。 */
@Composable
private fun ShareProgressBar(ratio: Double, height: Dp, fill: Color) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
            .background(ShareInk.ink.copy(alpha = 0.14f))
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            // 0% でも点が残るよう、最小幅をバーの高さにする (iOS と同じ)。
            val filled = maxOf(height, maxWidth * ratio.coerceIn(0.0, 1.0).toFloat())
            Box(Modifier.width(filled).fillMaxHeight().clip(CircleShape).background(fill))
        }
    }
}

/** 回収ダッシュボードから開くシェアシート。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionShareSheet(collected: Int, total: Int, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var stats by remember { mutableStateOf<CollectionShareStats?>(null) }

    LaunchedEffect(collected, total) {
        stats = CollectionShareStats.load(context, collected, total)
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ShareCardSheetHeader("回収率をシェア", onClose = onDismiss)
            val current = stats
            if (current == null) {
                Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else {
                ShareCardActionPane(fileNamePrefix = "collection") { size ->
                    CollectionShareCard(stats = current, size = size)
                }
            }
        }
    }
}
