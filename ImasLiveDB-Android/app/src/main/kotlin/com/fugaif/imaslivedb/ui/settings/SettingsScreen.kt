package com.fugaif.imaslivedb.ui.settings

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.QuestionAnswer
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material.icons.filled.Vaccines
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.notification.NotificationCategory
import com.fugaif.imaslivedb.data.notification.NotificationPrefs
import com.fugaif.imaslivedb.data.notification.NotificationScheduler
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRowKind
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTile
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMenuRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPass
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.MasteryPalette
import com.fugaif.imaslivedb.ui.theme.MasteryScale
import com.fugaif.imaslivedb.ui.theme.PerformerNamePref
import com.fugaif.imaslivedb.ui.theme.displayName
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.joined
import kotlinx.coroutines.launch
import uniffi.imas_core.InputField
import uniffi.imas_core.inputIsAcceptable
import uniffi.imas_core.inputLimitMax

private enum class SettingsInfoScreen { HELP, INBOX, PRIVACY, TERMS, SUPPORT, LICENSES }

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
            ImasLoadingState(modifier = Modifier.padding(innerPadding))
            return@Scaffold
        }

        ImasFormBackdrop(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                // アプリヘッダ (アイコン + バージョン)。最初に目に入る位置で「何のアプリの、
                // どのビルドか」が分かるようにしておく (不具合報告のときに聞き返さずに済む)。
                item { AppHeader() }

                // アカウント (投票に必要)
                item { ImasListSection("アカウント") { AccountSection() } }

                // フィルタ設定
                item {
                    ImasListSection("フィルタ設定") {
                        DefaultBrandPicker(
                            brands = state.brands,
                            selectedBrandId = state.defaultBrandId,
                            onBrandSelected = { viewModel.setDefaultBrand(it) }
                        )
                    }
                }

                // 表示 (文字サイズ・ライブ名の省略)
                item { ImasListSection("表示") { DisplaySettingsSection() } }

                // 習熟度の段階 (ラベルの好みは人によるので触れるようにする)
                item {
                    ImasListSection(
                        "習熟度",
                        footer = "下から順に積み上がります。段を減らすと、その段の曲は 1 つ下に移ります (記録は消えません)。" +
                            "どのラベルも 4 文字以内にしておくと一覧で切れません。"
                    ) { MasteryScaleSection() }
                }

                // 披露回収の対象
                item {
                    ImasListSection(
                        "披露回収",
                        footer = "回収はリアルライブ (ライブ/フェス) の現地参加のみが対象です。" +
                            "配信でしか観られない方は、配信参加も回収に含められます。"
                    ) { CollectionSettingsSection() }
                }

                // テーマ (担当カラー)
                item {
                    ImasListSection(
                        "テーマ",
                        footer = "ON にすると、選んだ担当のイメージカラーがアプリ全体のアクセントカラーになります。"
                    ) { OshiThemeSection(viewModel, state) }
                }

                // 通知
                item { ImasListSection("通知") { NotificationSection() } }

                // データ
                item {
                    ImasListSection("データ") {
                        ImasValueRow(key = "スキーマバージョン", value = state.schemaVersion)
                        ImasValueRow(key = "データバージョン", value = state.dataVersion)
                        DataSyncSection()
                    }
                }

                // バックアップ
                item {
                    ImasListSection(
                        "バックアップ",
                        footer = "機種変更やアプリの再インストール時に、お気に入り・担当・投票履歴を引き継げます"
                    ) { BackupSection() }
                }

                // キャラクター画像 (端末ローカル)
                item {
                    ImasListSection(
                        "キャラクター画像",
                        footer = "「名前 → 画像URL」の JSON を指定すると、アイコン画像をまとめて取り込めます。" +
                            "画像はこの端末の中だけに保存され、サーバーには送信されません。"
                    ) { ImageImportSection() }
                }

                // データ統計
                state.databaseStats?.let { stats ->
                    item {
                        ImasListSection("データ統計") {
                            ImasValueRow(key = "楽曲数", value = "${stats.songCount}曲")
                            ImasValueRow(key = "アイドル数", value = "${stats.idolCount}人")
                            ImasValueRow(key = "イベント数", value = "${stats.eventCount}件")
                            ImasValueRow(key = "公演数", value = "${stats.showCount}公演")
                        }
                    }
                }

                // クレジット
                item {
                    val version = try {
                        context.packageManager.getPackageInfo(context.packageName, 0).versionName
                    } catch (_: PackageManager.NameNotFoundException) {
                        null
                    }
                    ImasListSection("クレジット") {
                        Column(
                            Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
                            verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
                        ) {
                            CreditText("本アプリは株式会社バンダイナムコエンターテインメント様とは一切関係のない非公式ファンメイドアプリです。")
                            CreditText("アイドルのプロフィール(CV/カラー等): im@sparql (https://sparql.crssnky.xyz/imas/)")
                            CreditText("楽曲・ライブ等のデータ参照元: アイマスDB (https://imas-db.jp/)")
                            CreditText("楽曲・ライブセトリのデータ参照元: music765plus (https://music765plus.com/)")
                            CreditText("アイドルのイメージカラー: imas-palette (https://github.com/arrow2nd/imas-palette)")
                            CreditText("※各情報源のデータは独自に集計・整形して利用しています")
                        }
                        version?.let { ImasValueRow(key = "アプリバージョン", value = it) }
                    }
                }

                // アプリ情報
                item {
                    ImasListSection("アプリ情報") {
                        ImasNavRow(title = "使い方") { infoScreen = SettingsInfoScreen.HELP }
                        ImasNavRow(title = "お知らせ") { infoScreen = SettingsInfoScreen.INBOX }
                        ImasNavRow(title = "プライバシーポリシー") { infoScreen = SettingsInfoScreen.PRIVACY }
                        ImasNavRow(title = "利用規約") { infoScreen = SettingsInfoScreen.TERMS }
                        ImasNavRow(title = "サポート") { infoScreen = SettingsInfoScreen.SUPPORT }
                        ImasNavRow(title = "オープンソースライセンス") { infoScreen = SettingsInfoScreen.LICENSES }
                        ImasNavRow(title = "開発をサポートする", icon = Icons.Filled.Favorite, iconTone = ImasIconTileTone.NEUTRAL) {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://ko-fi.com/fugaapp")))
                        }
                        ImasNavRow(title = "アプリを評価する", icon = Icons.Filled.Star, iconTone = ImasIconTileTone.NEUTRAL) {
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
                    }
                }

                // 開発者
                item { ImasListSection("開発者", footer = "非公式のファンメイドアプリです。データの誤りや要望は GitHub Issue からお知らせください。") { DeveloperSection() } }
            }
        }
    }

    when (infoScreen) {
        SettingsInfoScreen.HELP -> Dialog(
            onDismissRequest = { infoScreen = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) { HelpScreen(onBack = { infoScreen = null }) }

        SettingsInfoScreen.INBOX -> Dialog(
            onDismissRequest = { infoScreen = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) { InboxScreen(onBack = { infoScreen = null }) }

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

        SettingsInfoScreen.LICENSES -> Dialog(
            onDismissRequest = { infoScreen = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) { OssLicensesScreen(onBack = { infoScreen = null }) }

        null -> {}
    }
}

@Composable
private fun DefaultBrandPicker(
    brands: List<com.fugaif.imaslivedb.data.model.Brand>,
    selectedBrandId: String,
    onBrandSelected: (String?) -> Unit
) {
    val selection = selectedBrandId.ifEmpty { null }
    ImasMenuRow(
        title = "デフォルトブランド",
        icon = Icons.Filled.GridView,
        options = listOf(null) + brands.map { it.id },
        selection = selection,
        onSelect = onBrandSelected,
        label = { id -> id?.let { bid -> brands.firstOrNull { it.id == bid }?.shortName ?: bid } ?: "すべて" }
    )
}

/**
 * データ同期の状態表示と手動実行 (iOS `MyPageView.dataSyncSection` と対)。
 *
 * 起動時の同期は増分で、増分では**サーバー側で消えたレコードを落とせない**
 * (孤児掃除はフル実行でしか走らない)。表示がおかしくなったときにユーザー自身が
 * 取り直せる口が要る。FAQ の「同期に失敗する」は以前からこの導線を案内していたが、
 * Android には実物が無く行き止まりになっていた。
 */
@Composable
private fun DataSyncSection() {
    val context = LocalContext.current
    val engine = remember { AppModule.from(context).syncEngine }
    val state by engine.state.collectAsState()
    val syncing = state is CloudKitSyncEngine.SyncState.Syncing

    ImasRow(
        title = when (val s = state) {
            is CloudKitSyncEngine.SyncState.Idle -> "待機中"
            is CloudKitSyncEngine.SyncState.Syncing -> "同期中 (${s.step}/${s.total}) ${s.label}"
            is CloudKitSyncEngine.SyncState.Completed -> "完了 (${s.fetched}件)"
            is CloudKitSyncEngine.SyncState.Error -> "失敗: ${s.message}"
        },
        titleRole = ImasTextRole.ROW_LABEL,
        trailing = if (syncing) {
            ImasRowTrailing.Custom { CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = DS.sys) }
        } else ImasRowTrailing.None
    )
    ImasActionRow(title = "差分更新", icon = Icons.Filled.CloudSync, isLoading = syncing, onClick = { engine.requestSync() })
    ImasActionRow(title = "全データ同期", icon = Icons.Filled.CloudSync, isLoading = syncing, onClick = { engine.requestFullSync() })
}

/**
 * 投票 (お題) に必要なログイン状態の表示・切替 + 表示名変更・アカウント削除。
 * iOS `MyPageView.accountSection` (AuthService = Sign in with Apple) の Android 移植。
 */
@Composable
private fun AccountSection(viewModel: AccountViewModel = viewModel()) {
    val context = LocalContext.current
    val authState by viewModel.authState.collectAsState()
    val state by viewModel.uiState.collectAsState()
    // サインインは Credential Manager がこの画面の上にアカウント選択を出すので、画面のスコープで行う。
    val scope = rememberCoroutineScope()
    val authService = remember { AppModule.from(context).authService }

    var showDeleteConfirm by remember { mutableStateOf(false) }

    if (authState.isSignedIn) {
        Box(Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
            ImasPass(
                leftImprint = "ACCOUNT",
                rightImprint = "ログイン中",
                title = authState.displayName?.takeIf { it.isNotBlank() } ?: "ログイン済み",
                subtitle = "コミュニティで表示される名前"
            ) {
                androidx.compose.material3.IconButton(onClick = viewModel::startEditingName) {
                    androidx.compose.material3.Icon(Icons.Filled.Edit, contentDescription = "表示名を変更")
                }
            }
        }
        ImasActionRow(title = "ログアウト", kind = ImasActionRowKind.DESTRUCTIVE, onClick = viewModel::signOut)
        ImasActionRow(
            title = if (state.isDeleting) "削除中..." else "アカウントを削除",
            kind = ImasActionRowKind.DESTRUCTIVE,
            isLoading = state.isDeleting,
            onClick = { showDeleteConfirm = true }
        )
    } else {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapLoose),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
        ) {
            Text(
                "投票 (お題) にはログインが必要です",
                style = ImasTextRole.NOTE.style,
                color = ImasTextRole.NOTE.color,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            ImasButton(
                title = "Googleでログイン",
                onClick = { scope.launch { authService.signIn(context) } },
                role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.LARGE,
                fillsWidth = true
            )
        }
    }

    state.editingName?.let { editingName ->
        AlertDialog(
            onDismissRequest = viewModel::cancelEditingName,
            title = { Text("表示名を変更") },
            text = {
                Column {
                    Text(
                        "コミュニティ投稿で表示される名前です (${inputLimitMax(InputField.DISPLAY_NAME)}文字以内)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = editingName,
                        onValueChange = viewModel::setEditingName,
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(top = DS.Space.gap)
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = inputIsAcceptable(InputField.DISPLAY_NAME, editingName) && !state.isSavingName,
                    onClick = viewModel::saveName
                ) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = viewModel::cancelEditingName, enabled = !state.isSavingName) { Text("キャンセル") }
            }
        )
    }

    state.nameError?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::dismissNameError,
            title = { Text("表示名の保存に失敗") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = viewModel::dismissNameError) { Text("OK") } }
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
                    viewModel.deleteAccount()
                }) { Text("削除する", color = DS.danger) }
            },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("キャンセル") } }
        )
    }

    state.deleteError?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::dismissDeleteError,
            title = { Text("削除に失敗しました") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = viewModel::dismissDeleteError) { Text("OK") } }
        )
    }
}

