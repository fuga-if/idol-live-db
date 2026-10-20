package com.fugaif.imaslivedb.ui.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceDialog
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability
import com.google.android.play.core.ktx.requestAppUpdateInfo

/**
 * Google Play に新しい版が出ていたら起動時にお知らせする (iOS `UpdateCheckService` と同じ役目)。
 * 古い版のまま使い続けて、直した不具合で落ち続ける人を減らすため。
 * 「後で」を押した版は二度と出さない。Play から入れていない端末 (開発機) では何も起きない。
 */
@Composable
fun UpdateAvailableAlert() {
    val context = LocalContext.current
    var availableVersionCode by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(Unit) {
        val info = runCatching { AppUpdateManagerFactory.create(context).requestAppUpdateInfo() }.getOrNull()
            ?: return@LaunchedEffect
        if (info.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE) return@LaunchedEffect
        val code = info.availableVersionCode()
        if (prefs(context).getInt(KEY_DISMISSED, -1) != code) availableVersionCode = code
    }

    val code = availableVersionCode ?: return
    val dismiss = {
        prefs(context).edit().putInt(KEY_DISMISSED, code).apply()
        availableVersionCode = null
    }
    ImasChoiceDialog(
        title = "新しいバージョンがあります",
        isPresented = true,
        options = listOf("update" to "更新"),
        onPick = { openStore(context) },
        onDismiss = dismiss,
        message = "新しいバージョンが Google Play で公開されています。",
        dismissTitle = "後で",
    )
}

private const val PREFS_NAME = "update_notice"
private const val KEY_DISMISSED = "dismissed_version_code"

private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

private fun openStore(context: Context) {
    val id = context.packageName
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id")))
    }.onFailure {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$id")))
        }
    }
}
