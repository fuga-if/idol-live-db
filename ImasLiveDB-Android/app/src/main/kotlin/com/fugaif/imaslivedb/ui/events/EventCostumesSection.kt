package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasDisclosureRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
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
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasSectionHeader(
            title = "衣装",
            count = "$total 着",
            tight = true,
            modifier = Modifier.padding(horizontal = DS.Space.screen)
        )
        ImasCardList(modifier = Modifier.padding(horizontal = DS.Space.screen)) {
            costumes.shared.forEachIndexed { index, entry ->
                if (index > 0) ImasRowDivider(inset = DS.Space.screen)
                CostumeRow(entry, individual = false, brand = brand) { onCostumeClick(entry.costume.id) }
            }
            if (costumes.individual.isNotEmpty()) {
                if (costumes.shared.isNotEmpty()) ImasRowDivider(inset = DS.Space.screen)
                ImasDisclosureRow(
                    title = "個別衣装",
                    count = "${costumes.individual.size} 着",
                    isExpanded = individualExpanded,
                    onToggle = { individualExpanded = !individualExpanded }
                )
                if (individualExpanded) {
                    costumes.individual.forEach { entry ->
                        ImasRowDivider(inset = DS.Space.screen)
                        CostumeRow(entry, individual = true, brand = brand) { onCostumeClick(entry.costume.id) }
                    }
                }
            }
        }
    }
}

/**
 * 衣装 1 着の行。個別衣装は「誰の衣装か」を副題に出す
 * (39 人ぶん並ぶので、人で探せるようにする)。
 */
@Composable
private fun CostumeRow(entry: EventCostumeRecord, individual: Boolean, brand: String?, onClick: () -> Unit) {
    ImasRow(
        title = entry.costume.name,
        modifier = Modifier.imasRowPress(onClick = onClick),
        subtitle = if (individual) entry.costume.attribution else null,
        trailing = ImasRowTrailing.Custom {
            Row(
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
                verticalAlignment = Alignment.CenterVertically
            ) {
                entry.wornInLabel?.let { ImasText(it, ImasTextRole.META, maxLines = 1) }
                ImasRowChevron()
            }
        },
        density = ImasRowDensity.COMPACT,
        titleRole = ImasTextRole.ROW_LABEL,
        detail = {
            if (!individual) {
                entry.costume.attribution?.let { ImasBadge(text = it, kind = ImasBadgeKind.UNIT, brand = brand) }
            }
        }
    )
}