// =============================================================================
// キャラクター画像の一括インポート (iOS MyPageView.imageImportSection と対)
// 取り込んだ画像は端末内 (filesDir) にだけ置く。サーバにも CloudKit にも送らない。
// =============================================================================

@Composable
private fun ImageImportSection(viewModel: ImageImportViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()

    var urlTarget by remember { mutableStateOf<ImageImportTarget?>(null) }
    var urlText by remember { mutableStateOf("") }
    var showClearConfirm by remember { mutableStateOf(false) }
    // SAF は起動時に保存先を決めるので、「どの型紙を書くか」は launch 前に控えておく。
    var templateTarget by remember { mutableStateOf(ImageImportTarget.IDOL) }

    val saveTemplateLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri != null) viewModel.saveTemplate(templateTarget, uri)
    }

    ImageImportTarget.entries.forEach { target ->
        ImasActionRow(
            title = "${target.label}画像をインポート",
            icon = Icons.Filled.PhotoLibrary,
            isLoading = state.isImporting,
            onClick = { urlTarget = target; urlText = "" }
        )
        ImasActionRow(
            title = "型紙",
            icon = Icons.Filled.FileDownload,
            onClick = {
                templateTarget = target
                saveTemplateLauncher.launch(target.templateFileName)
            }
        )
    }

    if (state.isImporting) {
        Box(Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
            androidx.compose.material3.LinearProgressIndicator(
                progress = { state.progress },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
    if (state.statusMessage.isNotEmpty()) {
        Box(Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight)) {
            Text(state.statusMessage, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
        }
    }
    // 失敗内訳は「名前が DB に無い」等ユーザーが型紙を直せる情報なので、件数だけでなく中身も出す。
    if (state.failures.isNotEmpty()) {
        Column(Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight)) {
            Text(
                "失敗内訳 (${state.failures.size} 件)",
                style = ImasType.text(12.sp, androidx.compose.ui.text.font.FontWeight.SemiBold),
                color = DS.warning
            )
            state.failures.take(MAX_SHOWN_FAILURES).forEach { failure ->
                Text("${failure.key}: ${failure.reason}", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
            }
            if (state.failures.size > MAX_SHOWN_FAILURES) {
                Text("ほか ${state.failures.size - MAX_SHOWN_FAILURES} 件", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
            }
        }
    }

    ImasActionRow(
        title = "カスタム画像をすべて削除",
        kind = ImasActionRowKind.DESTRUCTIVE,
        isLoading = state.isImporting,
        onClick = { showClearConfirm = true }
    )

    urlTarget?.let { target ->
        AlertDialog(
            onDismissRequest = { urlTarget = null },
            title = { Text("${target.label}画像の一括インポート") },
            text = {
                Column {
                    Text(
                        "{ \"名前\": \"画像URL\" } 形式の JSON を置いた URL を入力してください。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = urlText,
                        onValueChange = { urlText = it },
                        label = { Text("JSON の URL") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(top = DS.Space.gap)
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.import(target, urlText)
                        urlTarget = null
                    },
                    enabled = urlText.isNotBlank()
                ) { Text("インポート") }
            },
            dismissButton = { TextButton(onClick = { urlTarget = null }) { Text("キャンセル") } }
        )
    }

    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("カスタム画像をすべて削除") },
            text = { Text("取り込んだアイドル・ユニット・ブランドの画像をすべて消します。元に戻せません。") },
            confirmButton = {
                TextButton(onClick = {
                    showClearConfirm = false
                    viewModel.clearAll()
                }) { Text("削除", color = DS.danger) }
            },
            dismissButton = { TextButton(onClick = { showClearConfirm = false }) { Text("キャンセル") } }
        )
    }
}

/** 失敗内訳を設定画面に直接並べる上限 (これ以上は「ほか N 件」に畳む)。 */
private const val MAX_SHOWN_FAILURES = 20

@Composable
private fun CreditText(text: String) {
    Text(text = text, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
}

/**
 * 引き継ぎコード (サーバー経由) + ファイルエクスポート/インポート (SAF) の両方でお気に入り/担当/
 * 投票履歴をバックアップ/復元する。iOS `MyPageView.backupSection` の Android 移植。
 * 復元は常に非破壊マージ (ローカルの既存データを上書き・削除しない)。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BackupSection(viewModel: BackupViewModel = viewModel()) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()

    var restoreDeviceId by remember { mutableStateOf(false) }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri != null) viewModel.exportTo(uri)
    }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) viewModel.importFrom(uri, restoreDeviceId)
    }

    // 引き継ぎコード発行
    ImasActionRow(
        title = if (state.isCreatingCode) "発行中..." else "引き継ぎコードを発行する",
        icon = Icons.Filled.FileUpload,
        isLoading = state.isCreatingCode,
        onClick = { viewModel.createTransferCode() }
    )

    state.transferCode?.let { result ->
        val clipboardManager = remember(context) {
            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                .combinedClickable(
                    onClick = {},
                    onLongClick = {
                        clipboardManager.setPrimaryClip(ClipData.newPlainText("transfer_code", result.code))
                    }
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
        ) {
            Text(result.code, style = ImasType.heading(28.sp, androidx.compose.ui.text.font.FontWeight.Bold), color = DS.ink)
            Text(
                "長押しでコピー・24時間有効・1回のみ使用可能です",
                style = ImasTextRole.NOTE.style,
                color = ImasTextRole.NOTE.color,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
    }

    // 引き継ぎコードで復元
    Column(Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
        OutlinedTextField(
            value = state.codeInput,
            onValueChange = viewModel::setCodeInput,
            singleLine = true,
            label = { Text("引き継ぎコード") },
            modifier = Modifier.fillMaxWidth()
        )
        ImasButton(
            title = if (state.isRestoringCode) "復元中..." else "引き継ぎコードで復元する",
            onClick = { viewModel.restoreFromTransferCode(restoreDeviceId) },
            role = ImasButtonRole.SECONDARY,
            isLoading = state.isRestoringCode,
            enabled = !state.isRestoringCode && state.codeInput.isNotBlank(),
            fillsWidth = true,
            modifier = Modifier.padding(top = DS.Space.gap)
        )
    }

    // ファイルエクスポート/インポート
    ImasActionRow(
        title = if (state.isExporting) "書き出し中..." else "ファイルに保存する",
        icon = Icons.Filled.Backup,
        isLoading = state.isExporting,
        onClick = { exportLauncher.launch("imas-live-backup.json") }
    )
    ImasActionRow(
        title = if (state.isImportingFile) "読み込み中..." else "ファイルから復元する",
        icon = Icons.Filled.FileDownload,
        isLoading = state.isImportingFile,
        onClick = { importLauncher.launch(arrayOf("application/json", "text/plain", "*/*")) }
    )

    ImasToggleRow(
        title = "復元時に端末IDも引き継ぐ (上級者向け・通常はオフ)",
        isOn = restoreDeviceId,
        onCheckedChange = { restoreDeviceId = it }
    )

    state.transferError?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::dismissTransferError,
            title = { Text("発行に失敗しました") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = viewModel::dismissTransferError) { Text("OK") } }
        )
    }

    state.importSummary?.let { summary ->
        AlertDialog(
            onDismissRequest = viewModel::dismissImportResult,
            title = { Text("復元が完了しました") },
            text = { Text(summary) },
            confirmButton = { TextButton(onClick = viewModel::dismissImportResult) { Text("OK") } }
        )
    }

    state.importError?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::dismissImportError,
            title = { Text("復元に失敗しました") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = viewModel::dismissImportError) { Text("OK") } }
        )
    }
}

