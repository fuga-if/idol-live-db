package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

// =============================================================================
// 日付の印 (iOS `Calendar/ImasDateMark.swift` の移植)。
//
// 月の格子の日の枠・週の日付の頭に置く、当日/選択日の丸い印。
// 当日 = 墨で塗った丸、選択日 (当日以外) = 墨の線の丸、どちらでもなければ何も出さない。
// 日の数字は呼び出し側がこの上に重ねる (当日は `DS.onSys`)。
// =============================================================================

/** 当日・選択日の丸い印 (iOS `ImasDateMark`)。 */
@Composable
fun ImasDateMark(isToday: Boolean, isSelected: Boolean, modifier: Modifier = Modifier, size: Dp = 26.dp) {
    Box(
        modifier
            .size(size)
            .then(
                when {
                    isToday -> Modifier.background(DS.sys, CircleShape)
                    isSelected -> Modifier.border(1.5.dp, DS.sys, CircleShape)
                    else -> Modifier
                }
            )
    )
}
