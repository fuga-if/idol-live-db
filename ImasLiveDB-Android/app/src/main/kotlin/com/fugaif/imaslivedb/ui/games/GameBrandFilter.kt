package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.brandColor

/**
 * ゲーム/クイズ出題ブランドの複数選択チップ (「全て」+ 各ブランド)。
 * 選択なし = 全ブランド対象。iOS BrandIconCell グリッドの簡易版 (円形アイコンではなくチップ)。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GameBrandFilterGrid(
    brands: List<Brand>,
    selectedBrandIds: Set<String>,
    onToggle: (String) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier
) {
    val neutralAccent = ImasTheme.derive(null, null, dark = true).accent
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ImasFilterChip(
            label = "全て",
            selected = selectedBrandIds.isEmpty(),
            onClick = onClearAll,
            tintColor = neutralAccent
        )
        brands.forEach { brand ->
            ImasFilterChip(
                label = brand.shortName,
                selected = selectedBrandIds.contains(brand.id),
                onClick = { onToggle(brand.id) },
                tintColor = brandColor(brand.id)
            )
        }
    }
}
