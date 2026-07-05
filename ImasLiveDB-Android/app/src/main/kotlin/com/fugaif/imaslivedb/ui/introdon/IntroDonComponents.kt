package com.fugaif.imaslivedb.ui.introdon

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.delay
import kotlin.random.Random

// =============================================================================
// イントロドン共通 UI 部品。iOS IntroComponents.swift / IntroDesign.swift の移植。
// アプリ本体の DS (DesignTokens) にそのまま乗せる (iOS 側も ID enum は DS へのエイリアスに統一済み)。
// =============================================================================

/** ゲーム系画面共通のアクセント色 (iOS ID.menuCardDark 相当)。 */
@Composable
fun introDonAccent(): Color = ImasTheme.derive(null, null, dark = true).accent

/** 主ボタン (スタート/次の問題 等)。 */
@Composable
fun IntroDonActionButton(
    title: String,
    isLoading: Boolean = false,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val accent = introDonAccent()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(if (enabled) accent else accent.copy(alpha = 0.4f))
            .clickable(enabled = enabled && !isLoading, onClick = onClick)
            .padding(vertical = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
        } else {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}

/** 進捗バー (Rush の残り時間 / 通常の出題進捗)。 */
@Composable
fun IntroDonProgressBar(progress: Float, color: Color, modifier: Modifier = Modifier) {
    val animated by animateFloatAsState(targetValue = progress.coerceIn(0f, 1f), animationSpec = tween(150, easing = LinearEasing), label = "introDonProgress")
    Box(modifier = modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(DS.fill)) {
        Box(Modifier.fillMaxWidth(animated).height(3.dp).clip(RoundedCornerShape(2.dp)).background(color))
    }
}

/** 簡易イコライザーアニメーション (再生中の視覚フィードバック)。 */
@Composable
fun IntroDonEqAnimation(isAnimating: Boolean, modifier: Modifier = Modifier, color: Color = DS.ink) {
    val columns = 12
    var heights by remember { mutableStateOf(List(columns) { 2 }) }
    LaunchedEffect(isAnimating) {
        if (!isAnimating) {
            heights = List(columns) { 1 }
            return@LaunchedEffect
        }
        while (true) {
            heights = List(columns) { Random.nextInt(1, 6) }
            delay(220)
        }
    }
    Row(modifier = modifier.height(40.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        heights.forEach { h ->
            Box(
                modifier = Modifier
                    .width(4.dp)
                    .height((h * 7).dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(color.copy(alpha = if (isAnimating) 0.85f else 0.15f))
            )
        }
    }
}

/** イントロ再生の経過秒をカウントアップ表示する。iOS PlaybackElapsedLabel の移植。 */
@Composable
fun IntroDonElapsedLabel(isRunning: Boolean, resetKey: Any, modifier: Modifier = Modifier) {
    var accumulatedMs by remember { mutableStateOf(0L) }
    var runStartedAt by remember { mutableStateOf<Long?>(null) }
    var tick by remember { mutableStateOf(0L) }

    LaunchedEffect(resetKey) {
        accumulatedMs = 0L
        runStartedAt = if (isRunning) System.currentTimeMillis() else null
    }
    LaunchedEffect(isRunning, resetKey) {
        if (isRunning) {
            if (runStartedAt == null) runStartedAt = System.currentTimeMillis()
            while (isRunning) {
                tick = System.currentTimeMillis()
                delay(100)
            }
        } else {
            runStartedAt?.let { accumulatedMs += System.currentTimeMillis() - it }
            runStartedAt = null
        }
    }

    val displayedMs = accumulatedMs + (runStartedAt?.let { (tick.takeIf { t -> t > 0 } ?: System.currentTimeMillis()) - it } ?: 0L)
    val seconds = (displayedMs.coerceAtLeast(0L)) / 1000.0

    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Filled.MusicNote, null, tint = DS.ink2, modifier = Modifier.size(12.dp))
        Text(String.format("再生 %.1f秒", seconds), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.ink2)
    }
}

/** 回答選択肢の1行ボタン (iOS IDChoiceButton 相当)。 */
@Composable
fun IntroDonChoiceRow(title: String, onClick: () -> Unit) {
    val accent = introDonAccent()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier.size(30.dp).clip(RoundedCornerShape(6.dp)).background(accent.copy(alpha = 0.10f)),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.MusicNote, null, tint = accent.copy(alpha = 0.7f), modifier = Modifier.size(13.dp)) }
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
    }
}

/** 答え合わせ時の選択肢一覧 (正解=緑・自分の誤答=赤・その他=中立)。iOS IDAnswerReveal 相当。 */
@Composable
fun IntroDonAnswerReveal(choices: List<String>, correctTitle: String, selectedTitle: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        choices.forEach { choice ->
            val isCorrect = choice == correctTitle
            val wasSelected = choice == selectedTitle
            val (tint, bg, icon) = when {
                isCorrect -> Triple(DS.success, DS.success.copy(alpha = 0.15f), Icons.Filled.CheckCircle)
                wasSelected -> Triple(DS.danger, DS.danger.copy(alpha = 0.12f), Icons.Filled.Cancel)
                else -> Triple(DS.ink2, DS.fill, Icons.Filled.Circle)
            }
            Row(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(bg).padding(horizontal = 14.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(icon, null, tint = tint, modifier = Modifier.size(17.dp))
                Text(choice, fontSize = 14.sp, fontWeight = if (isCorrect) FontWeight.SemiBold else FontWeight.Normal, color = tint, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** ○/✕ の一瞬フラッシュ (Rush/全曲チャレンジの即時フィードバック)。 */
@Composable
fun IntroDonFlashOverlay(correct: Boolean) {
    Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
        Icon(
            imageVector = if (correct) Icons.Filled.Circle else Icons.Filled.Cancel,
            contentDescription = null,
            tint = if (correct) DS.success else DS.danger,
            modifier = Modifier.size(96.dp)
        )
    }
}

/** セクション見出し (iOS IDSectionLabel 相当)。 */
@Composable
fun IntroDonSectionLabel(text: String, hint: String? = null) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = DS.ink3)
        if (hint != null) {
            Spacer(Modifier.width(8.dp))
            Text(hint, fontSize = 11.sp, color = DS.ink3.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
