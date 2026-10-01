package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasEnvTheme

// =============================================================================
// 札と数字 (docs/DESIGN_SYSTEM.md §10.1・§10.2)。iOS `ImasLabels.swift` の移植。
//
// ImasBadge          状態の札 (押せない)。セトリの役割・参加済・受付中・NEW など。
//                    高さ 20 の角の小さい四角 (角丸 4)、11 太字。押せるものには使わない。
//                    色で意味を分けない: 線 (分類) / 墨 (予定・主演) / 朱の線 (済んだ記録) / 朱 (新着) だけ。
//                    札ごとに色を変えると淡い色の札が並ぶ「よくある見た目」になる。意味は文字が言う。
// ImasMetric         数字 + 単位。数字はステージと同じ「細長い太字・等幅」。
// ImasProportionLine 割合を行の下端などに細い線で示す。
// =============================================================================

/** 札の種類 (iOS `ImasBadge.Kind`)。見え方は 4 つだけで、意味は文字が言う。 */
enum class ImasBadgeKind {
    // セトリの役割 (分類なので灰)
    /** ユニット曲。 */
    UNIT,

    /** 全員。 */
    ALL,

    /** カバー。 */
    COVER,

    /** 一部のメンバー。 */
    PARTIAL,

    /** 主演 (墨)。 */
    LEAD,

    /** ゲスト (線)。 */
    GUEST,

    // 状態
    /** 参加済・当選・回収 (朱の線。判子を押した記録)。 */
    POSITIVE,

    /** 参加予定・チケットあり (墨の塗り。手元にある券)。 */
    PLANNED,

    /** 受付中・締切間近・下書き (墨の線)。 */
    ATTENTION,

    /** 落選・中止・差し戻し (灰の薄字)。 */
    NEGATIVE,

    /** 終了・未定・配信・LV (灰)。 */
    NEUTRAL,

    /** 新着 (朱)。 */
    NEW,

    /** 実体の色の線 (タグの票数など、色で所属を示したい数)。 */
    THEMED
}

/**
 * 状態の札 (iOS `ImasBadge`)。押せない。押せるならチップ (`ImasFilterChip`)。
 *
 * @param icon 文字の前の記号 (iOS の `systemImage`)。
 * @param seed 実体の色 hex ([ImasBadgeKind.THEMED] の線の色)。
 * @param brand ブランド ID (seed が無いときの色)。どちらも無ければ環境の実体の色。
 */
@Composable
fun ImasBadge(
    text: String,
    modifier: Modifier = Modifier,
    kind: ImasBadgeKind = ImasBadgeKind.NEUTRAL,
    icon: ImageVector? = null,
    seed: String? = null,
    brand: String? = null
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val shape = RoundedCornerShape(DS.rTag)
    val (bg, fg, stroke) = when (kind) {
        ImasBadgeKind.UNIT, ImasBadgeKind.ALL, ImasBadgeKind.COVER, ImasBadgeKind.PARTIAL, ImasBadgeKind.NEUTRAL ->
            Triple(Color.Transparent, DS.ink2, DS.line)
        ImasBadgeKind.LEAD, ImasBadgeKind.PLANNED -> Triple(DS.sys, DS.onSys, null)
        ImasBadgeKind.POSITIVE -> Triple(Color.Transparent, DS.stamp, DS.stamp)
        // iOS と同じく朱の塗りに白 (どちらのモードの朱でも白が読める)。
        ImasBadgeKind.NEW -> Triple(DS.stamp, Color.White, null)
        ImasBadgeKind.ATTENTION -> Triple(Color.Transparent, DS.ink, DS.ink)
        ImasBadgeKind.GUEST -> Triple(Color.Transparent, DS.ink2, DS.line)
        ImasBadgeKind.NEGATIVE -> Triple(Color.Transparent, DS.ink3, DS.sep)
        ImasBadgeKind.THEMED -> {
            val c = if (t.isNeutral) DS.ink else t.accent
            Triple(Color.Transparent, c, c.copy(alpha = 0.55f))
        }
    }
    // 記号は札の文字 (11) より一回り小さく、文字の大きさの設定に合わせる。
    val iconSize = with(LocalDensity.current) { 10.sp.toDp() }
    Row(
        modifier
            .heightIn(min = DS.Size.badge)
            .background(bg, shape)
            .then(if (stroke != null) Modifier.border(1.dp, stroke, shape) else Modifier)
            .padding(horizontal = 6.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(iconSize))
        Text(
            text,
            style = ImasTextRole.BADGE.style.copy(fontFeatureSettings = "tnum"),
            color = fg,
            maxLines = 1
        )
    }
}

/**
 * 数字 + 単位 (iOS `ImasMetric`)。並べ替えの根拠・票・確率・回数・統計の値。
 *
 * @param emphasized 強調する (1〜3 位・0 でない値など)。強調は墨、そうでなければ灰。色では飾らない。
 *   大 ([ImasNumeralSize.LARGE]) はいつも墨。
 * @param color 数の色を意味の色に替えるとき (足りない候補の数を注意の色にする `ImasCandidateCount` など)。
 */
@Composable
fun ImasMetric(
    value: String,
    modifier: Modifier = Modifier,
    unit: String? = null,
    size: ImasNumeralSize = ImasNumeralSize.MEDIUM,
    emphasized: Boolean = false,
    color: Color? = null
) {
    Row(
        modifier.semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        ImasFitText(
            value,
            style = size.style,
            color = color ?: if (emphasized || size == ImasNumeralSize.LARGE) DS.ink else DS.ink2,
            minScale = 0.6f,
            modifier = Modifier.alignByBaseline().weight(1f, fill = false)
        )
        if (!unit.isNullOrEmpty()) {
            Text(unit, style = size.unitStyle, color = DS.ink3, maxLines = 1, modifier = Modifier.alignByBaseline())
        }
    }
}

/**
 * 割合を行の下端などに細い線で示す (iOS `ImasProportionLine`)。票・確率の大きさ。数字を読まなくても差が分かる。
 * 色は環境の実体の色の帯 (無ければ墨)。
 *
 * @param fraction 0〜1。
 */
@Composable
fun ImasProportionLine(fraction: Double, modifier: Modifier = Modifier) {
    val theme = imasEnvTheme
    val fill = if (theme.isNeutral) DS.ink else theme.bar
    val f = fraction.coerceIn(0.0, 1.0).toFloat()
    Box(
        modifier
            .fillMaxWidth()
            .height(2.dp)
            .background(DS.fill)
            .clearAndSetSemantics { }
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .widthIn(min = 2.dp)
                .fillMaxWidth(f)
                .background(fill)
        )
    }
}
