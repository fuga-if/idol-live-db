package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.AccountBox
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Crop
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.RadioButtonChecked
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.fugaif.imaslivedb.data.local.BrandRoleStore
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.data.producercard.ProfileSheetAssembler
import com.fugaif.imaslivedb.data.producercard.ProfileSheetFiles
import com.fugaif.imaslivedb.data.producercard.ProfileSheetMaterials
import com.fugaif.imaslivedb.data.producercard.XAvatarFetcher
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardPortraitThumbnail
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.settings.BrandRoleSettingsScreen
import com.fugaif.imaslivedb.ui.settings.BrandRoleSetupSheet
import com.fugaif.imaslivedb.ui.share.ProfileSheetPreview
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.ShareCardSaveResult
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import com.fugaif.imaslivedb.data.producercard.ProducerCardMyRecord
import uniffi.imas_core.ProfileAutoField
import uniffi.imas_core.ProfileAutoFieldRow
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.cardXAvatarHandle
import uniffi.imas_core.profileAutoFieldRows
import uniffi.imas_core.profileBrandMarks
import uniffi.imas_core.profileSheetDefault
import uniffi.imas_core.profileSheetLayout
import uniffi.imas_core.profileSheetSizes
import uniffi.imas_core.profileToggleField

private const val FILE_PREFIX = "profile_sheet"