/**
 * 通知の許可状態と 4 種類のトグル。iOS `MyPageView.notificationSection` の移植。
 *
 * 保存キー (notif_oshi_birthday など) は iOS と同じ。トグルを触るたびに全再スケジュール
 * するのも iOS と同じで、差分更新はしない (組み立てが安いので、状態を持たない方が確実)。
 */
@Composable
private fun NotificationSection() {
    val context = LocalContext.current
    // 組み直しはアプリのスコープで行う (画面を離れても途中で止まらない)。
    val scope = remember { AppModule.from(context).appScope }
    val prefs = remember { NotificationPrefs(context) }

    var enabled by remember { mutableStateOf(NotificationScheduler.areNotificationsEnabled(context)) }
    var permissionDenied by remember { mutableStateOf(false) }

    // システムの通知設定で切られた/許可された場合、この画面に戻ってきた時点で表示を合わせる。
    // (アプリ内トグルだけ ON に見えて通知が来ない、という状態を作らないため)
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                enabled = NotificationScheduler.areNotificationsEnabled(context)
                if (enabled) permissionDenied = false
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        enabled = granted && NotificationScheduler.areNotificationsEnabled(context)
        permissionDenied = !enabled
        if (enabled) scope.launch { NotificationScheduler.rescheduleAll(context.applicationContext) }
    }

    if (!enabled) {
        ImasActionRow(
            title = "通知を許可する",
            icon = Icons.Filled.NotificationsActive,
            onClick = {
                // Android 13+ はランタイム権限のダイアログ。ただし 2 回拒否済みだと
                // ダイアログが出ずに即 denied で返るので、その場合は下の導線に切り替える。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    // 12 以下に POST_NOTIFICATIONS は無い。切られている = システム設定側なので直接飛ばす。
                    context.startActivity(appNotificationSettingsIntent(context))
                }
            }
        )
        if (permissionDenied) {
            Box(Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
                Text("通知が拒否されています。システムの通知設定から許可してください。", style = ImasTextRole.NOTE.style, color = DS.warning)
            }
            ImasNavRow(title = "システムの通知設定を開く") {
                context.startActivity(appNotificationSettingsIntent(context))
            }
        }
        return
    }

    NotificationToggleRow("担当アイドルの誕生日", prefs, NotificationCategory.OSHI_BIRTHDAY, scope)
    NotificationToggleRow("ライブ1週間前", prefs, NotificationCategory.LIVE_WEEK, scope)
    NotificationToggleRow("チケット締切・当落通知", prefs, NotificationCategory.TICKET, scope)
    NotificationToggleRow("月曜が近いことを知らせる (日曜 20:00)", prefs, NotificationCategory.MONDAY, scope)
    ImasNote("お気に入りまたは参加マークしたイベントにライブ前・チケット通知を送ります。")
}

