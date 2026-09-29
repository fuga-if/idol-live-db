package com.fugaif.imaslivedb

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.fugaif.imaslivedb.data.core.SnapshotUnavailableException
import com.fugaif.imaslivedb.data.db.DatabaseBoot
import com.fugaif.imaslivedb.data.notification.NotificationScheduler
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.games.DailyPickSheet
import com.fugaif.imaslivedb.ui.ledger.TicketExpensePrompt
import com.fugaif.imaslivedb.ui.navigation.AppNavigation
import com.fugaif.imaslivedb.ui.theme.ImasLiveDBTheme
import kotlinx.coroutines.launch
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import com.fugaif.imaslivedb.data.local.LocalWriteFailure
import com.fugaif.imaslivedb.data.sync.LocalDataStartup

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val module = AppModule.from(this)
        val boot = module.databaseBoot
        val sync = module.syncEngine
        openDatabase()
        setContent {
            ImasLiveDBTheme {
                when (val bootState = boot.state.collectAsState().value) {
                    DatabaseBoot.State.Preparing -> SyncLoadingScreen(CloudKitSyncEngine.SyncState.Idle, onRetry = {})
                    is DatabaseBoot.State.Failed -> DatabaseRecoveryScreen(bootState.detail, onRetry = ::openDatabase)
                    DatabaseBoot.State.Ready -> AppRoot(sync)
                }
            }
        }
    }

    /**
     * 端末の DB を開き、開けたら DB を読む起動時の処理を始める。開けなければ復旧画面が出る
     * (その「もう一度試す」もここを呼ぶ)。
     */
    private fun openDatabase() {
        val module = AppModule.from(this)
        lifecycleScope.launch {
            module.databaseBoot.prepare()
            // 通知の積み直しはスナップショットを読むので、seed の投入・入れ直しの後 (AppRoot) に回す。
        }
    }

    /** DB を開けた後の画面。 */
    @Composable
    private fun AppRoot(sync: CloudKitSyncEngine) {
        val state by sync.state.collectAsState()
        // null=判定中 / true=データあり / false=データ無し
        var hasData by remember { mutableStateOf<Boolean?>(null) }
        var retryKey by remember { mutableStateOf(0) }
        /** マスタのスナップショットを読み込めなかったときの詳細。 */
        var loadError by remember { mutableStateOf<String?>(null) }
        LaunchedEffect(retryKey) {
            loadError = null
            // 初回 (データ無し) は seed DB を投入してから判定する。これで CloudKit token
            // 未設定でも実データで起動できる (token はリリース版の最新化のためだけ)。
            val module = AppModule.from(this@MainActivity)
            // マスタの読み取りはスナップショットだけが答えるので、seed の投入・入れ直しを済ませてから
            // 読み直したものを画面に出す (先に誰かが読んだ空・古いスナップショットを出さない)。
            // 読み込めなければ再試行の画面へ。
            val prepared = try {
                LocalDataStartup.prepare(sync, module.snapshotStoreProvider) != null
            } catch (e: SnapshotUnavailableException) {
                loadError = "${e.message}\n(詳細: ${e.cause?.message ?: "不明"})"
                return@LaunchedEffect
            }
            // データありなら即UI表示してバックグラウンド差分同期 (アプリのスコープで走る)。
            sync.requestSync()
            if (prepared) {
                // ローカル通知を毎回まるごと組み直す (iOS ImasLiveDBApp と同じ起動時フック)。
                // AlarmManager の予約はアプリ更新や端末再起動で消えるうえ、担当/お気に入りの
                // 増減も起動のたびに拾い直したいので、差分更新ではなく全消去 → 全再スケジュール。
                // 未許可なら中で何もしないので、ここで権限を要求することはない。
                // マスタを読み直した後に回す (RedTeam A-M3)。画面は待たない。
                module.appScope.launch { NotificationScheduler.rescheduleAll(this@MainActivity) }
            }
            hasData = prepared
        }
        val ready = loadError == null && (hasData == true || state is CloudKitSyncEngine.SyncState.Completed)
        if (ready) {
            // 起動時の日替わりピック。データが揃ってから 1 回だけ枠を消費する
            // (「今日はもう出したか」の判定と印付けはコア + GameProgressStore)。
            var showDailyPick by remember {
                mutableStateOf(AppModule.from(this@MainActivity).gameProgressStore.consumeDailySheetSlot())
            }
            // オーバーレイにするのは、この上でタグピッカー (ModalBottomSheet) を開くため。
            // ボトムシートの中からボトムシートを開くと重なりとタッチ処理が壊れる。
            Box(modifier = Modifier.fillMaxSize()) {
                AppNavigation()
                // 参加を付けた直後の「チケット代を記録しますか」。参加登録の入口は
                // 一覧のスワイプ・公演の参加シート・セトリ画面と複数あるので、
                // 出すのは**アプリのルート 1 箇所**にまとめる (iOS ContentView と同じ)。
                TicketExpensePrompt()
                // 端末にしか無いデータの書き込み失敗は、どの画面で起きてもここで知らせる。
                LocalWriteFailureAlert()
                if (showDailyPick) {
                    DailyPickSheet(onDismiss = { showDailyPick = false })
                }
            }
        } else {
            // seed 投入失敗などでデータが無いまま Error になった場合、再起動せず
            // その場でやり直せるように再試行を用意する (無限「データを準備中…」の防止)。
            val shown = loadError?.let { CloudKitSyncEngine.SyncState.Error(it) } ?: state
            SyncLoadingScreen(shown, onRetry = { retryKey++ })
        }
    }

    override fun onStart() {
        super.onStart()
        // サインイン済みなら isAdmin / BAN 状態をサーバから最新化する。BAN は /auth/login では
        // 返らないため、これが無いと BAN 済みユーザーに編集導線が出続ける。前面に出たときに、
        // 間隔を空けて問い合わせる (iOS は起動時)。
        val module = AppModule.from(this)
        // セッションの期限が近ければ先に再発行する (JWT は 1 年で切れる)。
        module.appScope.launch {
            module.authService.refreshSessionIfDue()
            module.authService.refreshMeIfDue()
        }
        // 送れなかったお気に入りの集計を送り直す。
        module.appScope.launch { module.favoriteAggregation.flushPending() }
    }
}

