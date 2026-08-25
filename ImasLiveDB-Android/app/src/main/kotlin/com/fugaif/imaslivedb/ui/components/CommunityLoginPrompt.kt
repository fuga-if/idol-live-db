package com.fugaif.imaslivedb.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.launch

/**
 * 未ログインのまま投稿/編集導線を押した時に出すログイン誘導。
 * iOS `LoginToEditSheet` (DetailSheet / IdolDetailView / UnitDetailView が
 * `startCommunityEdit` の promptLogin で開くもの) にあたる。
 *
 * Android では既に「最近の編集」画面が AlertDialog + Google ログインの形を採っているので、
 * 同じ見た目に揃える (画面ごとに誘導の出方が変わると迷う)。
 *
 * 表示するかどうかは呼び出し側が決めない。必ず `AuthState.startCommunityEdit` の
 * promptLogin コールバックから立てること (未ログイン / BAN の優先順はコアが持っている)。
 */
@Composable
fun CommunityLoginPromptDialog(
    message: String = "タグ・コーレス・投票にはログインが必要です。",
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("ログインが必要です") },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                // signIn はアカウント選択シートを出すため Activity context が要る
                // (AppModule が握る application context ではなく LocalContext を渡す)。
                scope.launch { AppModule.from(context).authService.signIn(context) }
            }) { Text("Googleでログイン") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } }
    )
}
