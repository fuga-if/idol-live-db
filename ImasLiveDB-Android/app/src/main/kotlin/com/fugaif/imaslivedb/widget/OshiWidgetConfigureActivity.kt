package com.fugaif.imaslivedb.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.lifecycleScope
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasLiveDBTheme
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.launch

/**
 * 担当画像ウィジェットの設定画面 (`APPWIDGET_CONFIGURE`)。
 * iOS の `SelectOshiIntent` / `OshiEntityQuery` (長押し → 編集 のアイドル選択) に対応する。
 *
 * ## 候補は「画像を取り込んであるアイドル」だけ
 *
 * 画像が 1 枚も無いアイドルを選んでも、ウィジェットにはプレースホルダしか出ない。
 * 並びはブランド順 → アイドルの sort_order 順 ([OshiCatalog.candidates])。
 * 名前とブランドで絞れる検索も置く (担当が数十人になると縦スクロールでは探せない)。
 *
 * ## 2 種類のウィジェットで共用する
 *
 * 「タップで送る」版と「タップでアプリ」版は選ぶものが同じなので設定画面も共通。
 * どちらのウィジェットとして置かれたかは [AppWidgetManager] に聞いて、
 * 描き直す対象を選び分ける (取り違えると別種のウィジェットの絵で上書きしてしまう)。
 */
class OshiWidgetConfigureActivity : ComponentActivity() {

    private var appWidgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        // 先に「キャンセル」を返しておく。戻るキーで抜けた場合はこれが結果になり、
        // ホーム画面にウィジェットが置かれない (設定を確定しないと置かない、が Android の作法)。
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContent {
            ImasLiveDBTheme {
                var candidates by remember { mutableStateOf<List<OshiCandidate>?>(null) }
                var selectedId by remember { mutableStateOf<String?>(null) }

                LaunchedEffect(Unit) {
                    // 置き直し (再設定) のときは今の選択にチェックを付ける。
                    selectedId = runCatching { currentSelection() }.getOrNull()
                    candidates = OshiCatalog.candidates(this@OshiWidgetConfigureActivity)
                }

                OshiConfigureScreen(
                    candidates = candidates,
                    selectedId = selectedId,
                    onPick = { candidate -> confirm(candidate.idolId) }
                )
            }
        }
    }

    private suspend fun currentSelection(): String? {
        val glanceId = GlanceAppWidgetManager(this).getGlanceIdBy(appWidgetId)
        return selectedOshiIdolId(this, glanceId)
    }

    /** 選択を保存してウィジェットを描き直し、ホーム画面へ設置を許可する。 */
    private fun confirm(idolId: String) {
        lifecycleScope.launch {
            runCatching {
                val glanceId = GlanceAppWidgetManager(this@OshiWidgetConfigureActivity).getGlanceIdBy(appWidgetId)
                setOshiIdol(this@OshiWidgetConfigureActivity, glanceId, idolId)
                // 新規設置のときはまだウィジェットが束ねられておらず update が空振りするが、
                // 直後にシステムが onUpdate を呼ぶので、そこで保存済みの選択が読まれる。
                targetWidget().update(this@OshiWidgetConfigureActivity, glanceId)
            }
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
            finish()
        }
    }

    /** この appWidgetId がどちらの種類のウィジェットか。 */
    private fun targetWidget(): GlanceAppWidget {
        val provider = AppWidgetManager.getInstance(this)
            ?.getAppWidgetInfo(appWidgetId)?.provider?.className
        return if (provider == OshiLauncherWidgetReceiver::class.java.name) {
            OshiLauncherWidget
        } else {
            OshiImageWidget
        }
    }
}

@Composable
private fun OshiConfigureScreen(
    candidates: List<OshiCandidate>?,
    selectedId: String?,
    onPick: (OshiCandidate) -> Unit
) {
    var query by remember { mutableStateOf("") }

    Surface(modifier = Modifier.fillMaxSize(), color = DS.bg) {
        Column(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
            Text(
                text = "担当を選ぶ",
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = DS.ink,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)
            )
            Text(
                text = "ウィジェットに出すアイドルを選びます。画像を取り込んであるアイドルが並びます。",
                fontSize = 13.sp,
                color = DS.ink2,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
            )

            when {
                candidates == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = DS.sys)
                }

                candidates.isEmpty() -> Box(
                    modifier = Modifier.fillMaxSize().padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "表示できるアイドルがいません。\nアプリのアイドル詳細から画像を取り込むと、ここに並びます。",
                        fontSize = 14.sp,
                        color = DS.ink2
                    )
                }

                else -> {
                    TextField(
                        value = query,
                        onValueChange = { query = it },
                        singleLine = true,
                        placeholder = { Text("名前・ブランドで絞り込む", fontSize = 14.sp) },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp)
                    )
                    OshiCandidateList(
                        candidates = candidates.filter { it.matches(query) },
                        selectedId = selectedId,
                        onPick = onPick
                    )
                }
            }
        }
    }
}

/** ブランドの区切りを挟みながら候補を並べる (並び順は [OshiCatalog.candidates] が決めている)。 */
@Composable
private fun OshiCandidateList(
    candidates: List<OshiCandidate>,
    selectedId: String?,
    onPick: (OshiCandidate) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        itemsIndexed(candidates, key = { _, candidate -> candidate.idolId }) { index, candidate ->
            // 並びはブランド順なので、直前の行とブランドが変わったところが区切り。
            if (candidates.getOrNull(index - 1)?.brandId != candidate.brandId) {
                BrandHeader(candidate)
            }
            OshiRow(
                candidate = candidate,
                selected = candidate.idolId == selectedId,
                onPick = { onPick(candidate) }
            )
        }
    }
}

@Composable
private fun BrandHeader(candidate: OshiCandidate) {
    val theme = ImasTheme.derive(seed = candidate.brandColorHex, brand = null, dark = true)
    Text(
        text = candidate.brandShortName.orEmpty(),
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        color = theme.accent,
        modifier = Modifier.padding(start = 8.dp, top = 16.dp, bottom = 4.dp)
    )
}

@Composable
private fun OshiRow(candidate: OshiCandidate, selected: Boolean, onPick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onPick).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasAvatar(
            label = candidate.name,
            seed = candidate.colorHex,
            brand = candidate.brandColorHex,
            size = 44.dp,
            entityId = candidate.idolId
        )
        Text(
            text = candidate.name,
            fontSize = 15.sp,
            color = DS.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(horizontal = 8.dp)
        )
        if (selected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "選択中",
                tint = DS.sys,
                modifier = Modifier.size(20.dp).padding(end = 4.dp)
            )
        }
    }
}

/** 名前・ブランド略称の部分一致 (iOS のピッカー検索と同じ当たり方)。 */
private fun OshiCandidate.matches(query: String): Boolean {
    val trimmed = query.trim()
    if (trimmed.isEmpty()) return true
    return name.contains(trimmed, ignoreCase = true) ||
        brandShortName?.contains(trimmed, ignoreCase = true) == true
}
