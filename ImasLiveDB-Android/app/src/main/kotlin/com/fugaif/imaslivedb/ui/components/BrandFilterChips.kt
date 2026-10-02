package com.fugaif.imaslivedb.ui.components

import com.fugaif.imaslivedb.ui.designsystem.ImasChipRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor

/**
 * Data class representing a brand entry for the filter row.
 *
 * @param id        Brand ID matching the DB (e.g. "765as", "cg")
 * @param shortName Short display name (e.g. "765", "CG")
 */
data class BrandFilterItem(
    val id: String,
    val shortName: String
)

/**
 * Horizontal scrollable row of brand filter chips.
 * Includes a "全て" chip for clearing the filter.
 * Mirrors iOS BrandFilterChips behavior.
 *
 * @param brands          List of brands to display as chips
 * @param selectedBrandId Currently selected brand ID, or null for "all"
 * @param onBrandSelected Called with the brand ID, or null when "全て" is tapped
 */
@Composable
fun BrandFilterChips(
    brands: List<BrandFilterItem>,
    selectedBrandId: String?,
    onBrandSelected: (String?) -> Unit,
    modifier: Modifier = Modifier
) {
    ImasChipRow(modifier = modifier.padding(vertical = DS.Space.header)) {
        // "全て" chip
        ImasFilterChip(
            label = "全て",
            selected = selectedBrandId == null,
            onClick = { onBrandSelected(null) },
        )

        brands.forEach { brand ->
            val color = brandColor(brand.id)
            ImasFilterChip(
                label = brand.shortName,
                selected = selectedBrandId == brand.id,
                onClick = { onBrandSelected(brand.id) },
                tintColor = color
            )
        }
    }
}
