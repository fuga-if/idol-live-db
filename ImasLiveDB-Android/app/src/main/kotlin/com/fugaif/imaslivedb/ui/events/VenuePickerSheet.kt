package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 会場を 1 つ選ぶピッカー (iOS `VenuePickerView` の移植)。
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

    val filtered = remember(directory, query) {
        val q = query.trim()
        if (q.isEmpty()) {
            directory.venues
        } else {
            directory.venues.filter { v ->
                v.name.contains(q, ignoreCase = true) ||
                    (v.prefecture?.contains(q, ignoreCase = true) == true) ||
                    // 旧名でも引けるようにする (「武蔵野の森」→ 京王アリーナTOKYO)
                    v.aliasList.any { it.contains(q, ignoreCase = true) }
            }
        }
    }
    // 都道府県ごとにまとめる。244件あるので地域で塊にしないと探せない。
    val grouped = remember(filtered) {
        filtered.groupBy { it.prefecture ?: "その他" }
            .toList()
            .sortedWith(compareBy({ it.first == "その他" }, { it.second.minOf { v -> v.sortOrder } }))
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Text(
                "会場",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = DS.ink,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            NameFilterField(
                prompt = "会場を絞り込み",
                value = query,
                onValueChange = { query = it }
            )
            HorizontalDivider(color = DS.sep)

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
                    VenueRow(label = "選択なし", subtitle = null, isSelected = selected == null, muted = true) {
                        onSelect(null)
                        onDismiss()
                    }
                }
                grouped.forEach { (area, venues) ->
                    item(key = "h_$area") {
                        Text(
                            area,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = DS.ink2,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }
                    items(venues, key = { it.id }) { venue ->
                        VenueRow(
                            label = venue.name,
                            subtitle = venueSubtitle(venue),
                            isSelected = selected == venue.id,
                            muted = false
                        ) {
                            onSelect(venue.id)
                            onDismiss()
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

@Composable
private fun VenueRow(
    label: String,
    subtitle: String?,
    isSelected: Boolean,
    muted: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, fontSize = 15.sp, color = if (muted) DS.ink2 else DS.ink)
            if (subtitle != null) {
                Text(subtitle, fontSize = 12.sp, color = DS.ink3, maxLines = 1)
            }
        }
        if (isSelected) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = DS.sys, modifier = Modifier.size(18.dp))
        }
    }
    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
}
