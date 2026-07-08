package com.fugaif.imaslivedb.ui.settings

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

private enum class SettingsInfoScreen { PRIVACY, TERMS, SUPPORT }

private const val GITHUB_ISSUE_URL = "https://github.com/fuga-if/imas-live-privacy/issues/new"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    var infoScreen by remember { mutableStateOf<SettingsInfoScreen?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("設定") })
        }
    ) { innerPadding ->
        if (state.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // アカウント (投票に必要)
            item {
                SettingsSectionTitle("アカウント")
                AccountSection()
                HorizontalDivider()
            }

            // フィルタ設定
            item {
                SettingsSectionTitle("フィルタ設定")
                DefaultBrandPicker(
                    brands = state.brands,
                    selectedBrandId = state.defaultBrandId,
                    onBrandSelected = { viewModel.setDefaultBrand(it) }
                )
                HorizontalDivider()
            }

            // データ
            item {
                SettingsSectionTitle("データ")
                SettingsInfoRow("スキーマバージョン", state.schemaVersion)
                SettingsInfoRow("データバージョン", state.dataVersion)
                HorizontalDivider()
            }

            // データ統計
            state.databaseStats?.let { stats ->
                item {
                    SettingsSectionTitle("データ統計")
                    SettingsInfoRow("楽曲数", "${stats.songCount}曲")
                    SettingsInfoRow("アイドル数", "${stats.idolCount}人")
                    SettingsInfoRow("イベント数", "${stats.eventCount}件")
                    SettingsInfoRow("公演数", "${stats.showCount}公演")
                    HorizontalDivider()
                }
            }

            // クレジット
            item {
                SettingsSectionTitle("クレジット")
                CreditText("本アプリは株式会社バンダイナムコエンターテインメント様とは一切関係のない非公式ファンメイドアプリです。")
                CreditText("アイドルのプロフィール(CV/カラー等): im@sparql (https://sparql.crssnky.xyz/imas/)")
                CreditText("楽曲・ライブ等のデータ参照元: アイマスDB (https://imas-db.jp/)")
                CreditText("楽曲・ライブセトリのデータ参照元: music765plus (https://music765plus.com/)")
                CreditText("アイドルのイメージカラー: imas-palette (https://github.com/arrow2nd/imas-palette)")
                CreditText("※各情報源のデータは独自に集計・整形して利用しています")
                val version = try {
                    context.packageManager.getPackageInfo(context.packageName, 0).versionName
                } catch (_: PackageManager.NameNotFoundException) {
                    null
                }
                version?.let { SettingsInfoRow("アプリバージョン", it) }
                HorizontalDivider()
            }

            // アプリ情報
            item {
                SettingsSectionTitle("アプリ情報")
                SettingsNavRow("プライバシーポリシー") { infoScreen = SettingsInfoScreen.PRIVACY }
                SettingsNavRow("利用規約") { infoScreen = SettingsInfoScreen.TERMS }
                SettingsNavRow("サポート") { infoScreen = SettingsInfoScreen.SUPPORT }
                SettingsNavRow("アプリを評価する") {
                    val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${context.packageName}")).apply {
                        setPackage("com.android.vending")
                    }
                    try {
                        context.startActivity(marketIntent)
                    } catch (_: Exception) {
                        context.startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("https://play.google.com/store/apps/details?id=${context.packageName}")
                            )
                        )
                    }
                }
                HorizontalDivider()
            }
        }
    }

    when (infoScreen) {
        SettingsInfoScreen.PRIVACY -> Dialog(
            onDismissRequest = { infoScreen = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) { PrivacyPolicyScreen(onBack = { infoScreen = null }) }

        SettingsInfoScreen.TERMS -> Dialog(
            onDismissRequest = { infoScreen = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) { TermsOfServiceScreen(onBack = { infoScreen = null }) }

        SettingsInfoScreen.SUPPORT -> Dialog(
            onDismissRequest = { infoScreen = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SupportScreen(
                onBack = { infoScreen = null },
                onOpenGithubIssue = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(GITHUB_ISSUE_URL)))
                }
            )
        }

        null -> {}
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DefaultBrandPicker(
    brands: List<com.fugaif.imaslivedb.data.model.Brand>,
    selectedBrandId: String,
    onBrandSelected: (String?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val allItems = listOf(null to "すべて") + brands.map { it.id to it.shortName }
    val selectedLabel = brands.find { it.id == selectedBrandId }?.shortName ?: "すべて"

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text("デフォルトブランド") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            allItems.forEach { (id, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        onBrandSelected(id)
                        expanded = false
                    }
                )
            }
        }
    }
}

