package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType

// =============================================================================
// 料金表 (docs/DESIGN_SYSTEM.md §6.7 電光掲示板と同じ配色)。iOS `Events/ImasPriceList.swift` の移植。
//
// セトリ・公演詳細のチケット価格。`ImasBoard` と同じ暗い板に、「種類 … ¥ 細長い数字」の行を縦に並べる。
// 価格帯 (複数券種) は内訳行を薄く従える。金額はコアが整形済みの文字列 (`formatYen` など) をそのまま置く。
// =============================================================================

/**
 * 料金表の 1 行 (iOS `ImasPriceList.Row`)。
 *
 * @param label 券種・名前 (「一般指定席」「ERISA」)。
 * @param amount 金額。コアが整形済みの文字列 (「¥9,800」「¥5,500〜¥13,200」)。
 * @param note 薄く添える注記 (「推定含む」)。
 * @param indented 価格帯の内訳行 (少し下げて小さく出す)。
 * @param copyable 長押しで「〈券種〉をコピー」を出す。
 */
@Immutable
data class ImasPriceRow(
    val id: String,
    val label: String,
    val amount: String,
    val note: String? = null,
    val indented: Boolean = false,
    val copyable: Boolean = true
)

/** 料金表 (iOS `ImasPriceList`)。暗い板に券種と金額を並べる。板はライトでもダークでも暗い。 */
@Composable
fun ImasPriceList(rows: List<ImasPriceRow>, modifier: Modifier = Modifier, title: String? = null) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(DS.board, shape)
    ) {
        if (title != null) {
            Text(
                title,
                style = ImasTextRole.IMPRINT.style,
                color = DS.boardDim,
                modifier = Modifier.padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = 8.dp)
            )
            Box(Modifier.fillMaxWidth().height(1.dp).background(DS.boardLine))
        }
        rows.forEachIndexed { index, row ->
            if (index > 0) {
                Box(
                    Modifier
                        .padding(start = if (row.indented) 28.dp else 14.dp)
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(DS.boardLine)
                )
            }
            PriceRow(row)
        }
    }
}

@Composable
private fun PriceRow(row: ImasPriceRow) {
    ImasCopyableRow(
        items = if (row.copyable) listOf(CopyItem("${row.label}をコピー", row.amount)) else emptyList(),
        modifier = Modifier.fillMaxWidth(),
        onClick = null
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) { }
                .padding(start = if (row.indented) 28.dp else 14.dp, end = 14.dp)
                .padding(vertical = if (row.indented) 10.dp else 12.dp),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
        ) {
            Column(
                Modifier
                    .weight(1f)
                    .alignByBaseline(),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    row.label,
                    style = if (row.indented) ImasType.text(13.sp) else ImasType.text(15.sp, FontWeight.SemiBold),
                    color = if (row.indented) DS.boardDim else DS.boardInk,
                    maxLines = 2
                )
                if (row.note != null) {
                    Text(row.note, style = ImasType.text(11.sp), color = DS.boardDim)
                }
            }
            ImasFitText(
                row.amount,
                style = if (row.indented) ImasNumeralSize.SMALL.style else ImasNumeralSize.MEDIUM.style,
                color = DS.boardInk,
                minScale = 0.7f,
                modifier = Modifier
                    .widthIn(max = 220.dp)
                    .alignByBaseline()
            )
        }
    }
}
