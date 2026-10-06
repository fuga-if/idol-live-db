package com.fugaif.imaslivedb.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.local.BrandRoleStore
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStepSliderRow
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.BrandRoleRow
import uniffi.imas_core.brandRoleFromIndex
import uniffi.imas_core.brandRoleSet
import uniffi.imas_core.brandRoleStep
import uniffi.imas_core.brandRoleSteps

private const val BRAND_ROLE_NOTE = "担当は丸、メインは二重丸でプロフィール帳の担当ブランドに付きます。メインはいくつでも選べます。"

/**
 * 担当ブランドの並び (ブランドごとに なし / 担当 / メイン の段のついたスライダー)。iOS `BrandRoleSection`。
 * 設定の画面とはじめの案内で同じ中身。段・既定・保存の形はコア (`brandRoleSettings` / `brandRoleSet`)。
 */
@Composable
fun BrandRoleSection(rows: List<BrandRoleRow>, onChange: (List<BrandRoleRow>) -> Unit, footer: String? = null) {
    val steps = remember { brandRoleSteps() }
    ImasListSection("担当ブランド", footer = footer) {
        rows.forEach { row ->
            ImasStepSliderRow(
                title = row.label,
                steps = steps.map { it.label },
                index = brandRoleStep(row.role).index.toInt(),
                onIndexChange = { i -> onChange(brandRoleSet(rows, row.brandId, brandRoleFromIndex(i.toLong()))) },
                seed = row.color,
                brand = row.brandId
            )
        }
    }
}

/** 設定の「担当ブランド」。動かしたらその場で保存する (設定の画面の決まり)。iOS `BrandRoleSettingsView`。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrandRoleSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    var rows by remember { mutableStateOf<List<BrandRoleRow>>(emptyList()) }
    var configured by remember { mutableStateOf(true) }
    var loaded by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val settings = BrandRoleStore.load(context, module)
        rows = settings.rows
        configured = settings.configured
        loaded = true
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("担当ブランド") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                if (!loaded) {
                    ImasInlineLoading()
                } else {
                    BrandRoleSection(
                        rows = rows,
                        onChange = { next ->
                            rows = next
                            configured = true
                            BrandRoleStore.save(context, next)
                        },
                        footer = if (configured) BRAND_ROLE_NOTE
                        else "担当アイドルと参加した公演から組んだ見立てです。動かすと決まります。$BRAND_ROLE_NOTE"
                    )
                }
            }
        }
    }
}

/**
 * はじめの案内: 担当ブランドを選ぶ (初回起動の後と、まだ決めていない人がプロフィール帳をはじめて開いたときに 1 度だけ)。
 * iOS `BrandRoleSetupSheet`。記録から組んだ見立てを並べて確かめてもらう。× で飛ばせる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrandRoleSetupSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    var rows by remember { mutableStateOf<List<BrandRoleRow>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        // 出したら 1 度きり (× でも下へ引いて閉じても、もう案内しない)。
        BrandRoleStore.markPrompted(context)
        rows = BrandRoleStore.load(context, module).rows
        loaded = true
    }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        ImasFormBackdrop {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(
                        canSave = loaded,
                        onCancel = onDismiss,
                        onSave = {
                            BrandRoleStore.save(context, rows)
                            onDismiss()
                        }
                    ),
                    title = "担当ブランド"
                )
                ImasNote(
                    "担当しているブランドを選んでください。プロフィール帳の担当ブランドの丸になります。あとから設定で直せます。",
                    Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                )
                if (loaded) {
                    BrandRoleSection(rows = rows, onChange = { rows = it }, footer = BRAND_ROLE_NOTE)
                } else {
                    ImasInlineLoading()
                }
            }
        }
    }
}
