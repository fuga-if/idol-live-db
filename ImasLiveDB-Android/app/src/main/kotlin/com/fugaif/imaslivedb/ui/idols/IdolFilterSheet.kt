package com.fugaif.imaslivedb.ui.idols

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.ui.components.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasMenuRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * アイドル一覧のフィルタシート。iOS `IdolFilterSheet` の移植:
 * 表示形式(名前/CV名 + CV併記) + 並び順 + ブランド複数選択 + 属性(単一ブランド選択時のみ) + マイマーク3種。
 *
 * 見た目は `EventFilterSheet` と同じ体裁 (`ImasFilterSheetToolbar` + `ImasListSection` の区画)。
 * リセットはツールバーにだけ置き、画面末尾には置かない (DESIGN_SYSTEM.md §2.6)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolFilterSheet(
    brands: List<Brand>,
    currentBrandIds: Set<String>,
    currentAttribute: String?,
    currentDisplayMode: IdolDisplayMode,
    currentShowCV: Boolean,
    currentRequireMyPick: Boolean,
    currentRequireFavorite: Boolean,
    currentRequireNote: Boolean,
    currentSortOrder: IdolSortOrder,
    currentSortAscending: Boolean?,
    onDismiss: () -> Unit,
    onApply: (
        brandIds: Set<String>,
        attribute: String?,
        displayMode: IdolDisplayMode,
        showCV: Boolean,
        requireMyPick: Boolean,
        requireFavorite: Boolean,
        requireNote: Boolean,
        sortOrder: IdolSortOrder,
        sortAscending: Boolean?
    ) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var displayMode by remember { mutableStateOf(currentDisplayMode) }
    var showCV by remember { mutableStateOf(currentShowCV) }
    var brandIds by remember { mutableStateOf(currentBrandIds) }
    var attribute by remember { mutableStateOf(currentAttribute) }
    var requireMyPick by remember { mutableStateOf(currentRequireMyPick) }
    var requireFavorite by remember { mutableStateOf(currentRequireFavorite) }
    var requireNote by remember { mutableStateOf(currentRequireNote) }
    var sortOrder by remember { mutableStateOf(currentSortOrder) }
    var sortAscending by remember { mutableStateOf(currentSortAscending) }

    // 属性チップは単一ブランド選択時のみ (ブランド共通のサブ属性が無いため)。
    val attributesForBrand = brandIds.singleOrNull()?.let { IDOL_BRAND_ATTRIBUTES[it] } ?: emptyList()

    // リセットは絞り込みと並び順だけ戻す (表示形式と CV名併記は表示の好みなので残す。前の Android と同じ)。
    val hasActiveFilters = brandIds.isNotEmpty() || attribute != null ||
        requireMyPick || requireFavorite || requireNote ||
        sortOrder != IdolSortOrder.OFFICIAL || sortAscending != null

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        ImasFormBackdrop(Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = DS.sp8)
            ) {
                ImasFilterSheetToolbar(
                    canReset = hasActiveFilters,
                    onReset = {
                        brandIds = emptySet()
                        attribute = null
                        requireMyPick = false
                        requireFavorite = false
                        requireNote = false
                        sortOrder = IdolSortOrder.OFFICIAL
                        sortAscending = null
                    },
                    onApply = {
                        onApply(brandIds, attribute, displayMode, showCV, requireMyPick, requireFavorite, requireNote, sortOrder, sortAscending)
                        onDismiss()
                    },
                    title = "フィルタ"
                )

                ImasListSection(title = "表示形式") {
                    ImasSegmented(
                        labels = listOf("アイドル名", "CV名"),
                        selection = if (displayMode == IdolDisplayMode.CV_NAME) 1 else 0,
                        onSelect = { displayMode = if (it == 1) IdolDisplayMode.CV_NAME else IdolDisplayMode.IDOL_NAME },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                    // CV名表示中は併記の意味が無いので押せなくする。
                    ImasToggleRow(
                        title = "CV名を併記",
                        subtitle = "アイドル名表示中、CV名を別行で表示する",
                        isOn = showCV,
                        onCheckedChange = { showCV = it },
                        enabled = displayMode == IdolDisplayMode.IDOL_NAME
                    )
                }

                ImasListSection(
                    title = "並び順",
                    footer = if (sortOrder.keepsBrandGrouping) null else "ブランドの区切りを外して通しで並べます"
                ) {
                    ImasMenuRow(
                        title = "並び順",
                        options = IdolSortOrder.entries,
                        selection = sortOrder,
                        onSelect = {
                            sortOrder = it
                            // 並び順を変えたら方向は新しい並び順の既定に戻す
                            // (「高い順」のまま誕生日に切り替わると 12月からになって驚くため)。
                            sortAscending = null
                        },
                        label = { it.label }
                    )
                    ImasSegmented(
                        labels = listOf(sortOrder.ascendingLabel, sortOrder.descendingLabel),
                        selection = if (sortAscending ?: sortOrder.defaultAscending) 0 else 1,
                        onSelect = { sortAscending = it == 0 },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                }

                ImasListSection(title = "ブランド") {
                    ImasBrandPicker(
                        brands = brands,
                        includesAll = false,
                        selection = brandIds,
                        onSelectionChange = { brandIds = it; attribute = null },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                }

                if (attributesForBrand.isNotEmpty()) {
                    ImasListSection(title = "属性") {
                        ImasChipFlow(modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
                            ImasFilterChip(label = "全て", selected = attribute == null, onClick = { attribute = null })
                            attributesForBrand.forEach { (value, label) ->
                                ImasFilterChip(label = label, selected = attribute == value, onClick = { attribute = value })
                            }
                        }
                    }
                }

                ImasListSection(title = "マイマーク") {
                    ImasToggleRow(title = "担当のみ", isOn = requireMyPick, onCheckedChange = { requireMyPick = it })
                    ImasToggleRow(title = "お気に入りのみ", isOn = requireFavorite, onCheckedChange = { requireFavorite = it })
                    ImasToggleRow(title = "メモがあるアイドルのみ", isOn = requireNote, onCheckedChange = { requireNote = it })
                }
            }
        }
    }
}