/**
 * プロフィール帳: P としての自己紹介を、履歴書の様式の 1 枚絵にして SNS に貼る。iOS `ProfileSheetView` の移植。
 *
 * 開くとまず「載せる記録を選ぶ」画面。大きさ・証明写真・担当ブランド・載せる記録を選び、「作る」で画像の見本
 * ([ProfileSheetPreviewPage]) へ進んで書き出す。見本から鉛筆で戻れる。
 * 自分で書く欄は無く、中身はすべてアプリの記録から埋まる。名前・P歴・リンク・自分の QR は P名刺のもの
 * (ここからそのまま P名刺の編集を開ける)。担当ブランドはアプリ全体の設定 ([BrandRoleStore])。
 * 選んだものはその場で自分の名刺の行に保存する。欄の一覧と見本の値・付け外しはコア
 * (`profileAutoFieldRows` / `profileToggleField`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSheetScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()

    var card by remember { mutableStateOf<MyProducerCard?>(null) }
    var materials by remember { mutableStateOf(ProfileSheetMaterials.EMPTY) }
    var loaded by remember { mutableStateOf(false) }
    var showingPreview by remember { mutableStateOf(false) }
    var editingCard by remember { mutableStateOf<CardEdit?>(null) }
    var showingBrandSetup by remember { mutableStateOf(false) }
    var showingBrandSettings by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }

    // 証明写真
    var cropping by remember { mutableStateOf<PhotoDraft?>(null) }
    var isFetchingAvatar by remember { mutableStateOf(false) }
    var photoNotice by remember { mutableStateOf<String?>(null) }
    var hasOwnPhoto by remember { mutableStateOf(false) }
    var photoUrl by remember { mutableStateOf<String?>(null) }

    val sizes = remember { profileSheetSizes() }
    val saveLock = remember { Mutex() }

    suspend fun reloadMaterials() {
        withContext(Dispatchers.IO) {
            hasOwnPhoto = ProfileSheetFiles.photoFile(context) != null
            photoUrl = ProfileSheetFiles.effectiveUrl(context)
        }
        val mine = card ?: return
        materials = ProfileSheetAssembler.load(context, module, mine)
    }

    suspend fun load() {
        val mine = runCatching { module.producerCardRepository.myCard() }.getOrNull()
        // 材料を読み終えてから名刺を入れる (読み込み中に空の材料で並べない)。
        if (mine != null) materials = ProfileSheetAssembler.load(context, module, mine)
        withContext(Dispatchers.IO) {
            hasOwnPhoto = ProfileSheetFiles.photoFile(context) != null
            photoUrl = ProfileSheetFiles.effectiveUrl(context)
        }
        card = mine
        loaded = true
    }

    LaunchedEffect(Unit) {
        load()
        // 担当ブランドをまだ決めていなければ、はじめて開いたときに 1 度だけ確かめてもらう。
        if (card != null && BrandRoleStore.shouldPrompt(context)) {
            BrandRoleStore.markPrompted(context)
            showingBrandSetup = true
        }
    }
    // 担当ブランドの設定が変わったら (設定の画面・はじめの案内)、丸を描き直す。
    val brandRoles by BrandRoleStore.json.collectAsState()
    LaunchedEffect(brandRoles) {
        if (loaded) materials = materials.copy(record = materials.record.copy(brandRolesJson = BrandRoleStore.json(context)))
    }

    /** 選んだらその場で保存する。続けて変えても保存は順に 1 本ずつ流し、失敗したら前の選択に戻す。 */
    fun update(sheet: ProfileSheet) {
        val current = card ?: return
        val previous = current.profile
        card = current.withProfile(sheet)
        scope.launch {
            saveLock.withLock {
                runCatching {
                    val latest = module.producerCardRepository.myCard() ?: current
                    module.producerCardRepository.saveMyCard(latest.withProfile(sheet))
                }.onFailure {
                    if (card?.profile == sheet) card = card?.withProfile(previous)
                    saveError = it.message ?: "もう一度試してください。"
                }
            }
        }
    }

    fun openCardEditor(focus: String?) {
        scope.launch {
            val record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
            editingCard = CardEdit(card ?: MyProducerCard.empty(), record, focus)
        }
    }

    fun savePhoto(image: Bitmap, crop: ImasPortraitCrop) {
        scope.launch {
            val ok = withContext(Dispatchers.IO) { runCatching { ProfileSheetFiles.save(context, image, crop) }.isSuccess }
            if (!ok) photoNotice = "写真を保存できませんでした。"
            reloadMaterials()
        }
    }

    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        photoNotice = null
        scope.launch {
            val image = PaperCardCodeReader.loadBitmap(context, uri)
            if (image == null) photoNotice = "写真を読み込めませんでした。" else cropping = PhotoDraft(image, ImasPortraitCrop())
        }
    }

    fun useXAvatar(handle: String) {
        photoNotice = null
        isFetchingAvatar = true
        scope.launch {
            when (val outcome = XAvatarFetcher.fetch(handle)) {
                is XAvatarFetcher.Outcome.Image -> cropping = PhotoDraft(outcome.bitmap, ImasPortraitCrop())
                is XAvatarFetcher.Outcome.Failed -> photoNotice = outcome.message
            }
            isFetchingAvatar = false
        }
    }

    fun recrop() {
        scope.launch {
            val (source, crop) = withContext(Dispatchers.IO) {
                ProfileSheetFiles.decodeSource(context) to ProfileSheetFiles.crop(context)
            }
            if (source != null) cropping = PhotoDraft(source, crop ?: ImasPortraitCrop())
        }
    }

    fun usePhotoOfCard() {
        scope.launch {
            withContext(Dispatchers.IO) { ProfileSheetFiles.delete(context) }
            reloadMaterials()
        }
    }

    BackHandler(enabled = showingPreview) { showingPreview = false }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (showingPreview) "プロフィール帳" else "載せる記録を選ぶ") },
                navigationIcon = {
                    IconButton(onClick = { if (showingPreview) showingPreview = false else onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    if (showingPreview) {
                        IconButton(onClick = { showingPreview = false }) {
                            Icon(Icons.Filled.Edit, contentDescription = "編集")
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
                        title = "先に P名刺を作ってください",
                        message = "プロフィール帳の名前・P歴・リンク・写真は P名刺から入ります。担当と参加の記録はアプリから自動で入ります。",
                        actionTitle = "P名刺を作る",
                        onAction = { openCardEditor(null) }
                    )
                }
            }
            showingPreview -> ProfileSheetPreviewPage(mine.profile, materials, Modifier.padding(padding))
            else -> ImasFormBackdrop(Modifier.fillMaxSize().padding(padding)) {
                val sheet = mine.profile
                val rows = profileAutoFieldRows(sheet, materials.record)
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
                        "証明写真",
                        footer = "プロフィール帳だけの写真にできます (P名刺の写真は変わりません)。写真は端末の中だけに置き、バックアップには入りません。"
                    ) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
                            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                            verticalAlignment = Alignment.Top
                        ) {
                            ImasCardPortraitThumbnail(url = photoUrl)
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                Text(
                                    when {
                                        hasOwnPhoto -> "プロフィール帳の写真"
                                        photoUrl == null -> "写真なし"
                                        else -> "P名刺の写真"
                                    },
                                    style = ImasTextRole.ROW_TITLE.style, color = DS.ink
                                )
                                CardEditorAction(Icons.Filled.Image, if (hasOwnPhoto) "写真を選び直す" else "写真から選ぶ") {
                                    pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                }
                                cardXAvatarHandle(mine.links)?.let { handle ->
                                    CardEditorAction(
                                        Icons.Filled.AccountBox,
                                        if (isFetchingAvatar) "X のアイコンを取っています…" else "X のアイコンを使う (@$handle)",
                                        enabled = !isFetchingAvatar
                                    ) { useXAvatar(handle) }
                                }
                                if (hasOwnPhoto) {
                                    CardEditorAction(Icons.Filled.Crop, "位置を直す") { recrop() }
                                    CardEditorAction(Icons.AutoMirrored.Filled.Undo, "P名刺の写真に戻す") { usePhotoOfCard() }
                                }
                                photoNotice?.let { Text(it, style = ImasTextRole.NOTE.style, color = DS.danger) }
                            }
                        }
                        rows.firstOrNull { it.field == ProfileAutoField.PHOTO }?.let { FieldToggle(it, null, ::update, sheet) }
                    }
                    ImasListSection("担当ブランド", footer = "アプリ全体の設定です。担当は丸、メインは二重丸で付きます。") {
                        val marks = profileBrandMarks(materials.record)
                        val main = marks.filter { it.main }.map { it.label }
                        val oshi = marks.filter { it.checked && !it.main }.map { it.label }
                        val parts = listOfNotNull(
                            main.takeIf { it.isNotEmpty() }?.let { "メイン ${it.joinToString("・")}" },
                            oshi.takeIf { it.isNotEmpty() }?.let { "担当 ${it.joinToString("・")}" }
                        )
                        ImasNavRow(
                            title = "担当ブランドを選ぶ",
                            subtitle = parts.joinToString(" / ").ifEmpty { "まだありません" },
                            icon = Icons.Filled.RadioButtonChecked,
                            showsChevron = false,
                            subtitleLineLimit = 2
                        ) { showingBrandSettings = true }
                        rows.firstOrNull { it.field == ProfileAutoField.BRANDS }?.let { FieldToggle(it, null, ::update, sheet) }
                    }
                    ImasListSection("載せる記録", footer = "記録の無いものは並びません。外したものは画像に載りません。") {
                        rows.filter { it.field != ProfileAutoField.PHOTO && it.field != ProfileAutoField.BRANDS }.forEach { row ->
                            FieldToggle(row, if (row.fromCard) "P名刺から · ${row.value}" else row.value, ::update, sheet)
                        }
                    }
                    ImasListSection(
                        "P名刺から入るもの",
                        footer = "名前・P歴・連絡先のリンク・自分の QR は P名刺のものを使います。直すと次に作るときから変わります。"
                    ) {
                        val links = mine.links.map { cardLinkView(it).display }
                        ImasNavRow(
                            title = "P名刺のリンクを直す",
                            subtitle = if (links.isEmpty()) "まだリンクがありません" else links.joinToString("  "),
                            icon = Icons.Filled.Link
                        ) { openCardEditor("links") }
                    }
                    ImasButton(
                        title = "作る", icon = Icons.Filled.Description, role = ImasButtonRole.PRIMARY,
                        size = ImasButtonSize.LARGE, fillsWidth = true,
                        onClick = { showingPreview = true },
                        modifier = Modifier.padding(horizontal = DS.Space.screen)
                    )
                }
            }
        }
    }

    editingCard?.let { edit ->
        ProducerCardEditorSheet(
            card = edit.card,
            record = edit.record,
            focus = edit.focus,
            onSave = { saved ->
                // 名刺の欄だけを今の行に重ねる (プロフィール帳の選択は古い中身で戻さない)。
                val latest = module.producerCardRepository.myCard()
                module.producerCardRepository.saveMyCard(latest?.let { saved.copy(profileJson = it.profileJson) } ?: saved)
                load()
            },
            onDismiss = { editingCard = null }
        )
    }
    if (showingBrandSetup) BrandRoleSetupSheet(onDismiss = { showingBrandSetup = false })
    if (showingBrandSettings) {
        Dialog(
            onDismissRequest = { showingBrandSettings = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) { BrandRoleSettingsScreen(onBack = { showingBrandSettings = false }) }
    }
    cropping?.let { draft ->
        CardPhotoCropSheet(
            image = draft.image,
            initial = draft.crop,
            onDone = { savePhoto(draft.image, it) },
            onDismiss = { cropping = null },
            note = "引いて動かし、2 本の指で広げると、履歴書の証明写真の枠 (3:4) に合わせられます。写真は端末の中だけに置きます。"
        )
    }
    ImasErrorAlert(message = saveError, onDismiss = { saveError = null }, title = "保存できませんでした")
}

