package com.fugaif.imaslivedb

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import com.fugaif.imaslivedb.data.notification.NotificationScheduler
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.games.DailyPickSheet
import com.fugaif.imaslivedb.ui.navigation.AppNavigation
import com.fugaif.imaslivedb.ui.theme.ImasLiveDBTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val sync = AppModule.from(this).syncEngine
        // ローカル通知を毎回まるごと組み直す (iOS ImasLiveDBApp と同じ起動時フック)。
        // AlarmManager の予約はアプリ更新や端末再起動で消えるうえ、担当/お気に入りの
        // 増減も起動のたびに拾い直したいので、差分更新ではなく全消去 → 全再スケジュール。
        // 未許可なら中で何もしないので、ここで権限を要求することはない。
        lifecycleScope.launch { NotificationScheduler.rescheduleAll(this@MainActivity) }
        setContent {
            ImasLiveDBTheme {
                val state by sync.state.collectAsState()
                // null=判定中 / true=データあり / false=データ無し
                var hasData by remember { mutableStateOf<Boolean?>(null) }
                var retryKey by remember { mutableStateOf(0) }
                LaunchedEffect(retryKey) {
                    // 初回 (データ無し) は seed DB を投入してから判定する。これで CloudKit token
                    // 未設定でも実データで起動できる (token はリリース版の最新化のためだけ)。
                    hasData = sync.ensureLocalData()
                    // データありなら即UI表示してバックグラウンド差分同期。
                    sync.sync()
                }
                val ready = hasData == true || state is CloudKitSyncEngine.SyncState.Completed
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
                        if (showDailyPick) {
                            DailyPickSheet(onDismiss = { showDailyPick = false })
                        }
                    }
                } else {
                    // seed 投入失敗などでデータが無いまま Error になった場合、再起動せず
                    // その場でやり直せるように再試行を用意する (無限「データを準備中…」の防止)。
                    SyncLoadingScreen(state, onRetry = { retryKey++ })
                }
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