@Composable
private fun NotificationToggleRow(
    label: String,
    prefs: NotificationPrefs,
    category: NotificationCategory,
    scope: kotlinx.coroutines.CoroutineScope
) {
    val context = LocalContext.current
    var checked by remember(category) { mutableStateOf(prefs.isEnabled(category)) }
    ImasToggleRow(
        title = label,
        isOn = checked,
        onCheckedChange = { value ->
            checked = value
            prefs.setEnabled(category, value)
            // 設定を変えたら即座に予定表を作り直す (iOS の onChange と同じ)。
            // OFF にしたときは、予定表を作れなくても予約を消す (OFF にした通知を鳴らさない)。
            val reason = if (value) {
                NotificationScheduler.RescheduleReason.REFRESH
            } else {
                NotificationScheduler.RescheduleReason.SETTING_TURNED_OFF
            }
            scope.launch { NotificationScheduler.rescheduleAll(context.applicationContext, reason) }
        }
    )
}

/** このアプリの通知設定画面。チャンネル単位の音量・重要度もここから触れる。 */
private fun appNotificationSettingsIntent(context: Context): Intent =
    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

// =============================================================================
// アプリヘッダ / 表示 / 披露回収 / テーマ / 開発者
// iOS `MyPageView` の generalSettingsSection・collectionSettingsSection・themeSection
// および About 節の移植。設定値の保存先は AppPreferences (iOS の @AppStorage と同じキー)。
// =============================================================================

