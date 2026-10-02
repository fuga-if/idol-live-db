package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.ScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent

/**
 * タブを替えたとき、前のタブのスクロール位置のまま次のタブの途中が出ないようにする (iOS `imasTracksScrolledPast`)。
 * タブの見出しが上へ流れていれば、見出しまで戻す (流れていなければ動かさない)。
 *
 * 返す Modifier をタブの見出しに付ける。見出しはスクロールする Column の直下に置くこと (位置を親から測る)。
 */
@Composable
fun imasResetScrollOnTabChange(scroll: ScrollState, tab: Any): Modifier {
    var tabsY by remember { mutableIntStateOf(0) }
    LaunchedEffect(tab) {
        if (scroll.value > tabsY) scroll.scrollTo(tabsY)
    }
    return Modifier.onGloballyPositioned { tabsY = it.positionInParent().y.toInt() }
}
