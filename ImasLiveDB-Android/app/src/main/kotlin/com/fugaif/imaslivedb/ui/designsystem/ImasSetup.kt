package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasEnvTheme
import com.fugaif.imaslivedb.ui.theme.penlight
import java.text.NumberFormat

// =============================================================================
// ゲームの設定・読みもの・段階のメーター (docs/DESIGN_SYSTEM.md §2.8・§2.9・§10.4・§12)。
// iOS `ImasSetup.swift` の移植。
//
// ImasSetupHeader     設定画面の頭 (記号 + 題 + 説明)。クイズ 4 種・ソートメーカー・ティアー表。
// ImasCandidateCount  出題できる候補の数 (数えている間はくるくる)。
// ImasMeter           段階のメーター (習熟度の段・クイズの点数)。
// ImasProse           読みものの本文 (見出し・段落・箇条書き)。
// ImasStepList        手順 1・2・3。
// =============================================================================

// MARK: - 設定画面の頭

/** 設定画面の頭 (iOS `ImasSetupHeader`)。記号 (細い線の墨) + 題 (詳細の頭の大きさ) + 説明。 */
@Composable
fun ImasSetupHeader(icon: ImageVector, title: String, modifier: Modifier = Modifier, message: String? = null) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Icon(
            icon,
            contentDescription = null,
            tint = DS.ink,
            modifier = Modifier.size(with(LocalDensity.current) { 32.sp.toDp() })
        )
        Text(title, style = ImasTextRole.HERO_TITLE.style, color = ImasTextRole.HERO_TITLE.color)
        if (message != null) {
            Text(message, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
        }
    }
}

// MARK: - 候補の数

/** 候補の数の 2 つ目の指標 (「曲 + 歌手」のように軸が 2 つある出題のとき)。null の数は数えている途中。 */
@Immutable
data class ImasCandidateMetric(val count: Int?, val unit: String = "曲")

/**
 * 出題できる候補の数 (iOS `ImasCandidateCount`)。数えている間はくるくる、足りないときは注意の色。
 *
 * @param count 候補の数。null は数えている途中。
 * @param minimum 足りるための数。下回ると数を注意の色 (`DS.warning`) にする。
 * @param secondary 2 つ目の指標。渡すと「37 曲 / 12 歌手」のように並べる。
 * @param note 数の下に添える一言 (「4択の選択肢は歌手数が基準です」)。
 */
@Composable
fun ImasCandidateCount(
    count: Int?,
    modifier: Modifier = Modifier,
    unit: String = "曲",
    minimum: Int? = null,
    label: String = "出題できる候補",
    secondary: ImasCandidateMetric? = null,
    note: String? = null
) {
    val isShort = count != null && minimum != null && count < minimum
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = DS.Size.touch + 4.dp)
            .background(DS.surface, RoundedCornerShape(DS.rCard))
            .padding(horizontal = DS.Space.rowH, vertical = if (note == null) 0.dp else DS.Space.gapTight)
            .semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight, Alignment.CenterVertically)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = DS.Size.touch + 4.dp - if (note == null) 0.dp else DS.Space.gapTight * 2),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(label, style = ImasTextRole.VALUE.style, color = DS.ink2, modifier = Modifier.weight(1f))
            CandidateMetric(count, unit, if (isShort) DS.warning else DS.ink)
            if (secondary != null) {
                Text("/", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
                CandidateMetric(secondary.count, secondary.unit, DS.ink)
            }
        }
        if (note != null) {
            Text(note, style = ImasTextRole.META.style, color = ImasTextRole.META.color)
        }
    }
}

@Composable
private fun CandidateMetric(value: Int?, unit: String, color: androidx.compose.ui.graphics.Color) {
    if (value != null) {
        ImasMetric(
            NumberFormat.getIntegerInstance().format(value),
            unit = unit,
            size = ImasNumeralSize.MEDIUM,
            color = color
        )
    } else {
        CircularProgressIndicator(Modifier.size(16.dp), color = DS.ink3, strokeWidth = 2.dp)
    }
}

// MARK: - 段階のメーター

/**
 * 段階のメーター (iOS `ImasMeter`)。[value] 段まで実体の色 (無ければ墨) で塗る (習熟度・クイズの点数)。
 * 色は環境の実体の色 (`ImasThemeProvider`)。
 */
@Composable
fun ImasMeter(value: Int, total: Int, modifier: Modifier = Modifier) {
    val on = imasEnvTheme.penlight
    val off = DS.fill
    Row(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "$total 段中 $value 段" },
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        repeat(maxOf(total, 1)) { i ->
            Box(
                Modifier
                    .weight(1f)
                    .height(6.dp)
                    .background(if (i < value) on else off)
            )
        }
    }
}

// MARK: - 読みもの

/** 読みものの段落の種類 (iOS `ImasProse.Block`)。 */
@Immutable
sealed interface ImasProseBlock {
    data class Heading(val text: String) : ImasProseBlock
    data class Paragraph(val text: String) : ImasProseBlock
    data class Bullets(val items: List<String>) : ImasProseBlock
    data class Note(val text: String) : ImasProseBlock
}

/** 読みものの本文 (iOS `ImasProse`)。見出し・段落・箇条書きを並べる。 */
@Composable
fun ImasProse(blocks: List<ImasProseBlock>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
        blocks.forEach { block ->
            when (block) {
                is ImasProseBlock.Heading -> Text(
                    block.text,
                    style = ImasTextRole.CARD_TITLE.style,
                    color = ImasTextRole.CARD_TITLE.color,
                    modifier = Modifier.padding(top = DS.Space.gap)
                )
                is ImasProseBlock.Paragraph -> Text(block.text, style = ImasTextRole.BODY.style, color = ImasTextRole.BODY.color)
                is ImasProseBlock.Bullets -> Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                    block.items.forEach { item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                            Text("・", style = ImasTextRole.BODY.style, color = ImasTextRole.BODY.color, modifier = Modifier.alignByBaseline())
                            Text(item, style = ImasTextRole.BODY.style, color = ImasTextRole.BODY.color, modifier = Modifier.alignByBaseline())
                        }
                    }
                }
                is ImasProseBlock.Note -> ImasNote(block.text)
            }
        }
    }
}

/** 手順 1 つ (iOS `ImasStepList.Step`)。[media] は手順に添える説明の絵 (任意)。 */
@Immutable
class ImasStep(
    val title: String,
    val detail: String? = null,
    val media: (@Composable () -> Unit)? = null
)

/** 手順 1・2・3 (iOS `ImasStepList`)。番号は墨の丸に細長い数字。 */
@Composable
fun ImasStepList(steps: List<ImasStep>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
        steps.forEachIndexed { index, step ->
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.rowGap)) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                    Box(
                        Modifier
                            .size(26.dp)
                            .background(DS.sys, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("${index + 1}", style = ImasNumeralSize.SMALL.style, color = DS.onSys, maxLines = 1)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text(step.title, style = ImasTextRole.ROW_TITLE.style, color = ImasTextRole.ROW_TITLE.color)
                        if (step.detail != null) {
                            Text(step.detail, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
                        }
                    }
                }
                step.media?.invoke()
            }
        }
    }
}
