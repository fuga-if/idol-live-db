package com.fugaif.imaslivedb.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.lifecycleScope
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasListBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasLiveDBTheme
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import com.fugaif.imaslivedb.ui.components.searchFiltered

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

    ImasListBackdrop(Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
            Text(
                text = "担当を選ぶ",
                style = ImasTextRole.HERO_TITLE.style,
                color = ImasTextRole.HERO_TITLE.color,
                modifier = Modifier.padding(horizontal = DS.Space.screen).padding(top = DS.Space.gap)
            )
            Text(
                text = "ウィジェットに出すアイドルを選びます。画像を取り込んであるアイドルが並びます。",
                style = ImasTextRole.NOTE.style,
                color = ImasTextRole.NOTE.color,
                modifier = Modifier.padding(horizontal = DS.Space.screen).padding(vertical = DS.Space.header)
            )

            when {
                candidates == null -> ImasLoadingState(modifier = Modifier.weight(1f))

                candidates.isEmpty() -> ImasEmptyState(
                    kind = ImasEmptyStateKind.EMPTY,
                    title = "表示できるアイドルがいません",
                    message = "アプリのアイドル詳細から画像を取り込むと、ここに並びます。",
                    modifier = Modifier.weight(1f)
                )

                else -> {
                    ImasSearchField(
                        prompt = "名前・ブランドで絞り込む",
                        text = query,
                        onTextChange = { query = it },
                        modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                    )
                    OshiCandidateList(
                        candidates = searchFiltered(candidates, query) {
                            listOf(it.name, it.nameKana, it.brandShortName)
                        },
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
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        itemsIndexed(candidates, key = { _, candidate -> candidate.idolId }) { index, candidate ->
            // 並びはブランド順なので、直前の行とブランドが変わったところが区切り。
            if (candidates.getOrNull(index - 1)?.brandId != candidate.brandId) {
                ImasSectionHeader(
                    title = candidate.brandShortName.orEmpty(),
                    tight = true,
                    seed = candidate.brandColorHex,
                    brand = candidate.brandId
                )
            }
            ImasSelectableRow(
                title = candidate.name,
                isSelected = candidate.idolId == selectedId,
                isSingle = true,
                leading = ImasRowLeading.Avatar(
                    label = candidate.name,
                    seed = candidate.colorHex,
                    brand = candidate.brandId,
                    entityId = candidate.idolId
                ),
                onClick = { onPick(candidate) }
            )
        }
    }
}

