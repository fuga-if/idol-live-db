package com.fugaif.imaslivedb.ui.events

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasTagChip
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.EventCostumeRecord
import uniffi.imas_core.EventCostumesRecord

/**
 * イベント詳細「情報」タブの衣装セクション。iOS `EventCostumesSection` と対。
 *
 * **行は衣装単位。** 着た公演は `DAY1・DAY2` の短い 1 行で添え、行を押すと
 * イベントをまたいだ着用公演の一覧 ([CostumeShowsScreen]) へ進む。
 * 説明文や出典は出さない (名前と「誰の衣装か」だけで見分ける)。
 *
 * 共通・個別の分け方と「どの公演で着たか」の 1 行は共有コアが決めている。
 * 個別衣装は数十着になるので 1 行に畳み、開いたときだけ並べる。
 */
@Composable
fun EventCostumesSection(
    costumes: EventCostumesRecord,
    brand: String?,
    onCostumeClick: (String) -> Unit
) {
    val total = costumes.shared.size + costumes.individual.size
    if (total == 0) return
    var individualExpanded by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.padding(bottom = 8.dp).fillMaxWidth()) {
        ImasSectionHeader(title = "衣装 ・ $total 着", tight = true)
        Column(
            Modifier.padding(horizontal = 16.dp).fillMaxWidth()
                .clip(RoundedCornerShape(14.dp)).background(DS.surface)
        ) {
            costumes.shared.forEachIndexed { index, entry ->
                if (index > 0) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                CostumeRow(entry, individual = false, brand = brand) { onCostumeClick(entry.costume.id) }
            }
            if (costumes.individual.isNotEmpty()) {
                if (costumes.shared.isNotEmpty()) {
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                }
                Row(
                    Modifier.fillMaxWidth()
                        .clickable { individualExpanded = !individualExpanded }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("個別衣装", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                    Text("${costumes.individual.size} 着", fontSize = 13.sp, color = DS.ink2, modifier = Modifier.weight(1f))
                    Icon(
                        if (individualExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                        contentDescription = if (individualExpanded) "畳む" else "開く",
                        tint = DS.ink3, modifier = Modifier.size(20.dp)
                    )
                }
                AnimatedVisibility(visible = individualExpanded) {
                    Column {
                        costumes.individual.forEach { entry ->
                            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                            CostumeRow(entry, individual = true, brand = brand) { onCostumeClick(entry.costume.id) }
                        }
                    }
                }
            }
        }
    }
}

/**
 * 衣装 1 着の行。個別衣装は「誰の衣装か」を名前の上に小さく出す
 * (39 人ぶん並ぶので、人で探せるようにする)。
 */
@Composable
private fun CostumeRow(entry: EventCostumeRecord, individual: Boolean, brand: String?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (individual) {
                entry.costume.attribution?.let { Text(it, fontSize = 12.sp, color = DS.ink2) }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    entry.costume.name, fontSize = 15.sp, color = DS.ink,
                    fontWeight = if (individual) FontWeight.Normal else FontWeight.SemiBold
                )
                if (!individual) {
                    entry.costume.attribution?.let { ImasTagChip(text = it, brand = brand) }
                }
            }
        }
        entry.wornInLabel?.let { Text(it, fontSize = 12.sp, color = DS.ink2, maxLines = 1) }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = DS.ink3, modifier = Modifier.size(18.dp)
        )
    }
}