/** アプリアイコン + 名前 + バージョン (ビルド番号つき)。 */
@Composable
private fun AppHeader() {
    val context = LocalContext.current
    val info = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
    }
    val versionName = info?.versionName ?: "-"
    // ビルド番号は不具合報告の突き合わせに要る。longVersionCode は API 28 から。
    val versionCode = info?.let {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) it.longVersionCode else @Suppress("DEPRECATION") it.versionCode.toLong()
    }

    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gapLoose),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
    ) {
        // アダプティブアイコン (XML) なので painterResource ではなく Coil で描く。
        AsyncImage(
            model = com.fugaif.imaslivedb.R.mipmap.ic_launcher,
            contentDescription = null,
            modifier = Modifier.size(56.dp).clip(RoundedCornerShape(DS.rArtwork(56.dp)))
        )
        Column {
            Text("アイドルライブDB", style = ImasTextRole.CARD_TITLE.style, color = ImasTextRole.CARD_TITLE.color)
            Text(
                if (versionCode != null) "バージョン $versionName (Build $versionCode)" else "バージョン $versionName",
                style = ImasTextRole.META.style,
                color = ImasTextRole.META.color
            )
        }
    }
}

/** 歌唱者の表示サンプル (実データの 1 人)。設定を切り替えた見え方をその場で見せる。 */
private val performerNameSample = PerformerRow(
    id = "sample",
    name = "下田麻美",
    idolColor = null,
    idolName = "双海亜美",
    idolId = null
)

