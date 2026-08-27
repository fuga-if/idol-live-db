package com.fugaif.imaslivedb.ui.share

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

// =============================================================================
// 機能 4: イントロドンの結果シェアカード
// iOS ImasLiveDB/Views/IntroDon/IntroShareCard.swift の移植。
//
// 数値はすべて iOS の 1080×1350pt キャンバス基準の半分 (このカードは 540 単位で組み、
// SHARE_CARD_SCALE=2 で 1080×1350px に焼くため)。比率は iOS と 1:1 で一致する。
//
// カード下部に本家アプリ「イントロクイズ」のダウンロード導線を載せ、広告も兼ねる。
// =============================================================================

@Immutable
data class IntroShareLine(val title: String, val correct: Boolean)

/** 曲別内訳に載せる最大行数。あふれた分は「ほか N曲」に畳む。 */
private const val MAX_BREAKDOWN_ROWS = 10

/** 結果シェアカード。見出し / 大スコア / グレード / メトリクス / 曲別内訳 + 本家宣伝。 */
@Composable
fun IntroResultShareCard(
    modeLabel: String,
    score: Int,
    total: Int,
    percentage: Int,
    timeText: String?,
    bestCombo: Int,
    lines: List<IntroShareLine>,
    size: ShareCardSize
) {
    val isPerfect = percentage >= 100
    val (gradeLabel, gradeColor) = introGrade(percentage)

    Box(
        Modifier
            .fillMaxSize()
            .background(ShareInk.nearBlack)
    ) {
        // 上方向からの淡いピンクの光。iOS の RadialGradient (endRadius 720pt) と同じ広がり。
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(DS.pick.copy(alpha = 0.20f), Color.Transparent),
                        center = Offset(size.widthUnits * SHARE_CARD_SCALE / 2f, 0f),
                        radius = 360f * SHARE_CARD_SCALE
                    )
                )
        )

        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            // ヘッダ
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text("イントロドン", fontSize = 26.sp, fontWeight = FontWeight.Black, color = DS.ink)
                Text(
                    if (isPerfect) "PERFECT" else "RESULT",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 4.sp,
                    color = if (isPerfect) DS.favorite else DS.ink2
                )
                Text(modeLabel, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.pick)
            }

            Spacer(Modifier.weight(1f))

            // 大スコア + グレード
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("$score", fontSize = 65.sp, fontWeight = FontWeight.Black, color = DS.ink)
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "/ $total",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                        color = DS.ink2,
                        modifier = Modifier.padding(bottom = 6.dp)
                    )
                }
                Box(
                    Modifier
                        .clip(CircleShape)
                        .background(gradeColor.copy(alpha = 0.14f))
                        .padding(horizontal = 14.dp, vertical = 6.dp)
                ) {
                    Text(gradeLabel, fontSize = 17.sp, fontWeight = FontWeight.Black, color = gradeColor)
                }
            }

            Spacer(Modifier.weight(1f))

            // メトリクス行
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 28.dp)
                    .clip(RoundedCornerShape(11.dp))
                    .background(DS.surface)
                    .padding(vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                StatItem("正解率", "$percentage%", Modifier.weight(1f))
                if (timeText != null) {
                    StatDivider()
                    StatItem("タイム", timeText, Modifier.weight(1f))
                }
                if (bestCombo >= 2) {
                    StatDivider()
                    StatItem("最大コンボ", "×$bestCombo", Modifier.weight(1f))
                }
            }

            // 曲別内訳
            if (lines.isNotEmpty()) {
                Breakdown(lines, Modifier.padding(start = 28.dp, end = 28.dp, top = 12.dp))
            }

            Spacer(Modifier.weight(1f))

            IntroShareFooter(Modifier.padding(top = 14.dp, bottom = 28.dp))
        }
    }
}

@Composable
private fun StatItem(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(value, fontSize = 26.sp, fontWeight = FontWeight.Black, color = DS.ink, maxLines = 1)
        Text(label, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2, maxLines = 1)
    }
}

@Composable
private fun StatDivider() {
    Box(Modifier.width(1.dp).height(28.dp).background(DS.ink3.copy(alpha = 0.25f)))
}

@Composable
private fun Breakdown(lines: List<IntroShareLine>, modifier: Modifier = Modifier) {
    val shown = lines.take(MAX_BREAKDOWN_ROWS)
    val extra = lines.size - shown.size
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(11.dp))
            .background(DS.surface)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        shown.forEach { line ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (line.correct) Icons.Filled.CheckCircle else Icons.Filled.Cancel,
                    contentDescription = null,
                    tint = if (line.correct) DS.success else DS.ink3,
                    modifier = Modifier.size(14.dp)
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    line.title,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DS.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (extra > 0) {
            Text(
                "ほか ${extra}曲",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = DS.ink2,
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp)
            )
        }
    }
}

/**
 * 本家アプリ (イントロクイズ) への導線フッター。
 * 文言は iOS のシェアカードと一字一句そろえてある (同じ宣伝を 2 プラットフォームで打つため)。
 */
@Composable
private fun IntroShareFooter(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text("もっと遊ぶなら 本家アプリ", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = DS.ink2)
        Text("App Storeで「イントロクイズ」", fontSize = 17.sp, fontWeight = FontWeight.Black, color = DS.ink)
    }
}

/** 正答率 → グレード表記と色。iOS IntroResultShareCard.grade と同じ刻み。 */
private fun introGrade(percentage: Int): Pair<String, Color> = when {
    percentage >= 100 -> "パーフェクト！" to DS.favorite
    percentage >= 80 -> "すごい！" to DS.success
    // iOS の accentBlue に相当する固定色は Android に無いので、ゲーム画面と同じアクセントを使う。
    percentage >= 60 -> "なかなか！" to ImasTheme.derive(seed = null, brand = null, dark = true).accent
    percentage >= 40 -> "もう少し！" to DS.warning
    else -> "練習あるのみ！" to DS.pick
}

/**
 * イントロドン結果のシェアシート。
 *
 * 従来はテキストだけの ACTION_SEND だったが、画像を主役にして本文を添える形にする
 * (X などは画像付きの方が伸びるうえ、本家アプリの導線をカードに焼き込める)。
 * このカードのレイアウトは 4:5 前提で組んであるので、比率トグルは出さない。
 */
@Composable
fun IntroDonShareSheet(
    modeLabel: String,
    score: Int,
    total: Int,
    percentage: Int,
    timeText: String?,
    bestCombo: Int,
    lines: List<IntroShareLine>,
    shareText: String,
    onDismiss: () -> Unit
) {
    ShareCardSheet(title = "結果をシェア", onDismiss = onDismiss) {
        ShareCardActionPane(
            ratios = listOf(ShareCardRatio.PORTRAIT),
            shareText = shareText,
            fileNamePrefix = "introdon"
        ) { size ->
            IntroResultShareCard(
                modeLabel = modeLabel,
                score = score,
                total = total,
                percentage = percentage,
                timeText = timeText,
                bestCombo = bestCombo,
                lines = lines,
                size = size
            )
        }
    }
}
