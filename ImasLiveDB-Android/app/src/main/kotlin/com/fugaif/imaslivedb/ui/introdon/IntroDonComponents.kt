package com.fugaif.imaslivedb.ui.introdon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTile
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasPress
import kotlinx.coroutines.delay

// =============================================================================
// イントロドン共通 UI 部品。iOS IntroComponents.swift / IntroDesign.swift の移植。
//
// 2026-10 の DS 移行で、iOS 側の IDActionButton・IDEQAnimation・IDProgressBar・IDModeCard・
// IDSectionLabel・IDCorner (IntroComponents.swift / IntroDesign.swift) はすでにどの画面からも
// 呼ばれなくなっている (死んだ移行前コード)。Android 側もそれに揃え、ここに残すのは
// ui/designsystem の部品で表せない「イントロドン固有の中身」だけにする:
//   - IntroDonElapsedLabel  イントロ再生の経過秒 (iOS PlaybackElapsedLabel の移植)。
//   - IntroDonChoiceRow     回答中の選択肢 1 行 (ImasCard + ImasIconTile で組む)。
//   - IntroDonAnswerReveal  答え合わせの選択肢一覧 (正解=緑・自分の誤答=赤・その他=中立)。
// ボタン・進捗バー・イコライザー・見出し・フラッシュ演出は ui/designsystem の本物の部品
// (ImasButton・ImasStageEqualizer・ImasStageRushFlash・ImasSectionHeader 等) を呼び出し側が直接使う。
// =============================================================================

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

    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasIconTile(Icons.Filled.MusicNote, size = ImasIconTileSize.S28, tone = ImasIconTileTone.NEUTRAL)
        ImasText(String.format("再生 %.1f秒", seconds), ImasTextRole.META)
    }
}

/** 回答選択肢の1行ボタン (iOS IDChoiceButton 相当)。 */
@Composable
fun IntroDonChoiceRow(title: String, onClick: () -> Unit) {
    ImasCard(modifier = Modifier.imasPress(onClick = onClick), padding = DS.Space.rowH) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap)
        ) {
            ImasIconTile(Icons.Filled.MusicNote, size = ImasIconTileSize.S32, tone = ImasIconTileTone.NEUTRAL)
            ImasText(
                title,
                ImasTextRole.ROW_LABEL,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/**
 * 答え合わせ時の選択肢一覧 (正解=緑・自分の誤答=赤・その他=中立)。iOS IDAnswerReveal 相当。
 *
 * 行の地そのものを正誤の色に薄く染める (アイコン・文字だけでなく一目で分かる一覧なので、
 * `ImasCard` の紙面地に差し替えずここだけは正誤の地を残す)。
 */
@Composable
fun IntroDonAnswerReveal(choices: List<String>, correctTitle: String, selectedTitle: String?) {
    val iconSize = with(LocalDensity.current) { 17.sp.toDp() }
    val shape = RoundedCornerShape(DS.rSM)
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        choices.forEach { choice ->
            val isCorrect = choice == correctTitle
            val wasSelected = choice == selectedTitle
            val tint = when {
                isCorrect -> DS.success
                wasSelected -> DS.danger
                else -> DS.ink2
            }
            val background = when {
                isCorrect -> DS.success.copy(alpha = 0.15f)
                wasSelected -> DS.danger.copy(alpha = 0.12f)
                else -> DS.fill
            }
            val icon = when {
                isCorrect -> Icons.Filled.CheckCircle
                wasSelected -> Icons.Filled.Cancel
                else -> Icons.Filled.Circle
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(background, shape)
                    .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapLoose),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(iconSize))
                ImasText(
                    choice,
                    ImasTextRole.ROW_LABEL,
                    color = tint,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
