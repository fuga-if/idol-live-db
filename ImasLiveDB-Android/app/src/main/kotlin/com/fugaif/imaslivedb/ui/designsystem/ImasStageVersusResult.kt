package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.hexToColor

// =============================================================================
// 対戦の表示部品 (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageVersusResult.swift` の移植。
//
// ImasStageScoreChip     多人数の対戦中の軽い点数の表示 (色の点 + 名前 + 点数)。
// ImasStageVersusResult  1 対 1 の対戦の最後の結果 (勝者の見出し + 2 人分の点数 + 操作)。
//
// 色は対戦者が選んだ色 (データの色) とステージ固定の `QS`。
// =============================================================================

/** 多人数の対戦中の軽い点数の表示 (iOS `ImasStageScoreChip`)。 */
@Composable
fun ImasStageScoreChip(colorHex: String, name: String, score: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(10.dp).background(hexToColor(colorHex), CircleShape))
        Text(name, style = QS.text(12, FontWeight.Bold), color = QS.dim)
        Text("$score", style = QS.text(18, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = QS.ink)
    }
}

/** 対戦者 1 人 (iOS `ImasStageVersusResult.Player`)。 */
@Immutable
data class ImasStageVersusPlayer(val name: String, val colorHex: String, val score: Int)

/**
 * 1 対 1 の対戦の最後の結果 (iOS `ImasStageVersusResult`)。
 *
 * @param winnerColorHex 勝者の色 (引き分けは null)。見出しの色になる。
 * @param actions 下に縦に並べる操作 (もう一度・終わる)。
 */
@Composable
fun ImasStageVersusResult(
    winnerColorHex: String?,
    headline: String,
    players: Pair<ImasStageVersusPlayer, ImasStageVersusPlayer>,
    modifier: Modifier = Modifier,
    actions: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically)
    ) {
        Text(
            headline,
            style = QS.text(28, FontWeight.Black),
            color = winnerColorHex?.let(::hexToColor) ?: QS.ink
        )
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
            PlayerScore(players.first)
            Text("vs", style = QS.text(14, FontWeight.Bold), color = QS.faint)
            PlayerScore(players.second)
        }
        Column(
            Modifier.padding(horizontal = 40.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = actions
        )
    }
}

@Composable
private fun PlayerScore(p: ImasStageVersusPlayer) {
    Column(
        Modifier.semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(p.name, style = QS.text(14, FontWeight.Bold), color = hexToColor(p.colorHex))
        Text("${p.score}", style = QS.text(44, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = QS.ink)
    }
}
