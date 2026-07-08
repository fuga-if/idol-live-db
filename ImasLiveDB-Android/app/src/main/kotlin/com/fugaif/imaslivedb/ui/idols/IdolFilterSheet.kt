package com.fugaif.imaslivedb.ui.idols

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor

/**
 * アイドル一覧のフィルタシート。iOS `IdolFilterSheet` の移植:
 * 表示形式(名前/CV名 + CV併記) + ブランド複数選択 + 属性(単一ブランド選択時のみ) + マイマーク3種。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
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
    onDismiss: () -> Unit,
    onApply: (
        brandIds: Set<String>,
        attribute: String?,
        displayMode: IdolDisplayMode,
        showCV: Boolean,
        requireMyPick: Boolean,
        requireFavorite: Boolean,
        requireNote: Boolean
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

    // 属性チップは単一ブランド選択時のみ (ブランド共通のサブ属性が無いため)。
    val attributesForBrand = brandIds.singleOrNull()?.let { IDOL_BRAND_ATTRIBUTES[it] } ?: emptyList()

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 32.dp)
        ) {
            Text(
                "フィルタ",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = DS.ink,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            HorizontalDivider(color = DS.sep)

            SectionLabel("表示形式")
            ImasSegmented(
                labels = listOf("アイドル名", "CV名"),
                selection = if (displayMode == IdolDisplayMode.CV_NAME) 1 else 0,
                onSelect = { displayMode = if (it == 1) IdolDisplayMode.CV_NAME else IdolDisplayMode.IDOL_NAME },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
            )
            SwitchRow(
                title = "CV名を併記",
                subtitle = "アイドル名表示中、CV名を別行で表示する",
                checked = showCV,
                enabled = displayMode == IdolDisplayMode.IDOL_NAME,
                onCheckedChange = { showCV = it }
            )

            HorizontalDivider(color = DS.sep)
            SectionLabel("ブランド")
            FlowRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                brands.forEach { brand ->
                    ImasFilterChip(
                        label = brand.shortName,
                        selected = brandIds.contains(brand.id),
                        tintColor = brandColor(brand.id),
                        onClick = {
                            brandIds = if (brandIds.contains(brand.id)) {
                                brandIds - brand.id
                            } else {
                                brandIds + brand.id
                            }
                            attribute = null
                        }
                    )
                }
            }

            if (attributesForBrand.isNotEmpty()) {
                HorizontalDivider(color = DS.sep)
                SectionLabel("属性")
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ImasFilterChip(label = "全て", selected = attribute == null, onClick = { attribute = null })
                    attributesForBrand.forEach { (value, label) ->
                        ImasFilterChip(label = label, selected = attribute == value, onClick = { attribute = value })
                    }
                }
            }

            HorizontalDivider(color = DS.sep)
            SectionLabel("マイマーク")
            SwitchRow(title = "担当のみ", checked = requireMyPick, onCheckedChange = { requireMyPick = it }, tint = DS.pick)
            SwitchRow(title = "お気に入りのみ", checked = requireFavorite, onCheckedChange = { requireFavorite = it }, tint = DS.favorite)
            SwitchRow(title = "メモがあるアイドルのみ", checked = requireNote, onCheckedChange = { requireNote = it })

            Spacer(Modifier.height(8.dp))
            HorizontalDivider(color = DS.sep)
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TextButton(
                    onClick = {
                        brandIds = emptySet()
                        attribute = null
                        requireMyPick = false
                        requireFavorite = false
                        requireNote = false
                    },
                    modifier = Modifier.weight(1f)
                ) { Text("リセット") }
                Button(
                    onClick = {
                        onApply(brandIds, attribute, displayMode, showCV, requireMyPick, requireFavorite, requireNote)
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f)
                ) { Text("適用") }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = DS.ink2,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    enabled: Boolean = true,
    tint: androidx.compose.ui.graphics.Color? = null,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = if (enabled) DS.ink else DS.ink3)
            if (subtitle != null) {
                Text(subtitle, fontSize = 12.sp, color = DS.ink3)
            }
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled,
            colors = if (tint != null) {
                SwitchDefaults.colors(checkedTrackColor = tint, checkedThumbColor = DS.surface)
            } else {
                SwitchDefaults.colors()
            }
        )
    }
}
