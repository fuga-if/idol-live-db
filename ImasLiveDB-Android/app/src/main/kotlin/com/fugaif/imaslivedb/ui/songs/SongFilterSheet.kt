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
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongMyMarkFilter
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.theme.DS

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
    currentSortAscending: Boolean?,
    currentShowOtherBrand: Boolean,
    currentCollectFilter: SongCollectFilter,
    currentMyMarkFilter: SongMyMarkFilter,
    onDismiss: () -> Unit,
    onApply: (
        filter: SongSearchFilter,
        sortOrder: SongSortOrder,
        sortAscending: Boolean?,
        showOtherBrand: Boolean,
        collectFilter: SongCollectFilter,
        myMarkFilter: SongMyMarkFilter
    ) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var selectedSort by remember { mutableStateOf(currentSortOrder) }
    var sortAscending by remember { mutableStateOf(currentSortAscending) }
    var selectedBrandId by remember { mutableStateOf(currentFilter.brandId) }
    var includeRemixes by remember { mutableStateOf(currentFilter.includeRemixes) }
    var showOtherBrand by remember { mutableStateOf(currentShowOtherBrand) }
    var collectFilter by remember { mutableStateOf(currentCollectFilter) }
    var myMarkFilter by remember { mutableStateOf(currentMyMarkFilter) }

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
                color = DS.ink2,
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
                        onClick = {
                            if (selectedSort != order) sortAscending = null
                            selectedSort = order
                        }
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ImasFilterChip(label = "既定", selected = sortAscending == null, onClick = { sortAscending = null })
                ImasFilterChip(label = "昇順", selected = sortAscending == true, onClick = { sortAscending = true })
                ImasFilterChip(label = "降順", selected = sortAscending == false, onClick = { sortAscending = false })
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider()

            // Brand filter
            Text(
                text = "ブランド",
                style = MaterialTheme.typography.labelLarge,
                color = DS.ink2,
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
            SwitchRow(
                title = "リミックスを含む",
                subtitle = "アレンジ・リミックス曲を表示",
                checked = includeRemixes,
                onCheckedChange = { includeRemixes = it }
            )

            HorizontalDivider()

            // Show 'other' brand toggle (only meaningful when no brand is selected)
            SwitchRow(
                title = "その他ブランドを表示",
                subtitle = "歌枠カバー等、ブランド未設定の曲も一覧に出す",
                checked = showOtherBrand,
                onCheckedChange = { showOtherBrand = it }
            )

            HorizontalDivider()

            // My-mark filter
            Text(
                text = "マイマーク",
                style = MaterialTheme.typography.labelLarge,
                color = DS.ink2,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
            )
            SwitchRow(
                title = "担当のみ",
                subtitle = "担当アイドルが歌唱者にいる曲だけ表示",
                checked = myMarkFilter.requireMyPick,
                onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireMyPick = it) }
            )
            SwitchRow(
                title = "お気に入りのみ",
                checked = myMarkFilter.requireFavorite,
                onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireFavorite = it) }
            )

            HorizontalDivider()

            // Collect filter
            Text(
                text = "現地回収",
                style = MaterialTheme.typography.labelLarge,
                color = DS.ink2,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SongCollectFilter.entries.forEach { cf ->
                    ImasFilterChip(
                        label = cf.label,
                        selected = collectFilter == cf,
                        onClick = { collectFilter = cf }
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
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
                        sortAscending = null
                        selectedBrandId = null
                        includeRemixes = false
                        showOtherBrand = false
                        collectFilter = SongCollectFilter.ALL
                        myMarkFilter = SongMyMarkFilter()
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
                        onApply(newFilter, selectedSort, sortAscending, showOtherBrand, collectFilter, myMarkFilter)
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("適用")
                }
            }
        }
    }
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.bodyMedium)
            if (subtitle != null) {
                Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
            }
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private val SongSortOrder.label: String
    get() = when (this) {
        SongSortOrder.TITLE_KANA -> "五十音順"
        SongSortOrder.RELEASE_DATE -> "リリース日順"
        SongSortOrder.PERFORMANCE_COUNT -> "披露回数順"
        SongSortOrder.COLLECTED_COUNT -> "現地回収回数順"
        SongSortOrder.COLLECTED_RATE -> "回収率順"
    }

private val SongCollectFilter.label: String
    get() = when (this) {
        SongCollectFilter.ALL -> "すべて"
        SongCollectFilter.COLLECTED -> "回収済のみ"
        SongCollectFilter.UNCOLLECTED -> "未回収のみ"
    }