@Composable
private fun SettingsNavRow(label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun SettingsSectionTitle(title: String) {
    com.fugaif.imaslivedb.ui.components.ImasSectionHeader(title = title, tight = true)
}

/**
 * 投票 (お題) に必要なログイン状態の表示・切替 + 表示名変更・アカウント削除。
 * iOS `MyPageView.accountSection` (AuthService = Sign in with Apple) の Android 移植。
 */
@Composable
private fun AccountSection() {
    val context = LocalContext.current
    val authService = remember { AppModule.from(context).authService }
    val authState by authService.state.collectAsState()
    val scope = rememberCoroutineScope()

    var showEditName by remember { mutableStateOf(false) }
    var editingName by remember { mutableStateOf("") }
    var isSavingName by remember { mutableStateOf(false) }
    var nameError by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var isDeleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }

    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (authState.isSignedIn) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    authState.displayName?.takeIf { it.isNotBlank() } ?: "ログイン済み",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f, fill = false)
                )
                IconButton(onClick = {
                    editingName = authState.displayName ?: ""
                    showEditName = true
                }) {
                    Icon(Icons.Filled.Edit, contentDescription = "表示名を変更", modifier = Modifier.size(18.dp))
                }
            }
            OutlinedButton(
                onClick = { authService.signOut() },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
            ) { Text("ログアウト") }
            Button(
                onClick = { showDeleteConfirm = true },
                enabled = !isDeleting,
                colors = ButtonDefaults.buttonColors(containerColor = DS.danger),
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
            ) { Text(if (isDeleting) "削除中..." else "アカウントを削除") }
        } else {
            Text(
                "投票 (お題) にはログインが必要です",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Button(
                onClick = { scope.launch { authService.signIn(context) } },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
            ) { Text("Googleでログイン") }
        }
    }

    if (showEditName) {
        AlertDialog(
            onDismissRequest = { if (!isSavingName) showEditName = false },
            title = { Text("表示名を変更") },
            text = {
                Column {
                    Text(
                        "コミュニティ投稿で表示される名前です (40文字以内)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = editingName,
                        onValueChange = { if (it.length <= 40) editingName = it },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = editingName.trim().isNotEmpty() && !isSavingName,
                    onClick = {
                        scope.launch {
                            isSavingName = true
                            val result = authService.updateDisplayName(editingName.trim())
                            isSavingName = false
                            result.onSuccess { showEditName = false }
                                .onFailure { nameError = "表示名の保存に失敗しました" }
                        }
                    }
                ) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = { showEditName = false }, enabled = !isSavingName) { Text("キャンセル") }
            }
        )
    }

    if (nameError != null) {
        AlertDialog(
            onDismissRequest = { nameError = null },
            title = { Text("表示名の保存に失敗") },
            text = { Text(nameError ?: "") },
            confirmButton = { TextButton(onClick = { nameError = null }) { Text("OK") } }
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("アカウントを削除しますか?") },
            text = { Text("サーバー上のあなたの編集・Good・投票・ユーザー情報がすべて削除され、サインアウトされます。この操作は取り消せません。") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        isDeleting = true
                        val result = authService.deleteAccount()
                        isDeleting = false
                        result.onFailure { deleteError = "削除に失敗しました" }
                    }
                }) { Text("削除する", color = DS.danger) }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("キャンセル") } }
        )
    }

    if (deleteError != null) {
        AlertDialog(
            onDismissRequest = { deleteError = null },
            title = { Text("削除に失敗しました") },
            text = { Text(deleteError ?: "") },
            confirmButton = { TextButton(onClick = { deleteError = null }) { Text("OK") } }
        )
    }
}

@Composable
private fun SettingsInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun CreditText(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}
