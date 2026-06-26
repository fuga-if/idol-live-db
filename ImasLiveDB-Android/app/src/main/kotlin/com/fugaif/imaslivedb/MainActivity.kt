package com.fugaif.imaslivedb

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
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
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.navigation.AppNavigation
import com.fugaif.imaslivedb.ui.theme.ImasLiveDBTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val sync = AppModule.from(this).syncEngine
        setContent {
            ImasLiveDBTheme {
                val state by sync.state.collectAsState()
                // null=判定中 / true=既存データあり / false=初回(データ無し)
                var hasData by remember { mutableStateOf<Boolean?>(null) }
                LaunchedEffect(Unit) {
                    hasData = sync.hasData()
                    // 既存データありなら即UI表示してバックグラウンド差分同期。
                    // 初回(データ無し)はフル同期完了まで下のローディングを出す。
                    sync.sync()
                }
                val ready = hasData == true || state is CloudKitSyncEngine.SyncState.Completed
                if (ready) {
                    AppNavigation()
                } else {
                    SyncLoadingScreen(state)
                }
            }
        }
    }
}

@Composable
private fun SyncLoadingScreen(state: CloudKitSyncEngine.SyncState) {
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
