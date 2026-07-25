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
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 会場を 1 つ選ぶピッカー (iOS `ListPickerView` の会場用途に相当)。
 *
 * 会場は 400 件近くあるので、絞り込みフィールドを常設する。
 * 会場名は "千葉・幕張メッセ国際展示場" 形式なので、「幕張」でも「千葉」でも引ける。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenuePickerSheet(
    venues: List<String>,
    selected: String?,
    onSelect: (String?) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var query by remember { mutableStateOf("") }

    val filtered = remember(venues, query) {
        val q = query.trim()
        if (q.isEmpty()) venues else venues.filter { it.contains(q, ignoreCase = true) }
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
                    VenueRow(label = "選択なし", isSelected = selected == null, muted = true) {
                        onSelect(null)
                        onDismiss()
                    }
                }
                items(filtered, key = { it }) { venue ->
                    VenueRow(label = venue, isSelected = selected == venue, muted = false) {
                        onSelect(venue)
                        onDismiss()
                    }
                }
            }
        }
    }
}

@Composable
private fun VenueRow(label: String, isSelected: Boolean, muted: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(label, fontSize = 15.sp, color = if (muted) DS.ink2 else DS.ink, modifier = Modifier.weight(1f))
        if (isSelected) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = DS.sys, modifier = Modifier.size(18.dp))
        }
    }
    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
}
