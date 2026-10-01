package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasLeadBar

/**
 * イベントカード左端のブランドの色の帯 (iOS `BrandColorBar` と対)。見た目は DS の [ImasLeadBar]
 * (ブランドの色が引けないときは [ImasLeadBar] 自身のニュートラルの色に委ねる)。
 */
@Composable
fun BrandColorBar(
    brandId: String?,
    modifier: Modifier = Modifier
) {
    ImasLeadBar(brandId = brandId, modifier = modifier)
}