/** 文字サイズ・歌唱者の名前・ライブ名の省略。どれも変更が即座にアプリ全体へ効く。 */
@Composable
private fun DisplaySettingsSection() {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Text("文字サイズ", style = ImasTextRole.ROW_LABEL.style, color = ImasTextRole.ROW_LABEL.color)
        ImasSegmented(
            labels = AppPreferences.textScaleLabels,
            // 保存値が選択肢に無い (将来値を足した/減らした) 場合は「中」に倒す。
            selection = AppPreferences.textScaleOptions.indexOf(AppPreferences.textScale)
                .takeIf { it >= 0 } ?: AppPreferences.textScaleOptions.indexOf(1.0f),
            onSelect = { AppPreferences.setTextScale(AppPreferences.textScaleOptions[it]) },
            modifier = Modifier.fillMaxWidth()
        )
        // プレビュー: この設定画面の文字自体も倍率が効くので、実データ風の文字で
        // 「一覧がどう見えるか」を確かめられるようにする。
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight), modifier = Modifier.padding(top = DS.Space.gapTight)) {
            Text("プレビュー", style = ImasTextRole.ROW_SUBTITLE.style, color = ImasTextRole.ROW_SUBTITLE.color)
            Text("Timeless Shooting Star", style = ImasTextRole.ROW_TITLE.style, color = ImasTextRole.ROW_TITLE.color)
            Text("ストレイライト ・ 全員", style = ImasTextRole.ROW_SUBTITLE.style, color = ImasTextRole.ROW_SUBTITLE.color)
        }
        Text("OS のフォントサイズ設定に掛け合わせた倍率です。", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
    }

    Column(
        Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Text("セトリの歌唱者", style = ImasTextRole.ROW_LABEL.style, color = ImasTextRole.ROW_LABEL.color)
        // 選択肢はコアが出す (順も文言もアプリ 1 本)。
        val options = PerformerNamePref.options
        ImasSegmented(
            labels = options.map { it.label },
            selection = options.indexOfFirst { it.raw == AppPreferences.performerNameRaw }
                .takeIf { it >= 0 } ?: 0,
            onSelect = { AppPreferences.setPerformerNameRaw(options[it].raw) },
            modifier = Modifier.fillMaxWidth()
        )
        // 設定値で見え方が変わるサンプル。声優ライブの 1 人分をそのまま出す。
        Text(
            performerNameSample.displayName(AppPreferences.performerName, isCharacterLive = false).joined(),
            style = ImasTextRole.META.style,
            color = ImasTextRole.META.color
        )
    }

    ImasToggleRow(
        title = "ライブ名を省略表示",
        isOn = AppPreferences.abbreviateEventNames,
        onCheckedChange = { AppPreferences.setAbbreviateEventNames(it) }
    )
    // 設定値で見え方が変わるサンプル。ON なら作品名プレフィックスを省く。
    Box(Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight)) {
        Text(
            AppPreferences.eventDisplayName("THE IDOLM@STER SHINY COLORS 3rdLIVE TOUR"),
            style = ImasTextRole.META.style,
            color = ImasTextRole.META.color
        )
    }
}

