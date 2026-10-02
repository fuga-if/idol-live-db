package com.fugaif.imaslivedb.ui.navigation

import androidx.compose.runtime.staticCompositionLocalOf
import uniffi.imas_core.AppDestination

/**
 * タブバーに載っていない行き先 (タブから外した主な画面) を開く。
 * プロデュースの「そのほか」から呼ぶ。ルート (AppNavigation) が中身を差し込む。
 */
val LocalOpenDestination = staticCompositionLocalOf<(AppDestination) -> Unit> { {} }
