package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasFilterChip

private val ALL_BRANDS = listOf(
    BrandFilterItem("765as", "765"),
    BrandFilterItem("cg", "CG"),
    BrandFilterItem("ml", "ML"),
    BrandFilterItem("sidem", "SideM"),
    BrandFilterItem("sc", "シャニ"),
    BrandFilterItem("gakuen", "学マス"),
    BrandFilterItem("valiv", "ヴイアラ"),
    BrandFilterItem("876", "876"),
    BrandFilterItem("961", "961")
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongFilterSheet(
    currentFilter: SongSearchFilter,
    currentSortOrder: SongSortOrder,
    onDismiss: () -> Unit,
    onApply: (SongSearchFilter, SongSortOrder) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var selectedSort by remember { mutableStateOf(currentSortOrder) }
    var selectedBrandId by remember { mutableStateOf(currentFilter.brandId) }
    var includeRemixes by remember { mutableStateOf(currentFilter.includeRemixes) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 32.dp)
        ) {
            // Sheet header
            Text(
                text = "フィルター・並び替え",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )

            HorizontalDivider()

            // Sort order picker
            Text(
                text = "並び順",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SongSortOrder.entries.forEach { order ->
                    ImasFilterChip(
                        label = order.label,
                        selected = selectedSort == order,
                        onClick = { selectedSort = order }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider()

            // Brand filter
            Text(
                text = "ブランド",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
            )
            BrandFilterChips(
                brands = ALL_BRANDS,
                selectedBrandId = selectedBrandId,
                onBrandSelected = { selectedBrandId = it }
            )

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()

            // Include remixes toggle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "リミックスを含む",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = "アレンジ・リミックス曲を表示",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = includeRemixes,
                    onCheckedChange = { includeRemixes = it }
                )
            }

            HorizontalDivider()

            // Action buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TextButton(
                    onClick = {
                        selectedSort = SongSortOrder.TITLE_KANA
                        selectedBrandId = null
                        includeRemixes = false
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("リセット")
                }
                Button(
                    onClick = {
                        val newFilter = currentFilter.copy(
                            brandId = selectedBrandId,
                            includeRemixes = includeRemixes
                        )
                        onApply(newFilter, selectedSort)
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("適用")
                }
            }
        }
    }
}

private val SongSortOrder.label: String
    get() = when (this) {
        SongSortOrder.TITLE_KANA -> "五十音順"
        SongSortOrder.RELEASE_DATE -> "リリース日順"
        SongSortOrder.PERFORMANCE_COUNT -> "披露回数順"
    }
