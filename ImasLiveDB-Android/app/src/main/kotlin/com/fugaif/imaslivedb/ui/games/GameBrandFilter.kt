package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import com.fugaif.imaslivedb.ui.theme.imasTheme

/**
 * ゲーム/クイズ出題ブランドの複数選択チップ (「全て」+ 各ブランド)。
 * 選択なし = 全ブランド対象。iOS BrandIconCell グリッドの簡易版 (円形アイコンではなくチップ)。
 *
 * 呼び出し側は共有アダプタ [com.fugaif.imaslivedb.ui.components.ImasBrandPicker] に移行済み
 * (ロゴ画像にも対応する)。この定義自体は旧い部品として残してある (呼び出し側が無くなっても消さない)。
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
    val neutralAccent = imasTheme(null, null).accent
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
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