/** 回収の対象に配信参加を含めるか。切り替えると次の集計から新しい条件で数え直される。 */
@Composable
private fun CollectionSettingsSection() {
    val context = LocalContext.current
    ImasToggleRow(
        title = "配信参加も回収に含める",
        isOn = AppPreferences.includeStreamInCollection,
        onCheckedChange = { AppPreferences.setIncludeStreamInCollection(context, it) }
    )
}

/** 担当のイメージカラーをアプリ全体のアクセントにする設定。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OshiThemeSection(viewModel: SettingsViewModel, state: SettingsUiState) {
    ImasToggleRow(
        title = "担当の色をテーマに使う",
        icon = Icons.Filled.Palette,
        isOn = AppPreferences.useOshiColor,
        onCheckedChange = {
            AppPreferences.setUseOshiColor(it)
            // ON にした直後は担当が 1 人も選ばれていないことがある。解決はコアに任せる。
            viewModel.syncOshiTheme()
        }
    )

    if (AppPreferences.useOshiColor) {
        if (state.pickIdols.isEmpty()) {
            ImasNote("アイドル詳細で担当 (推し) に設定すると、ここで色を選べます。")
        } else {
            val selected = state.pickIdols.find { it.id == AppPreferences.oshiIdolId }
            ImasMenuRow(
                title = "テーマにする担当",
                options = state.pickIdols,
                selection = selected ?: state.pickIdols.first(),
                onSelect = {
                    AppPreferences.setOshiIdolId(it.id)
                    viewModel.syncOshiTheme()
                },
                label = { it.name }
            )
        }
    }
}

/** 開発者と、その公開リポジトリへの導線。 */
@Composable
private fun DeveloperSection() {
    val context = LocalContext.current
    ImasValueRow(key = "開発", value = "fuga-if")
    ImasNavRow(title = "GitHub (fuga-if)") {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/fuga-if")))
    }
}