/** P名刺の編集を開くときに渡すもの。 */
private class CardEdit(val card: MyProducerCard, val record: ProducerCardMyRecord?, val focus: String?)

/** 写真の位置を決めるシートに渡すもの。 */
private class PhotoDraft(val image: Bitmap, val crop: ImasPortraitCrop)

@Composable
private fun FieldToggle(row: ProfileAutoFieldRow, subtitle: String?, update: (ProfileSheet) -> Unit, sheet: ProfileSheet) {
    ImasToggleRow(
        title = row.label,
        subtitle = subtitle?.ifEmpty { null },
        isOn = row.shown,
        onCheckedChange = { update(profileToggleField(sheet, row.field)) }
    )
}

/** プロフィール帳の見本と書き出し。iOS `ProfileSheetPreviewView`。鉛筆で選ぶ画面へ戻る。 */
@Composable
private fun ProfileSheetPreviewPage(sheet: ProfileSheet?, materials: ProfileSheetMaterials, modifier: Modifier) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val capture = rememberShareCardCapture()
    var exporting by remember { mutableStateOf(false) }
    var exportError by remember { mutableStateOf<String?>(null) }
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

    /** 焼いた画像を渡す。焼けなければ知らせる。 */
    fun withImage(action: suspend (Bitmap) -> Unit) {
        exporting = true
        scope.launch {
            val bitmap = capture.toBitmap()
            if (bitmap == null) exportError = "もう一度試すか、アプリを再起動してください。" else action(bitmap)
            exporting = false
        }
    }

    val layout = profileSheetLayout(sheet ?: profileSheetDefault(), materials.record)
    ImasPage(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
            ProfileSheetPreview(
                layout, materials, capture,
                Modifier.clearAndSetSemantics { contentDescription = "${layout.title}の見本" }
            )
            ImasButton(
                title = "画像を書き出す", icon = Icons.Filled.Share, role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.LARGE, fillsWidth = true, isLoading = exporting,
                onClick = { withImage { ShareCardFiles.share(context, it, FILE_PREFIX) } }
            )
            ImasCardList {
                ImasActionRow(
                    title = "写真に保存", icon = Icons.Filled.Download,
                    onClick = {
                        withImage { bitmap ->
                            when (ShareCardFiles.saveToPictures(context, bitmap, FILE_PREFIX)) {
                                ShareCardSaveResult.Saved ->
                                    Toast.makeText(context, "ピクチャに保存しました", Toast.LENGTH_SHORT).show()
                                ShareCardSaveResult.NeedsDocumentPicker -> {
                                    pendingSave = bitmap
                                    documentPicker.launch(ShareCardFiles.fileName(FILE_PREFIX))
                                }
                                ShareCardSaveResult.Failed ->
                                    Toast.makeText(context, "保存に失敗しました", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }
                )
            }
            ImasNote("中身はアプリの記録 (担当・好きな曲・担当ブランド・参加した公演・回収) から自動で入ります。載せるものは右上の鉛筆から選び直せます。")
        }
    }
    ImasErrorAlert(message = exportError, onDismiss = { exportError = null }, title = "画像を書き出せませんでした")
}
