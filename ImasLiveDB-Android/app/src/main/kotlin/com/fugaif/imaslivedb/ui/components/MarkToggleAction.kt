package com.fugaif.imaslivedb.ui.components

import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.launch

/**
 * 担当/お気に入り等の ON/OFF トグルを TopAppBar のアクションに置く共通ボタン。
 * 端末ローカルの user_marks を読み書きする。
 */
@Composable
fun MarkToggleAction(
    entityType: String,
    entityId: String,
    kind: String,
    activeIcon: ImageVector,
    inactiveIcon: ImageVector,
    activeTint: Color,
    contentDescription: String
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var on by remember(entityId, kind) { mutableStateOf(false) }

    LaunchedEffect(entityId, kind) {
        on = AppModule.from(ctx).userMarkRepository.isOn(entityType, entityId, kind)
    }
    IconButton(onClick = {
        scope.launch {
            on = AppModule.from(ctx).userMarkRepository.toggle(entityType, entityId, kind)
        }
    }) {
        Icon(
            imageVector = if (on) activeIcon else inactiveIcon,
            contentDescription = contentDescription,
            tint = if (on) activeTint else LocalContentColor.current
        )
    }
}
