package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.image.GalleryKind
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand

// =============================================================================
// ユニットのアバターと名札 (docs/DESIGN_SYSTEM.md §10.3・§6.6 相当)。iOS `Idols/ImasUnitAvatar.swift` の移植。
//
// ImasUnitAvatar   ユニットの円形アイコン。取り込んだ画像があれば画像、無ければ所属ブランドの色
//                  (読めない間だけブランドの id 由来の安定色) + 人の集まりの記号。
// ImasUnitCell     ユニットの名札 (格子の 1 つ)。`ImasIdolCell` のユニット版。上の帯がブランド色。
// =============================================================================

/** ユニットの色。ブランドの色が読めればそれ、読めない間はブランドの id から決めた安定色。 */
@Composable
private fun unitTheme(unit: ImasUnit): ImasTheme =
    if (BrandColors.hex(unit.brandId) != null) imasThemeForBrand(null, unit.brandId)
    else ImasTheme.forCategoryKey(unit.brandId, LocalImasColors.current.dark)

/**
 * ユニットの円形アイコン (iOS `ImasUnitAvatar`)。取り込んだ画像があれば画像 (ロゴは横長が多いので
 * 切らずに収める)、無ければブランドの色の地 + 人の集まりの記号。
 */
@Composable
fun ImasUnitAvatar(unit: ImasUnit, modifier: Modifier = Modifier, size: Dp = 36.dp) {
    val t = unitTheme(unit)
    val image = rememberCustomImage(unit.id, GalleryKind.UNIT)
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(t.tint)
            .border(1.5.dp, t.ring, CircleShape)
            .semantics { contentDescription = unit.displayName },
        contentAlignment = Alignment.Center
    ) {
        if (image != null) {
            SubcomposeAsyncImage(
                model = image,
                contentDescription = null,
                // ユニットのアイコンは横長のロゴが多い (SideM 等)。切ると何のユニットか分からなくなるので収める。
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(size * 0.04f),
                error = { UnitFallback(t, size) }
            )
        } else {
            UnitFallback(t, size)
        }
    }
}

@Composable
private fun UnitFallback(t: ImasTheme, size: Dp) {
    Box(Modifier.fillMaxSize().background(t.tint), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.Groups, contentDescription = null, tint = t.accent, modifier = Modifier.size(size * 0.5f))
    }
}

/**
 * ユニットの名札 (iOS `ImasUnitCell`)。`ImasIdolCell` のユニット版。上の帯がブランド色、その下にアイコンと名前。
 * 選ぶ格子 (ピッカー) では枠が点き、右上に選択の印。
 *
 * @param metric 名札の下段に添える値 (「タグ 3 個一致」等)。null なら出さない。
 */
@Composable
fun ImasUnitCell(unit: ImasUnit, modifier: Modifier = Modifier, metric: String? = null, isSelected: Boolean? = null) {
    val t = unitTheme(unit)
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier
            .imasSurface(shape)
            .clip(shape)
            .then(if (isSelected == true) Modifier.border(2.dp, t.accent, shape) else Modifier)
            .semantics(mergeDescendants = true) {
                contentDescription = listOfNotNull(unit.displayName, metric).joinToString("、")
                if (isSelected != null) selected = isSelected
            }
    ) {
        Column(Modifier.fillMaxWidth()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(5.dp)
                    .background(t.accent)
            )
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 6.dp, end = 6.dp, top = 7.dp, bottom = 9.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                ImasUnitAvatar(unit, size = 52.dp)
                ImasFitText(unit.displayName, style = ImasType.heading(12.5.sp, FontWeight.ExtraBold), color = DS.ink, minScale = 0.6f)
                if (metric != null) {
                    ImasFitText(metric, style = ImasType.mono(10.5.sp, FontWeight.SemiBold), color = DS.ink3, minScale = 0.8f)
                }
            }
        }
        if (isSelected != null) {
            ImasSelectionMark(
                isSelected = isSelected,
                brand = unit.brandId,
                size = 18.dp,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 9.dp, end = 5.dp)
            )
        }
    }
}
