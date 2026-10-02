package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasListBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import uniffi.imas_core.VenueAreaEntry
import uniffi.imas_core.groupVenuesByArea

/**
 * 会場を 1 つ選ぶピッカー (iOS `VenuePickerView` の移植)。見た目は DesignSystem の
 * `ImasSelectableRow` (選択の印) + `ImasSectionHeader` (都道府県の見出し)。
 *
 * 会場は **ID で選ぶ**。名前で持つと改名 (武蔵野の森総合スポーツプラザ →
 * 京王アリーナTOKYO) や表記揺れで絞り込みが外れてしまうため。
 * 検索は現行名に加えて **旧名・別名・都道府県** も対象にするので、「武蔵野の森」でも
 * 「京王アリーナ」でも同じ会場に辿り着ける。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenuePickerSheet(
    directory: VenueDirectory,
    selected: String?,
    onSelect: (String?) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var query by remember { mutableStateOf("") }

    // 綴りは現行名・読み・都道府県・別名 (旧名/通称)。以前は `contains` を並べていて、
    // `venues.name_kana` を持っているのに読みで引けなかった (「ぶどうかん」で出ない)。
    val filtered = rememberSearchFiltered(directory.venues, query) { v ->
        // 旧名でも引けるようにする (「武蔵野の森」→ 京王アリーナTOKYO)
        listOf(v.name, v.nameKana, v.prefecture) + v.aliasList
    }
    // 都道府県ごとにまとめる。244件あるので地域で塊にしないと探せない。
    // 塊の切り方・並び・「その他」はコア (groupVenuesByArea)。
    val grouped = remember(filtered) {
        groupVenuesByArea(filtered.map { VenueAreaEntry(it.prefecture, it.sortOrder.toLong()) })
            .map { group -> group.label to group.indices.map { filtered[it.toInt()] } }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        ImasListBackdrop(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Column(Modifier.fillMaxWidth()) {
                Text(
                    "会場",
                    style = ImasType.heading(17.sp, FontWeight.Bold),
                    color = DS.ink,
                    maxLines = 1,
                    modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                )
                NameFilterField(
                    prompt = "会場を絞り込み",
                    value = query,
                    onValueChange = { query = it }
                )

                if (filtered.isEmpty()) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                        ImasEmptyState(
                            icon = Icons.Filled.Search,
                            title = "見つかりません",
                            message = "「$query」に一致する会場がありません"
                        )
                    }
                    return@Column
                }

                LazyColumn(Modifier.fillMaxWidth()) {
                    item {
                        ImasSelectableRow(
                            title = "選択なし",
                            isSelected = selected == null,
                            isSingle = true,
                            position = ImasRowPosition.FIRST,
                            onClick = {
                                onSelect(null)
                                onDismiss()
                            }
                        )
                    }
                    grouped.forEach { (area, venues) ->
                        item(key = "h_$area") {
                            ImasSectionHeader(title = area, tight = true)
                        }
                        itemsIndexed(venues, key = { _, v -> v.id }) { index, venue ->
                            ImasSelectableRow(
                                title = venue.name,
                                subtitle = venueSubtitle(venue),
                                isSelected = selected == venue.id,
                                isSingle = true,
                                position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING,
                                onClick = {
                                    onSelect(venue.id)
                                    onDismiss()
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

/** キャパと旧名を副題に出す。キャパは出典が取れた会場だけ入っているので null もある。 */
private fun venueSubtitle(venue: Venue): String? {
    val parts = buildList {
        venue.capacityLabel?.let { add(it) }
        venue.aliasList.firstOrNull()?.let { add("旧: $it") }
    }
    return parts.joinToString(" ・ ").ifEmpty { null }
}
