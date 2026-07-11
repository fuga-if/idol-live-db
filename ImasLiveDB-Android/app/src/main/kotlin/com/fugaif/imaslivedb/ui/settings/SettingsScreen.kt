package com.fugaif.imaslivedb.ui.settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.material3.Checkbox
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
import com.fugaif.imaslivedb.data.backup.BackupFormatException
import com.fugaif.imaslivedb.data.backup.BackupImportResult
import com.fugaif.imaslivedb.data.backup.BackupTransferException
import com.fugaif.imaslivedb.data.backup.TransferCodeResult
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

            // バックアップ
            item {
                SettingsSectionTitle("バックアップ")
                BackupSection(viewModel)
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
                SettingsNavRow("開発をサポートする") {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://ko-fi.com/fugaapp")))
                }
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

/**
 * 引き継ぎコード (サーバー経由) + ファイルエクスポート/インポート (SAF) の両方でお気に入り/担当/
 * 投票履歴をバックアップ/復元する。iOS `MyPageView.backupSection` の Android 移植。
 * 復元は常に非破壊マージ (ローカルの既存データを上書き・削除しない)。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BackupSection(viewModel: SettingsViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var restoreDeviceId by remember { mutableStateOf(false) }

    var isCreatingCode by remember { mutableStateOf(false) }
    var transferCodeResult by remember { mutableStateOf<TransferCodeResult?>(null) }
    var transferError by remember { mutableStateOf<String?>(null) }

    var codeInput by remember { mutableStateOf("") }
    var isRestoringCode by remember { mutableStateOf(false) }

    var isExporting by remember { mutableStateOf(false) }
    var isImportingFile by remember { mutableStateOf(false) }

    var importResult by remember { mutableStateOf<BackupImportResult?>(null) }
    var importError by remember { mutableStateOf<String?>(null) }

    fun handleImportFailure(e: Exception) {
        importError = when (e) {
            is BackupFormatException -> e.message
            is BackupTransferException -> e.message
            else -> "読み込みに失敗しました"
        } ?: "読み込みに失敗しました"
    }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            isExporting = true
            try {
                val json = viewModel.exportBackupJson()
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use {
                        it.write(json.toByteArray(Charsets.UTF_8))
                    }
                }
            } catch (e: Exception) {
                importError = "書き出しに失敗しました"
            } finally {
                isExporting = false
            }
        }
    }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            isImportingFile = true
            try {
                val json = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                } ?: throw BackupFormatException("ファイルを読み込めませんでした")
                importResult = viewModel.importBackup(json, restoreDeviceId)
            } catch (e: Exception) {
                handleImportFailure(e)
            } finally {
                isImportingFile = false
            }
        }
    }

    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(
            "機種変更やアプリの再インストール時に、お気に入り・担当・投票履歴を引き継げます",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        // 引き継ぎコード発行
        Button(
            onClick = {
                scope.launch {
                    isCreatingCode = true
                    transferError = null
                    try {
                        transferCodeResult = viewModel.createTransferCode()
                    } catch (e: BackupTransferException) {
                        transferError = e.message
                    } catch (e: Exception) {
                        transferError = "発行に失敗しました"
                    } finally {
                        isCreatingCode = false
                    }
                }
            },
            enabled = !isCreatingCode,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp)
        ) { Text(if (isCreatingCode) "発行中..." else "引き継ぎコードを発行する") }

        transferCodeResult?.let { result ->
            val clipboardManager = remember(context) {
                context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
                    .combinedClickable(
                        onClick = {},
                        onLongClick = {
                            clipboardManager.setPrimaryClip(ClipData.newPlainText("transfer_code", result.code))
                        }
                    )
            ) {
                Text(
                    result.code,
                    style = MaterialTheme.typography.headlineMedium,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                Text(
                    "長押しでコピー・24時間有効・1回のみ使用可能です",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }

        // 引き継ぎコードで復元
        OutlinedTextField(
            value = codeInput,
            onValueChange = { codeInput = it.uppercase() },
            singleLine = true,
            label = { Text("引き継ぎコード") },
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp)
        )
        Button(
            onClick = {
                scope.launch {
                    isRestoringCode = true
                    try {
                        importResult = viewModel.restoreFromTransferCode(codeInput.trim(), restoreDeviceId)
                        codeInput = ""
                    } catch (e: Exception) {
                        handleImportFailure(e)
                    } finally {
                        isRestoringCode = false
                    }
                }
            },
            enabled = !isRestoringCode && codeInput.isNotBlank(),
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
        ) { Text(if (isRestoringCode) "復元中..." else "引き継ぎコードで復元する") }

        HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

        // ファイルエクスポート/インポート
        OutlinedButton(
            onClick = { exportLauncher.launch("imas-live-backup.json") },
            enabled = !isExporting,
            modifier = Modifier.fillMaxWidth()
        ) { Text(if (isExporting) "書き出し中..." else "ファイルに保存する") }
        OutlinedButton(
            onClick = { importLauncher.launch(arrayOf("application/json", "text/plain", "*/*")) },
            enabled = !isImportingFile,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
        ) { Text(if (isImportingFile) "読み込み中..." else "ファイルから復元する") }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp)
        ) {
            Checkbox(checked = restoreDeviceId, onCheckedChange = { restoreDeviceId = it })
            Text(
                "復元時に端末IDも引き継ぐ (上級者向け・通常はオフ)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }

    if (transferError != null) {
        AlertDialog(
            onDismissRequest = { transferError = null },
            title = { Text("発行に失敗しました") },
            text = { Text(transferError ?: "") },
            confirmButton = { TextButton(onClick = { transferError = null }) { Text("OK") } }
        )
    }

    if (importResult != null) {
        AlertDialog(
            onDismissRequest = { importResult = null },
            title = { Text("復元が完了しました") },
            text = {
                val r = importResult!!
                Column {
                    Text("追加されたマーク: ${r.addedMarks}件")
                    Text("追加された投票履歴: ${r.addedVotes}件")
                    Text("追加されたマイタグ: ${r.addedPersonalTags}件")
                    if (r.skippedMarks > 0) Text("一部のデータの形式が読み取れず、${r.skippedMarks}件をスキップしました")
                    if (r.deviceIdRestored) Text("端末IDを引き継ぎました")
                }
            },
            confirmButton = { TextButton(onClick = { importResult = null }) { Text("OK") } }
        )
    }

    if (importError != null) {
        AlertDialog(
            onDismissRequest = { importError = null },
            title = { Text("復元に失敗しました") },
            text = { Text(importError ?: "") },
            confirmButton = { TextButton(onClick = { importError = null }) { Text("OK") } }
        )
    }
}
