package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.brandColor

/**
 * 4dp wide vertical color bar shown at the left edge of event cards.
 * Mirrors iOS BrandColorBar.
 */
@Composable
fun BrandColorBar(
    brandId: String?,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .width(4.dp)
            .height(40.dp)
            .clip(RoundedCornerShape(2.dp))
            .background(brandColor(brandId))
    )
}
