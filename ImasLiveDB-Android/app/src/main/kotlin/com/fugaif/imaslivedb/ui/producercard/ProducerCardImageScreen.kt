package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import com.fugaif.imaslivedb.data.local.BrandRoleStore
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.producercard.ProfileSheetAssembler
import com.fugaif.imaslivedb.data.producercard.ProfileSheetMaterials
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasPinnedPreview
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.settings.BrandRoleSetupSheet
import com.fugaif.imaslivedb.ui.share.ProfileSheetPreview
import com.fugaif.imaslivedb.ui.share.ShareCardCapture
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.ShareCardSaveResult
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.ProfileAutoField
import uniffi.imas_core.ProfileAutoFieldRow
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.ProfileSheetLayout
import uniffi.imas_core.profileAutoFieldRows
import uniffi.imas_core.profileSheetLayout
import uniffi.imas_core.profileSheetSizes
import uniffi.imas_core.profileToggleField

private const val FILE_PREFIX = "producer_card_image"

/**
 * SNS に貼る P名刺の画像: 自分の P名刺と記録を、履歴書の様式の 1 枚絵にする (P名刺の 3 つ目の出し方)。
 * iOS `ProducerCardImageView` の移植。
 *
 * 開くとすぐできあがりの見本が上に固定で見え (押すと原寸)、選ぶのは大きさ (4:5 / 9:16) と載せる項目の付け外しだけ。
 * 中身はすべて P名刺とアプリの記録から入る: 名前・P歴・写真・リンク・自分の QR・好きな曲は P名刺
 * (直すのは P名刺の編集)、担当ブランドの丸はアプリ全体の設定 ([BrandRoleStore])、参加した公演・回収は記録。
 * 名刺 (交換するもの) に載せない記録の数も、ここ (見せるもの) には載る。
 * 選んだものはその場で自分の名刺の行に保存する。欄の一覧と値・付け外しはコア
 * (`profileAutoFieldRows` / `profileToggleField`、組みは `profileSheetLayout`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProducerCardImageScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()

    var card by remember { mutableStateOf<MyProducerCard?>(null) }
    var materials by remember { mutableStateOf(ProfileSheetMaterials.EMPTY) }
    var loaded by remember { mutableStateOf(false) }
    var showingBrandSetup by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var exportError by remember { mutableStateOf<String?>(null) }
    var exporting by remember { mutableStateOf(false) }
    val capture = rememberShareCardCapture()
    // Android 9 以下の保存経路。保存先を選んで戻ってくるまで画像を持っておく。
    var pendingSave by remember { mutableStateOf<Bitmap?>(null) }
    val documentPicker = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/png")) { uri ->
        val bitmap = pendingSave
        pendingSave = null
        if (uri == null || bitmap == null) return@rememberLauncherForActivityResult
        scope.launch {
            val ok = ShareCardFiles.writeTo(context, uri, bitmap)
            Toast.makeText(context, if (ok) "画像を保存しました" else "保存に失敗しました", Toast.LENGTH_SHORT).show()
        }
    }

    val sizes = remember { profileSheetSizes() }
    // 最後に流した保存 (選択の保存は順に 1 本ずつ)。
    val lastSave = remember { mutableStateOf<Job?>(null) }

    LaunchedEffect(Unit) {
        val mine = runCatching { module.producerCardRepository.myCard() }.getOrNull()
        // 材料を読み終えてから名刺を入れる (読み込み中に空の材料で並べない)。
        if (mine != null) materials = ProfileSheetAssembler.load(context, module, mine)
        card = mine
        loaded = true
        // 担当ブランドをまだ決めていなければ、はじめて開いたときに 1 度だけ確かめてもらう (画像に丸が付く)。
        if (mine != null && BrandRoleStore.shouldPrompt(context)) {
            BrandRoleStore.markPrompted(context)
            showingBrandSetup = true
        }
    }
    // 担当ブランドの設定が変わったら (はじめの案内・設定の画面)、丸を描き直す。
    val brandRoles by BrandRoleStore.json.collectAsState()
    LaunchedEffect(brandRoles) {
        if (loaded) materials = materials.copy(record = materials.record.copy(brandRolesJson = BrandRoleStore.json(context)))
    }

    /**
     * 選んだらその場で保存する。保存は順に 1 本ずつ流し (古い選択が後から書かれないように。読んで重ねて書くのは
     * リポジトリが 1 本ずつ流す)、失敗したときは最後に変えた分だけ前の選択に戻す。
     * 名刺のほかの欄と好きな曲は DB の最新を使う (好きな曲は P名刺の編集で直すので、開いた時の古い選択で戻さない)。
     * 保存はアプリのスコープで流す (選んですぐ戻っても、画面と一緒に取り消されて書き落とさない。iOS の Task と同じ)。
     */
    fun update(sheet: ProfileSheet) {
        val current = card ?: return
        val previous = current.profile
        card = current.withProfile(sheet)
        // 前の保存が終わってから書く (アプリのスコープは並んで走るので、古い選択が後から書かれないように)。
        val prior = lastSave.value
        lastSave.value = module.appScope.launch {
            prior?.join()
            try {
                module.producerCardRepository.updateMyCard { latest ->
                    val row = latest ?: current
                    row.withProfile(sheet.copy(songs = row.profile.songs))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    if (card?.profile == sheet) card = card?.withProfile(previous)
                    saveError = e.message ?: "もう一度試してください。"
                }
            }
        }
    }

    /** 焼いた画像を渡す。焼けなければ知らせる。 */
    fun withImage(action: suspend (Bitmap) -> Unit) {
        exporting = true
        scope.launch {
            val bitmap = capture.toBitmap()
            if (bitmap == null) exportError = "もう一度試すか、アプリを再起動してください。" else action(bitmap)
            exporting = false
        }
    }

    fun export() = withImage { ShareCardFiles.share(context, it, FILE_PREFIX) }

    fun saveToPictures() = withImage { bitmap ->
        when (ShareCardFiles.saveToPictures(context, bitmap, FILE_PREFIX)) {
            ShareCardSaveResult.Saved -> Toast.makeText(context, "ピクチャに保存しました", Toast.LENGTH_SHORT).show()
            ShareCardSaveResult.NeedsDocumentPicker -> {
                pendingSave = bitmap
                documentPicker.launch(ShareCardFiles.fileName(FILE_PREFIX))
            }
            ShareCardSaveResult.Failed -> Toast.makeText(context, "保存に失敗しました", Toast.LENGTH_SHORT).show()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SNS に貼る画像") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                },
                actions = {
                    if (card != null) {
                        IconButton(onClick = ::export, enabled = !exporting) {
                            Icon(Icons.Filled.Share, contentDescription = "画像を書き出す")
                        }
                    }
                }
            )
        }
    ) { padding ->
        val mine = card
        when {
            !loaded -> ImasLoadingState(Modifier.padding(padding))
            mine == null -> ImasPage(modifier = Modifier.padding(padding)) {
                ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.Badge,
                        title = "まだ P名刺がありません",
                        message = "P名刺を作ると、名前・写真・好きな曲と参加の記録から画像ができます。"
                    )
                }
            }
            else -> {
                val sheet = mine.profile
                val layout = profileSheetLayout(sheet, materials.record)
                val rows = profileAutoFieldRows(sheet, materials.record)
                Column(Modifier.fillMaxSize().padding(padding)) {
                    ImasPinnedPreview(full = { SheetPreview(layout, materials, rememberShareCardCapture()) }) {
                        SheetPreview(layout, materials, capture)
                    }
                    ImasFormBackdrop(Modifier.weight(1f).fillMaxWidth()) {
                        Column(
                            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section),
                            verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
                        ) {
                            ImasListSection("大きさ") {
                                ImasSegmented(
                                    labels = sizes.map { "${it.label} ${it.caption}" },
                                    selection = sizes.indexOfFirst { it.size == sheet.size },
                                    onSelect = { i -> update(sheet.copy(size = sizes[i].size)) },
                                    modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV)
                                )
                            }
                            ImasListSection(
                                "載せる項目",
                                footer = "記録の無いものは並びません。名前・P歴・写真・リンク・自分の QR・好きな曲は P名刺の編集で、担当ブランドは設定で直せます。"
                            ) {
                                rows.forEach { row ->
                                    ImasToggleRow(
                                        title = row.label,
                                        subtitle = subtitle(row),
                                        isOn = row.shown,
                                        onCheckedChange = { update(profileToggleField(sheet, row.field)) }
                                    )
                                }
                            }
                            Column(
                                Modifier.padding(horizontal = DS.Space.screen),
                                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
                            ) {
                                ImasButton(
                                    title = "画像を書き出す", icon = Icons.Filled.Share, role = ImasButtonRole.PRIMARY,
                                    size = ImasButtonSize.LARGE, fillsWidth = true, isLoading = exporting, onClick = ::export
                                )
                                ImasCardList {
                                    ImasActionRow(
                                        title = "写真に保存", icon = Icons.Filled.Download,
                                        position = ImasRowPosition.FIRST, onClick = ::saveToPictures
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showingBrandSetup) BrandRoleSetupSheet(onDismiss = { showingBrandSetup = false })
    ImasErrorAlert(message = saveError, onDismiss = { saveError = null }, title = "保存できませんでした")
    ImasErrorAlert(message = exportError, onDismiss = { exportError = null }, title = "画像を書き出せませんでした")
}

/** 見本 (実寸の画像を幅に合わせて縮めて見せる。焼くのは [capture])。 */
@Composable
private fun SheetPreview(layout: ProfileSheetLayout, materials: ProfileSheetMaterials, capture: ShareCardCapture) {
    ProfileSheetPreview(
        layout, materials, capture,
        Modifier.clearAndSetSemantics { contentDescription = "${layout.title}の見本" }
    )
}

/** 行の副題: 中身の出どころ (P名刺・設定) と今の値。 */
private fun subtitle(row: ProfileAutoFieldRow): String? {
    val from = when (row.field) {
        ProfileAutoField.BRANDS -> "設定の担当ブランドから"
        ProfileAutoField.SONGS -> "P名刺の好きな曲から"
        else -> if (row.fromCard) "P名刺から" else null
    }
    return listOfNotNull(from, row.value.ifEmpty { null }).joinToString(" · ").ifEmpty { null }
}