/**
 * 習熟度の段階。段数とラベルを決める。
 *
 * **保存されているのは序数だけ**なので、ラベルを書き換えても記録には触らない。
 * 段を減らしたときだけ、その段にいた曲が 1 つ下へ寄る (規則は共有コアの
 * `remapMasteryLevel`)。iOS `MasteryScaleSettingsView` の移植。
 */
@Composable
private fun MasteryScaleSection() {
    var labels by remember { mutableStateOf(AppPreferences.masteryScale.labels) }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            MasteryScale.presets.forEach { (name, preset) ->
                ImasFilterChip(name, labels == preset.labels, {
                    labels = preset.labels
                    AppPreferences.setMasteryLabels(preset.labels)
                })
            }
        }
        labels.forEachIndexed { index, label ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap)
            ) {
                Box(
                    Modifier.size(14.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(DS.rTag))
                        .background(
                            MasteryPalette.fill((index + 1).toUByte(), labels.size.toUByte())
                        )
                )
                OutlinedTextField(
                    value = label,
                    onValueChange = { v ->
                        labels = labels.toMutableList().also { it[index] = v }
                    },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                // 削除できるのは**最上段だけ**。真ん中を抜くと序数の意味がずれて、
                // 寄せ先の規則 (上限で丸める) と噛み合わなくなる。
                if (index == labels.lastIndex && labels.size > 1) {
                    TextButton(onClick = {
                        labels = labels.dropLast(1)
                        AppPreferences.setMasteryLabels(labels)
                    }) { Text("削除") }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            if (labels.size < 8) {
                TextButton(onClick = { labels = labels + "" }) { Text("段を追加") }
            }
            Box(Modifier.weight(1f))
            TextButton(
                onClick = { AppPreferences.setMasteryLabels(labels) },
                enabled = labels.all { it.isNotBlank() } &&
                    labels.map { it.trim() }.toSet().size == labels.size &&
                    labels != AppPreferences.masteryScale.labels,
            ) { Text("この段階にする") }
        }
    }
}