/**
 * 端末ローカルの書き込み失敗の知らせ ([LocalWriteFailure])。出ている間は次を重ねない
 * (iOS `LocalWriteFailureAlert` と同じ)。ダイアログは別ウィンドウなので、シートの上にも出る。
 */
@Composable
private fun LocalWriteFailureAlert() {
    var notice by remember { mutableStateOf<LocalWriteFailure.Notice?>(null) }
    LaunchedEffect(Unit) {
        LocalWriteFailure.notices.collect { if (notice == null) notice = it }
    }
    notice?.let { shown ->
        AlertDialog(
            onDismissRequest = { notice = null },
            title = { Text(shown.title) },
            text = { Text(shown.message) },
            confirmButton = { TextButton(onClick = { notice = null }) { Text("OK") } }
        )
    }
}

/**
 * DB を開けなかったときの画面 (iOS `DatabaseRecoveryView` と同じ)。端末のデータは消していないので、
 * 「もう一度試す」だけを出す。再インストールは勧めない (端末にしかないデータが消える)。
 */
@Composable
private fun DatabaseRecoveryScreen(detail: String, onRetry: () -> Unit) {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        // 文字を大きくしている人でも読み切れるようにスクロールさせる。
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            ImasEmptyState(
                icon = Icons.Filled.Warning,
                title = "データを開けませんでした",
                message = "端末に保存しているデータを開く途中で問題が起きました。データは消えていません。" +
                    "もう一度試しても開けないときは、アプリを最新版に更新してください。",
                actionTitle = "もう一度試す",
                onAction = onRetry
            )
            SelectionContainer {
                Text(
                    "詳細: $detail",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 24.dp)
                )
            }
        }
    }
}

@Composable
private fun SyncLoadingScreen(state: CloudKitSyncEngine.SyncState, onRetry: () -> Unit) {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier.fillMaxSize().padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            when (state) {
                is CloudKitSyncEngine.SyncState.Error -> {
                    Text(
                        "データの取得に失敗しました",
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center
                    )
                    Text(
                        state.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                    androidx.compose.material3.Button(onClick = onRetry, modifier = Modifier.padding(top = 16.dp)) {
                        Text("再試行")
                    }
                }
                is CloudKitSyncEngine.SyncState.Syncing -> {
                    CircularProgressIndicator(modifier = Modifier.size(48.dp))
                    Text(
                        "${state.label} を取得中… (${state.step}/${state.total})",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 16.dp)
                    )
                }
                else -> {
                    CircularProgressIndicator(modifier = Modifier.size(48.dp))
                    Text(
                        "データを準備中…",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 16.dp)
                    )
                }
            }
        }
    }
}
