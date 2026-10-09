package com.fugaif.imaslivedb.ui.producercard

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Crop
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.geometry.Offset
import com.fugaif.imaslivedb.data.producercard.XAvatarFetcher
import com.fugaif.imaslivedb.data.producercard.FavoriteSongSource
import com.fugaif.imaslivedb.data.local.BrandRoleStore
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.settings.BrandRoleSettingsScreen
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RecentActors
import uniffi.imas_core.producerCardOshiPicks
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import uniffi.imas_core.BrandRole
import uniffi.imas_core.ProfileSongInput
import uniffi.imas_core.favoriteSongPicks
import com.fugaif.imaslivedb.ui.designsystem.ImasCardDesignOption
import com.fugaif.imaslivedb.ui.designsystem.ImasCardDesignPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasCardFace
import uniffi.imas_core.CardDesign
import uniffi.imas_core.cardQrLinkView
import uniffi.imas_core.cardXAvatarHandle
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.ui.designsystem.ImasCardPortraitThumbnail
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCropper
import com.fugaif.imaslivedb.ui.theme.ImasCardNameFonts
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardLinkView
import uniffi.imas_core.ProducerCardInputError
import uniffi.imas_core.ScannedCode
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.cardDesignKey
import uniffi.imas_core.cardDesigns
import uniffi.imas_core.classifyScannedCode
import uniffi.imas_core.encodeProducerCard
import uniffi.imas_core.normalizeCardQrUrl
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ProducerCardField
import com.fugaif.imaslivedb.data.producercard.ProducerCardMyRecord
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasDiscardConfirmation
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormToggle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPinnedPreview
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.CardPhotoShape
import uniffi.imas_core.CardPhotoSource
import uniffi.imas_core.cardPhotoShape
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCard
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.imas_core.CardLink
import uniffi.imas_core.CardLinkKind
import uniffi.imas_core.cardLinkKinds
import uniffi.imas_core.normalizeCardLink
import uniffi.imas_core.producerCardInputErrorMessage
import uniffi.imas_core.producerCardEmbedsCardId
import uniffi.imas_core.producerCardLimits
import uniffi.imas_core.producerCardNewId
import uniffi.imas_core.validateProducerCard
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive

/** 編集中のリンク 1 本。 */
private data class EditableLink(val id: String = UUID.randomUUID().toString(), val kind: CardLinkKind, val value: String)

private const val RENEW_CARD_ID_NOTE =
    "作り直すと、相手の名刺入れではあなたの名刺が別の人の名刺になります (今までの会った記録とはつながりません)。"

/** 名刺 id を作り直す (名刺 id を名刺に載せている間だけ出す。コアの `producerCardEmbedsCardId`)。 */
@Composable
private fun CardIdCard(renewedCardId: String?, onRenew: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasCardList {
            ImasActionRow(
                title = if (renewedCardId == null) "名刺 id を作り直す" else "名刺 id を作り直しました (✓ で保存)",
                icon = Icons.Filled.Refresh,
                onClick = onRenew
            )
        }
        ImasNote(RENEW_CARD_ID_NOTE)
    }
}

/**
 * 自分の P名刺を作る・直す。iOS `ProducerCardEditorView` の移植。書くのは名前・ひとこと・P歴・リンク・
 * 名刺のデザイン・名刺の写真・自分の QR・好きな曲で、担当と記録の数はアプリの記録から入る (載せたくない項目はここで外す)。
 * 担当ブランドはアプリ全体の設定へ行く。好きな曲と担当ブランドは名刺 (QR) には入らず、P名刺の画像 (SNS に貼る画像) に載る。
 * 上に名刺の見本を置き、変えたものはその場で見本に出る。
 *
 * デザインは 4 つ (入場証・かしこまった名刺・ポップ・担当を大きく) と「自作の画像」から選ぶだけ (細かい見た目は選ばせない)。
 * 自作の画像は写真から選んだ名刺の画像 (表・任意で裏) を、紙の名刺の取り込みと同じく四隅を見つけて平らにし、
 * 画像の QR があれば自分の QR に入れる。名刺の写真は X のアイコンからも取れる。
 *
 * 入力の検査・リンクと QR の URL の正規化・デザインの一覧・X のアイコンの規則はコア
 * (`validateProducerCard` / `normalizeCardLink` / `normalizeCardQrUrl` / `cardDesigns` / `cardXAvatarHandle`)。
 */
@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ProducerCardEditorSheet(
    card: MyProducerCard,
    record: ProducerCardMyRecord?,
    onSave: suspend (MyProducerCard) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val limits = remember { producerCardLimits() }
    val kinds = remember { cardLinkKinds() }
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf(card.name) }
    var message by remember { mutableStateOf(card.message) }
    var sinceYear by remember { mutableStateOf(card.sinceYear) }
    val links = remember { mutableStateListOf(*card.links.map { EditableLink(kind = it.kind, value = it.value) }.toTypedArray()) }
    var hidden by remember { mutableStateOf(card.hidden) }
    // アプリの担当のアイドル (名刺に載せる担当を選ぶ材料。行に写真か判子を出す)。
    var oshiIdols by remember { mutableStateOf<Map<String, Idol>>(emptyMap()) }
    // 名刺に載せる担当の選択 (idol id、載せる順。null はまだ選んでいない)。
    var oshiChoice by remember { mutableStateOf(card.cardOshiChoice) }
    var showingOshiPicker by remember { mutableStateOf(false) }
    val oshiEntries = record?.oshiEntries.orEmpty()
    // 名刺に載せる担当 (本人の選択。まだ選んでいなければ自動の選び方。規則はコア)。
    val oshi = record?.cardOshiIds(oshiChoice).orEmpty().mapNotNull { oshiIdols[it] }
    // 先頭の担当の画像 (担当を大きく のデザインの札)。
    var leadImage by remember { mutableStateOf<String?>(null) }
    // 好きな曲 (お気に入りから選んだ曲 id、載せる順。null はまだ選んでいない)。
    var songs by remember { mutableStateOf(card.profile.songs) }
    var favorites by remember { mutableStateOf<List<ProfileSongInput>>(emptyList()) }
    var showingSongPicker by remember { mutableStateOf(false) }
    // 担当ブランドの設定の要約 (「メイン 765AS / 担当 シャニマス」)。
    var brandRoleSummary by remember { mutableStateOf("") }
    var showingBrandSettings by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    // 作り直した名刺 id (✓ で保存する。null は作り直していない)。
    var renewedCardId by remember { mutableStateOf<String?>(null) }
    var confirmRenewCardId by remember { mutableStateOf(false) }

    val designs = remember { cardDesigns() }
    var design by remember { mutableStateOf(cardDesignKey(card.cardDesign)) }
    val selectedDesign = designs.firstOrNull { it.key == design } ?: designs.first()
    var qrUrl by remember { mutableStateOf(card.qrUrl.orEmpty()) }
    var qrNotice by remember { mutableStateOf<String?>(null) }

    // 名刺の写真 (切り抜く前) と切り抜き。変えたら ✓ のときに書く。
    var photoSource by remember { mutableStateOf<Bitmap?>(null) }
    var crop by remember { mutableStateOf(ImasPortraitCrop()) }
    var photoDirty by remember { mutableStateOf(false) }
    // 写真を選び直した (元の写真も書き直す)。位置を直しただけなら元の写真は書き直さない。
    var photoSourceChanged by remember { mutableStateOf(false) }
    // 切り抜きを決めて見本を作っている間は保存させない (写真が書かれずに閉じないように)。
    var applyingCrop by remember { mutableStateOf(false) }
    var cropping by remember { mutableStateOf<CropDraft?>(null) }
    // 見本に出す切り抜き済みの写真 (✓ の前は一時ファイル)。
    var previewPortrait by remember { mutableStateOf<String?>(null) }
    // 名刺の写真の出どころ (X のアイコンは丸く出す。切り方はコアの `cardPhotoShape`)。
    var photoOrigin by remember { mutableStateOf(CardPhotoSource.PICKED) }
    var directory by remember { mutableStateOf(ProducerCardDirectory()) }

    // 自作の名刺の画像 (平らにした後)。変えた面だけ ✓ のときに書く (null は外した)。
    val faceImages = remember { mutableStateMapOf<ProducerCardFiles.Side, Bitmap>() }
    // 写真から選んだ元と見つけた四隅 (四隅を直すとき用。この編集で選んだ面だけ)。
    val faceSources = remember { mutableStateMapOf<ProducerCardFiles.Side, PaperPhotoSource>() }
    // 見本に出す画像 (保存済みのファイルか、✓ の前の一時ファイル)。
    val facePreview = remember { mutableStateMapOf<ProducerCardFiles.Side, String>() }
    val faceDirty = remember { mutableStateListOf<ProducerCardFiles.Side>() }
    var faceCorners by remember { mutableStateOf<FaceCornerDraft?>(null) }
    var faceNotice by remember { mutableStateOf<String?>(null) }
    var isReadingFace by remember { mutableStateOf(false) }
    var pickingFace by remember { mutableStateOf(ProducerCardFiles.Side.FRONT) }

    var isFetchingAvatar by remember { mutableStateOf(false) }
    var avatarNotice by remember { mutableStateOf<String?>(null) }
    // 取りに行っている X のアイコン (写真を選んだ・外したら取り消す。遅れて届いたアイコンで切り抜きを差し替えない)。
    var avatarJob by remember { mutableStateOf<Job?>(null) }

    fun cancelAvatar() {
        avatarJob?.cancel()
        avatarJob = null
        isFetchingAvatar = false
    }

    // アプリの担当すべてを引く (どの人を選んでも見本に出せるように)。
    LaunchedEffect(record) {
        val ids = record?.oshiIds.orEmpty()
        if (ids.isEmpty()) return@LaunchedEffect
        directory = ProducerCardDirectory.load(module, ids, emptyList())
        oshiIdols = directory.idols
    }
    // 先頭の担当の画像 (担当を大きく のデザインの札)。選び直したら引き直す。
    val leadId = oshi.firstOrNull()?.id
    LaunchedEffect(leadId) {
        leadImage = leadId?.let { id ->
            withContext(Dispatchers.IO) { module.customImageStore.primaryImageFile(id)?.let { Uri.fromFile(it).toString() } }
        }
    }
    LaunchedEffect(Unit) { favorites = FavoriteSongSource.load(module).map { it.input } }
    // 担当ブランドの設定が変わったら (設定の画面から戻った等) 要約を組み直す。
    val brandRolesJson by BrandRoleStore.json.collectAsState()
    LaunchedEffect(brandRolesJson) {
        val rows = BrandRoleStore.load(context, module).rows
        val main = rows.filter { it.role == BrandRole.MAIN }.map { it.label }
        val picked = rows.filter { it.role == BrandRole.OSHI }.map { it.label }
        brandRoleSummary = listOfNotNull(
            main.takeIf { it.isNotEmpty() }?.let { "メイン ${it.joinToString("・")}" },
            picked.takeIf { it.isNotEmpty() }?.let { "担当 ${it.joinToString("・")}" }
        ).joinToString(" / ").ifEmpty { "まだありません" }
    }
    LaunchedEffect(Unit) {
        if (photoDirty) return@LaunchedEffect
        withContext(Dispatchers.IO) {
            // 前に開いたときの見本の一時ファイルを片付ける。
            previewFolder(context).deleteRecursively()
            val source = ProducerCardFiles.decodeMyPhotoSource(context)
            val savedCrop = ProducerCardFiles.myPhotoCrop(context)
            val url = if (source == null) null else ProducerCardFiles.myPhotoUrl(context)
            val origin = ProducerCardFiles.myPhotoSource(context)
            withContext(Dispatchers.Main) {
                if (photoDirty) return@withContext
                photoSource = source
                photoOrigin = origin
                crop = savedCrop ?: ImasPortraitCrop()
                previewPortrait = url
            }
        }
    }
    LaunchedEffect(Unit) {
        if (faceDirty.isNotEmpty()) return@LaunchedEffect
        val saved = withContext(Dispatchers.IO) {
            faceFolder(context).deleteRecursively()
            ProducerCardFiles.Side.entries.associateWith { ProducerCardFiles.myFaceUrl(context, it) }
        }
        if (faceDirty.isNotEmpty()) return@LaunchedEffect
        saved.forEach { (side, url) -> if (url != null) facePreview[side] = url }
    }

    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        cancelAvatar()
        scope.launch {
            val image = PaperCardCodeReader.loadBitmap(context, uri)
            if (image == null) {
                error = "写真を読み込めませんでした。"
                return@launch
            }
            cropping = CropDraft(image, ImasPortraitCrop(), CardPhotoSource.PICKED)
        }
    }

    /** 写真に写った QR を読み、URL なら自分の QR に入れる (分け方はコア)。 */
    val pickQrPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        qrNotice = null
        scope.launch {
            val image = PaperCardCodeReader.loadBitmap(context, uri)
            if (image == null) {
                qrNotice = "写真を読み込めませんでした。"
                return@launch
            }
            val code = PhotoQRReader.firstCode(image)
            if (code == null) {
                qrNotice = "写真に QR が見つかりませんでした。"
                return@launch
            }
            when (val kind = classifyScannedCode(code)) {
                is ScannedCode.Link ->
                    if (normalizeCardQrUrl(kind.url) != null) qrUrl = kind.url
                    else qrNotice = "この QR の URL は自分の QR にできません。"
                is ScannedCode.Card -> qrNotice = "アプリの P名刺の QR です。交換用の QR は名刺に初めから入っています。"
                is ScannedCode.Text -> qrNotice = "URL の QR ではありません。"
            }
        }
    }

    /**
     * 画像に刷られた QR を読み、URL なら自分の QR に入れる (分け方はコア)。アプリの名刺の QR
     * (自分の交換用の QR) は名刺に初めから入っているので入れない。
     */
    suspend fun readFaceQr(image: Bitmap) {
        for (code in PaperCardCodeReader.codes(listOf(image))) {
            val link = classifyScannedCode(code) as? ScannedCode.Link ?: continue
            val normalized = normalizeCardQrUrl(link.url) ?: continue
            if (normalizeCardQrUrl(qrUrl) != normalized) {
                qrUrl = normalized
                faceNotice = "画像の QR (${cardQrLinkView(normalized).display}) を自分の QR に入れました。"
            }
            return
        }
    }

    /** 見本には一時ファイルで出し、✓ で端末に書く。 */
    suspend fun setFace(image: Bitmap, side: ProducerCardFiles.Side) {
        val url = withContext(Dispatchers.IO) {
            val jpeg = ProducerCardFiles.jpeg(image, maxPixels = 2000, quality = 90) ?: return@withContext null
            val dir = faceFolder(context).apply { mkdirs() }
            val file = File(dir, "${side.key}-${UUID.randomUUID()}.jpg")
            runCatching { file.writeBytes(jpeg) }.getOrNull() ?: return@withContext null
            Uri.fromFile(file).toString()
        } ?: return
        faceImages[side] = image
        facePreview[side] = url
        if (side !in faceDirty) faceDirty.add(side)
        readFaceQr(image)
    }

    /**
     * 写真から選んだ名刺の画像。紙の名刺を撮った写真なら四隅を見つけて平らにする (見つからなければ
     * 画像のまま)。画像の QR は自分の QR に入れる。
     */
    val pickFace = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val side = pickingFace
        faceNotice = null
        // 読み込みから保存させない (読み込み中に ✓ で閉じると、選んだ面が黙って書かれない)。
        isReadingFace = true
        scope.launch {
            try {
                val image = PaperCardCodeReader.loadBitmap(context, uri)
                if (image == null) {
                    faceNotice = "画像を読み込めませんでした。"
                    return@launch
                }
                val result = PaperCardRectifier.rectify(PaperCardRectifier.bounded(image))
                // 画面で作った画像は四隅が画像の縁なので見つからない。代わりに画像の中の小さな四角 (写真の枠など)
                // を拾うことがあるので、画像の半分に満たない四角では切り抜かない (四隅を直す で選び直せる)。
                val corners = result.corners?.takeIf { PaperCardCorners.area(it) >= 0.5f }
                faceSources[side] = PaperPhotoSource(result.original, corners)
                setFace(if (corners == null) result.original else result.image, side)
            } finally {
                isReadingFace = false
            }
        }
    }

    fun applyFaceCorners(side: ProducerCardFiles.Side, source: PaperPhotoSource, corners: List<Offset>) {
        isReadingFace = true
        scope.launch {
            try {
                val flat = withContext(Dispatchers.Default) { PaperCardRectifier.correct(source.original, corners) } ?: source.original
                faceSources[side] = PaperPhotoSource(source.original, corners)
                setFace(flat, side)
            } finally {
                isReadingFace = false
            }
        }
    }

    fun removeFace(side: ProducerCardFiles.Side) {
        faceImages.remove(side)
        faceSources.remove(side)
        facePreview.remove(side)
        if (side !in faceDirty) faceDirty.add(side)
    }

    /**
     * 名刺のリンクの X の ID からアイコンを取り、名刺の写真の枠に合わせる。取れなければ案内を出す
     * (写真から選ぶ形のまま)。
     */
    fun useXAvatar(handle: String) {
        avatarNotice = null
        isFetchingAvatar = true
        avatarJob?.cancel()
        avatarJob = scope.launch {
            val outcome = XAvatarFetcher.fetch(handle)
            isFetchingAvatar = false
            when (outcome) {
                is XAvatarFetcher.Outcome.Image -> cropping = CropDraft(outcome.bitmap, ImasPortraitCrop(), CardPhotoSource.X_ICON)
                is XAvatarFetcher.Outcome.Failed -> avatarNotice = outcome.message
            }
        }
    }

    /** 切り抜きを決めた。見本には一時ファイルで出し、✓ で端末に書く。 */
    fun applyCrop(image: Bitmap, result: ImasPortraitCrop, origin: CardPhotoSource) {
        avatarNotice = null
        applyingCrop = true
        scope.launch {
            val url = withContext(Dispatchers.IO) {
                val jpeg = result.render(image, ImasPortraitCrop.Frame.CARD)?.let { ProducerCardFiles.jpeg(it) } ?: return@withContext null
                val dir = previewFolder(context).apply { mkdirs() }
                val file = File(dir, "${UUID.randomUUID()}.jpg")
                runCatching { file.writeBytes(jpeg) }.getOrNull() ?: return@withContext null
                Uri.fromFile(file).toString()
            }
            applyingCrop = false
            if (url == null) {
                error = "写真を読み込めませんでした。"
                return@launch
            }
            if (image !== photoSource) photoSourceChanged = true
            photoSource = image
            photoOrigin = origin
            crop = result
            previewPortrait = url
            photoDirty = true
        }
    }

    fun removePhoto() {
        cancelAvatar()
        avatarNotice = null
        photoSource = null
        previewPortrait = null
        photoDirty = true
    }

    fun filled() = links.filter { it.value.isNotBlank() }
    fun draft(): MyProducerCard = card.copy(
        name = name.trim(),
        message = message.trim(),
        sinceYear = sinceYear
    ).withLinks(filled().mapNotNull { normalizeCardLink(CardLink(it.kind, it.value)) }).withHidden(hidden)
        .copy(design = design, qrUrl = normalizeCardQrUrl(qrUrl))
        .let { it.withProfile(it.profile.copy(songs = songs)) }
        .withCardOshiChoice(oshiChoice)
        .let { d -> renewedCardId?.let { d.copy(cardId = it) } ?: d }

    // 検査は名刺に載る中身 (担当・記録の数・書体も) で組んだ入力に、書きかけのリンクと QR の URL を
    // そのまま入れて渡す (載る中身を抜くと、QR に収まるかの見積もりが実物より短くなる)。
    val validation = validateProducerCard(
        ProducerCardAssembler.input(draft(), record ?: ProducerCardMyRecord(emptyList(), emptyList(), 0)).copy(
            name = name, message = message,
            links = filled().map { CardLink(it.kind, it.value) },
            qrUrl = qrUrl
        )
    )
    // 自作の画像のデザインは表の画像が要る (無いと入場証になってしまう)。画像の QR を読み終えるまで保存させない。
    val canSave = validation == null && !isSaving && !applyingCrop && !isReadingFace &&
        !(selectedDesign.usesFaceImage && facePreview[ProducerCardFiles.Side.FRONT] == null)
    val isDirty = name != card.name || message != card.message || sinceYear != card.sinceYear ||
        hidden != card.hidden || draft().linksJson != card.linksJson ||
        draft().cardDesign != card.cardDesign || draft().qrUrl != card.qrUrl || photoDirty || faceDirty.isNotEmpty() ||
        songs != card.profile.songs || oshiChoice != card.cardOshiChoice || renewedCardId != null
    val qrInvalid = qrUrl.isNotBlank() && normalizeCardQrUrl(qrUrl) == null

    // ✕・✓ と払う動きは、押した時点の判定で決める (下の関数は組み立てたときの値を抱えたまま
    // 渡り続けることがあり、書きかけでも確かめずに閉じていた)。
    val dirtyNow by rememberUpdatedState(isDirty)
    val validationNow by rememberUpdatedState(validation)

    fun cancel() {
        if (dirtyNow) confirmDiscard = true else onDismiss()
    }

    fun save() {
        val invalid = validationNow
        if (invalid != null) {
            error = producerCardInputErrorMessage(invalid)
            return
        }
        isSaving = true
        scope.launch {
            try {
                onSave(draft())
                // 名刺を保存できてから写真を書く (保存に失敗して編集をやめたとき、写真だけ変わらないように)。
                if (photoDirty) {
                    val source = photoSource
                    val result = crop
                    val origin = photoOrigin
                    withContext(Dispatchers.IO) {
                        if (source != null) ProducerCardFiles.saveMyPhoto(context, source, result, origin, writeSource = photoSourceChanged)
                        else ProducerCardFiles.deleteMyPhoto(context)
                    }
                }
                val faces = faceDirty.associateWith { faceImages[it] }
                withContext(Dispatchers.IO) {
                    faces.forEach { (side, image) ->
                        if (image != null) ProducerCardFiles.saveMyFace(context, image, side)
                        else ProducerCardFiles.deleteMyFace(context, side)
                    }
                }
                onDismiss()
            } catch (e: Exception) {
                error = "保存できませんでした。${e.message.orEmpty()}"
            } finally {
                isSaving = false
            }
        }
    }

    // 書きかけを指で払って消さない (iOS `interactiveDismissDisabled(isDirty)`)。
    // 判定の関数は同じものを渡し続ける (書き換わるたびに別の関数を渡すと、シートの状態が作り直されて
    // 開き直しや閉じる動きが途中で入る)。止めるのは閉じる動きだけ。
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = remember { { value: SheetValue -> value != SheetValue.Hidden || !dirtyNow } }
    )
    ModalBottomSheet(onDismissRequest = ::cancel, sheetState = sheetState, containerColor = DS.bg) {
        Box {
            // 見本は画面の上に固定する (下の欄は別にスクロールし、写真やリンクを足して見本の背が
            // 変わっても欄は動かない。実機で「操作するたびにレイアウトがずれる」と指摘された)。
            Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(canSave = canSave, isSaving = isSaving, onCancel = ::cancel, onSave = ::save),
                    title = if (card.name.isEmpty()) "P名刺を作る" else "P名刺を編集"
                )
                ImasPinnedPreview {
                    CardPreview(
                        draft(), record, directory, previewPortrait, photoOrigin,
                        facePreview[ProducerCardFiles.Side.FRONT]?.let { ProducerCardFace(it, facePreview[ProducerCardFiles.Side.BACK]) }
                    )
                }
                Column(
                    Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = DS.Space.screen)
                        .padding(bottom = DS.Space.section),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
                ) {
                    ImasFormCard {
                        ImasFormTextField(
                            label = "名前", imprint = "NAME", text = name, onTextChange = { name = it },
                            prompt = "ふがP",
                            error = if (name.length > limits.maxNameChars.toInt()) "${limits.maxNameChars}文字までです" else null,
                            isTitle = true
                        )
                        ImasFormTextArea(
                            label = "ひとこと", imprint = "MESSAGE", icon = null, text = message,
                            onTextChange = { message = it }, prompt = "現地派・ライブ皆勤目指してます",
                            limit = limits.maxMessageChars.toInt()
                        )
                        ImasFormField(label = "P歴の始まり", imprint = "SINCE") {
                            YearPicker(selected = sinceYear, onSelect = { sinceYear = it })
                        }
                    }

                    ImasFormCard {
                        ImasFormField(label = "名刺のデザイン", imprint = "DESIGN") {
                            val assets = context.assets
                            val frontFace = facePreview[ProducerCardFiles.Side.FRONT]
                            val options = remember(designs, frontFace, leadImage) {
                                designs.map {
                                    ImasCardDesignOption(it.key, it.label, designLook(it.design, frontFace, leadImage), ImasCardNameFonts.family(assets, it.font.fileStem))
                                }
                            }
                            val lead = oshi.firstOrNull()
                            ImasCardDesignPicker(
                                options = options, selection = design, onSelect = { design = it }, sample = name.trim(),
                                seed = lead?.color, brand = lead?.brandId
                            )
                        }
                        if (selectedDesign.usesFaceImage) {
                            ImasFormField(
                                label = "自作の画像", imprint = "FACE",
                                error = if (facePreview[ProducerCardFiles.Side.FRONT] == null) "表の画像を選んでください" else null
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.Top) {
                                        listOf(ProducerCardFiles.Side.FRONT to "表", ProducerCardFiles.Side.BACK to "裏 (なくてもよい)").forEach { (side, title) ->
                                            FaceSlot(
                                                title = title,
                                                preview = facePreview[side],
                                                canAdjust = faceSources[side] != null,
                                                onPick = {
                                                    pickingFace = side
                                                    pickFace.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                                },
                                                onAdjust = { faceSources[side]?.let { faceCorners = FaceCornerDraft(side, it) } },
                                                onRemove = { removeFace(side) },
                                                modifier = Modifier.weight(1f)
                                            )
                                        }
                                    }
                                    Text(
                                        "自分で作った名刺の画像がそのまま名刺の顔になります (91:55 の比が基本、違う比率でも切りません)。紙の名刺を撮った写真なら、四隅を見つけて平らにします。画像の QR は自分の QR に入ります。",
                                        style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color
                                    )
                                    faceNotice?.let { Text(it, style = ImasTextRole.NOTE.style, color = DS.ink) }
                                }
                            }
                        }
                    }

                    ImasFormCard {
                        ImasFormField(label = "名刺の写真", imprint = "PHOTO") {
                            val handle = cardXAvatarHandle(draft().links)
                            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.Top) {
                                previewPortrait?.let { ImasCardPortraitThumbnail(url = it, round = cardPhotoShape(photoOrigin) == CardPhotoShape.ROUND) }
                                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                    CardEditorAction(Icons.Filled.Photo, if (photoSource == null) "写真を選ぶ" else "写真を変える") {
                                        pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                    }
                                    if (handle != null) {
                                        CardEditorAction(
                                            Icons.Filled.AccountCircle,
                                            if (isFetchingAvatar) "X のアイコンを取っています…" else "X のアイコンを使う (@$handle)",
                                            enabled = !isFetchingAvatar
                                        ) { useXAvatar(handle) }
                                    }
                                    val source = photoSource
                                    if (source != null) {
                                        CardEditorAction(Icons.Filled.Crop, "位置を直す") { cropping = CropDraft(source, crop, photoOrigin) }
                                        CardEditorAction(Icons.Filled.RemoveCircleOutline, "写真を外す", tint = DS.danger, onClick = ::removePhoto)
                                    }
                                    val notice = avatarNotice
                                    if (notice != null) {
                                        Text(notice, style = ImasTextRole.NOTE.style, color = DS.danger)
                                    } else if (source == null) {
                                        Text("名前の横に正方形で載ります (X のアイコンは丸く)。担当の画像とは別です。", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
                                    }
                                }
                            }
                        }
                    }

                    ImasFormCard {
                        ImasFormField(label = "担当 · アプリから", imprint = "OSHI") {
                            if (oshi.isEmpty()) {
                                Text("アイドル詳細で「担当」を付けると、ここに入ります", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
                            } else {
                                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                    oshi.forEach { idol ->
                                        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                                            ImasAvatar(
                                                label = idol.shortName, seed = idol.color, brand = idol.brandId,
                                                size = DS.Size.avatarSmall, isPick = true, entityId = idol.id
                                            )
                                            Text(idol.name, style = ImasTextRole.ROW_TITLE.style, color = DS.ink)
                                        }
                                    }
                                    val byHand = producerCardOshiPicks(oshiChoice, oshiEntries).chosenByHand
                                    ImasNavRow(
                                        title = "名刺に載せる担当を選ぶ",
                                        subtitle = if (byHand) "選んだ ${oshi.size} 人 (この順に載ります)" else "おまかせ (ブランドごとに 1 人)",
                                        icon = Icons.Filled.RecentActors, subtitleLineLimit = 2
                                    ) { showingOshiPicker = true }
                                }
                            }
                        }
                        FieldToggle(ProducerCardField.OSHI, "担当を載せる", null, hidden) { hidden = it }
                        FieldToggle(ProducerCardField.BRAND_LABELS, "判子の下にブランド名を刷る", null, hidden) { hidden = it }
                    }

                    ImasFormCard {
                        ImasFormField(label = "リンク", imprint = "LINKS") {
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                                links.forEachIndexed { index, link ->
                                    val info = kinds.firstOrNull { it.kind == link.kind }
                                    LinkEditor(
                                        label = info?.label.orEmpty(),
                                        placeholder = info?.placeholder.orEmpty(),
                                        link = link,
                                        onChange = { links[index] = link.copy(value = it) },
                                        onRemove = { links.removeAll { it.id == link.id } }
                                    )
                                }
                                if (links.size < limits.maxLinks.toInt()) {
                                    AddLinkMenu(kinds.map { it.label to it.kind }) { kind -> links.add(EditableLink(kind = kind, value = "")) }
                                }
                            }
                        }
                        FieldToggle(ProducerCardField.LINKS, "リンクを載せる", null, hidden) { hidden = it }
                    }

                    ImasFormCard {
                        ImasFormField(
                            label = "自分の QR", imprint = "QR",
                            error = if (qrInvalid) producerCardInputErrorMessage(ProducerCardInputError.QR_URL_INVALID) else null
                        ) {
                            QrEditor(
                                value = qrUrl,
                                onChange = { qrUrl = it },
                                links = draft().links.map { cardLinkView(it) },
                                onReadPhoto = { pickQrPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                                notice = qrNotice
                            )
                        }
                    }

                    val summary = record?.summary
                    ImasFormCard {
                        FieldToggle(
                            ProducerCardField.SHOW_COUNT, "参加公演数",
                            summary?.let { "${ProducerCardDisplay.number(it.showCount.toLong())} 公演" }, hidden
                        ) { hidden = it }
                        FieldToggle(
                            ProducerCardField.SONG_COUNT, "回収曲数",
                            record?.let { "${ProducerCardDisplay.number(it.songCount.toLong())} 曲" }, hidden
                        ) { hidden = it }
                        FieldToggle(
                            ProducerCardField.NEXT, "次の現場",
                            if (summary?.nextShowId == null) "参加予定なし" else null, hidden
                        ) { hidden = it }
                        FieldToggle(ProducerCardField.ATTENDED, "参加した公演の一覧", "共通点を出すのに使う", hidden) { hidden = it }
                    }

                    // P名刺の画像に載るもの (名刺の QR には入らない)。
                    ImasFormCard {
                        ImasFormField(label = "好きな曲 · お気に入りから", imprint = "SONGS") {
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                ImasNavRow(
                                    title = "載せる曲を選ぶ", subtitle = songsSummary(songs, favorites),
                                    icon = Icons.AutoMirrored.Filled.QueueMusic, subtitleLineLimit = 2
                                ) { showingSongPicker = true }
                                Text(
                                    "好きな曲と担当ブランドは名刺の QR には入らず、SNS に貼る画像に載ります。",
                                    style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color
                                )
                            }
                        }
                        ImasFormField(label = "担当ブランド · アプリ全体の設定", imprint = "BRANDS") {
                            ImasNavRow(
                                title = "担当ブランドを選ぶ", subtitle = brandRoleSummary,
                                icon = Icons.Filled.RadioButtonChecked, subtitleLineLimit = 2
                            ) { showingBrandSettings = true }
                        }
                    }

                    val shownError = error ?: validation?.takeIf { it == ProducerCardInputError.TOO_LONG }?.let { producerCardInputErrorMessage(it) }
                    shownError?.let { Text(it, style = ImasTextRole.NOTE.style, color = DS.danger) }
                    if (producerCardEmbedsCardId()) {
                        CardIdCard(renewedCardId, onRenew = { confirmRenewCardId = true })
                        ImasNote("名刺には同じ人と分かる名刺 id が入るので、古い版のアプリでは読めません (相手にアプリを最新にしてもらうと読めます)。")
                    } else if (design != designs[0].key || qrUrl.trim().isNotEmpty()) {
                        ImasNote("デザインや自分の QR を載せた名刺は、古い版のアプリでは読めません (相手にアプリを最新にしてもらうと読めます)。")
                    }
                    ImasNote("名刺の中身は QR に全部入ります。サーバには何も置かないので、圏外の会場でも交換できます。後から名刺を直したら、もう一度交換すると相手の名刺入れの名刺も新しくなります。")
                }
            }
            ImasSavingOverlay(isSaving = isSaving || isReadingFace, label = if (isReadingFace) "画像を整えています" else "保存中")
        }
    }

    ImasDiscardConfirmation(isPresented = confirmDiscard, onDismiss = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDismiss()
    })
    ImasConfirmDestructive(
        title = "名刺 id を作り直しますか？",
        isPresented = confirmRenewCardId,
        onDismiss = { confirmRenewCardId = false },
        actionTitle = "作り直す",
        message = RENEW_CARD_ID_NOTE,
        onConfirm = { renewedCardId = producerCardNewId(UUID.randomUUID().toString()) }
    )
    faceCorners?.let { draft ->
        PaperCardCornerSheet(
            image = draft.source.original,
            initial = draft.source.corners ?: PaperCardRectifier.defaultCorners,
            onDone = { applyFaceCorners(draft.side, draft.source, it) },
            onDismiss = { faceCorners = null }
        )
    }
    if (showingSongPicker) {
        Dialog(
            onDismissRequest = { showingSongPicker = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            FavoriteSongPickerScreen(chosen = songs, onChange = { songs = it }, onBack = { showingSongPicker = false })
        }
    }
    if (showingOshiPicker) {
        Dialog(
            onDismissRequest = { showingOshiPicker = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            CardOshiPickerScreen(
                chosen = oshiChoice, oshi = oshiEntries, idols = oshiIdols,
                onChange = { oshiChoice = it }, onBack = { showingOshiPicker = false }
            )
        }
    }
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
            onDone = { applyCrop(draft.image, it, draft.origin) },
            onDismiss = { cropping = null },
            round = cardPhotoShape(draft.origin) == CardPhotoShape.ROUND
        )
    }
}

/** 切り抜きのシートに渡すもの。 */
private class CropDraft(val image: Bitmap, val crop: ImasPortraitCrop, val origin: CardPhotoSource)

/** 自作の名刺の画像の四隅を直すシートに渡すもの。 */
private class FaceCornerDraft(val side: ProducerCardFiles.Side, val source: PaperPhotoSource)

/** 見本に出す切り抜き済みの写真の一時置き場。 */
private fun previewFolder(context: Context): File = File(context.cacheDir, "producer_card_edit")

/** 自作の名刺の画像の一時置き場。 */
private fun faceFolder(context: Context): File = File(context.cacheDir, "producer_card_face_edit")

/** デザインの札に組む小さな名刺の形。 */
private fun designLook(design: CardDesign, frontFace: String?, leadImage: String?): ImasCardDesignOption.Look = when (design) {
    CardDesign.PASS -> ImasCardDesignOption.Look.Pass
    CardDesign.FORMAL -> ImasCardDesignOption.Look.Formal
    CardDesign.POP -> ImasCardDesignOption.Look.Pop
    CardDesign.OSHI -> ImasCardDesignOption.Look.Oshi(leadImage)
    CardDesign.CUSTOM -> ImasCardDesignOption.Look.Face(frontFace)
}

/** 選んだ曲の題 (まだ選んでいなければお気に入りの新しい順。並べ方はコア)。 */
private fun songsSummary(chosen: List<String>?, favorites: List<ProfileSongInput>): String {
    if (favorites.isEmpty()) return "お気に入りの曲がありません"
    val picks = favoriteSongPicks(chosen, favorites)
    val titles = picks.picked.joinToString("") { "「${it.title}」" }
    if (titles.isEmpty()) return "載せない"
    return if (picks.chosenByHand) titles else "おまかせ (お気に入りの新しい順)  $titles"
}

/** 自作の名刺の画像の 1 面 (表・裏) の欄。 */
@Composable
private fun FaceSlot(
    title: String,
    preview: String?,
    canAdjust: Boolean,
    onPick: () -> Unit,
    onAdjust: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Text(title, style = ImasTextRole.ROW_LABEL.style, color = DS.ink2)
        if (preview != null) ImasCardFace(front = preview, label = "自作の名刺の$title")
        CardEditorAction(Icons.Filled.PhotoLibrary, if (preview == null) "画像を選ぶ" else "選び直す", onClick = onPick)
        if (canAdjust) CardEditorAction(Icons.Filled.Crop, "四隅を直す", onClick = onAdjust)
        if (preview != null) CardEditorAction(Icons.Filled.RemoveCircleOutline, "外す", tint = DS.danger, onClick = onRemove)
    }
}

/**
 * 今の入力で組んだ名刺の表 (保存前でもその場で見た目に出す)。名刺は 91:55 の紙 1 枚なので、
 * 入力で背が変わらない (名刺の下の詳細は出さない・返さない)。
 */
@Composable
private fun CardPreview(
    draft: MyProducerCard,
    record: ProducerCardMyRecord?,
    directory: ProducerCardDirectory,
    portraitUrl: String?,
    portraitSource: CardPhotoSource,
    face: ProducerCardFace?
) {
    val rec = record ?: ProducerCardMyRecord(oshiIds = emptyList(), attended = emptyList(), songCount = 0)
    val sample = draft.copy(name = draft.name.ifEmpty { "名前" })
    val card = encodeProducerCard(ProducerCardAssembler.input(sample, rec)).card
    val content = rememberProducerCardContent(
        card = card, directory = directory, ownImages = true, portraitUrl = portraitUrl, portraitSource = portraitSource, face = face
    )
    ImasProducerCard(content, isFlippable = false, modifier = Modifier.semantics { contentDescription = "名刺の見本" })
}

/** 自分の QR の欄 (URL を打つ・名刺のリンクから選ぶ・写真の QR を読む)。 */
@Composable
private fun QrEditor(
    value: String,
    onChange: (String) -> Unit,
    links: List<CardLinkView>,
    onReadPhoto: () -> Unit,
    notice: String?
) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
            val ink = DS.ink
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = ImasTextRole.VALUE.style.copy(color = ink),
                cursorBrush = SolidColor(ink),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Uri
                ),
                modifier = Modifier.weight(1f),
                decorationBox = { inner ->
                    Box {
                        if (value.isEmpty()) Text("https://lit.link/…", style = ImasTextRole.VALUE.style, color = DS.ink3)
                        inner()
                    }
                }
            )
            if (value.isNotEmpty()) {
                ImasIconButton(
                    icon = Icons.Filled.RemoveCircleOutline,
                    label = "自分の QR を外す",
                    onClick = { onChange("") },
                    size = ImasIconButtonSize.SMALL,
                    style = ImasIconButtonStyle.PLAIN
                )
            }
        }
        if (links.isNotEmpty()) {
            var open by remember { mutableStateOf(false) }
            Box {
                CardEditorAction(Icons.Filled.Link, "名刺のリンクから選ぶ") { open = true }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    links.forEach { view ->
                        DropdownMenuItem(text = { Text("${view.label} ${view.display}") }, onClick = { open = false; onChange(view.url) })
                    }
                }
            }
        }
        CardEditorAction(Icons.Filled.QrCodeScanner, "写真の QR を読む", onClick = onReadPhoto)
        notice?.let { Text(it, style = ImasTextRole.NOTE.style, color = DS.danger) }
    }
}

/** 編集画面の小さな操作 (写真を選ぶ・位置を直す・リンクから選ぶ)。 */
@Composable
internal fun CardEditorAction(
    icon: ImageVector,
    title: String,
    tint: Color = DS.ink,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Row(
        if (enabled) Modifier.imasRowPress(onClick = onClick) else Modifier,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = tint)
        Text(title, style = ImasTextRole.ROW_LABEL.style, color = tint)
    }
}

/** 名刺の写真を枠に合わせるシート (iOS `CardPhotoCropSheet`)。引いて動かし、つまんで広げ、✓ で決める。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CardPhotoCropSheet(
    image: Bitmap,
    initial: ImasPortraitCrop,
    onDone: (ImasPortraitCrop) -> Unit,
    onDismiss: () -> Unit,
    /** 切り抜く枠 (P名刺は正方形)。 */
    frame: ImasPortraitCrop.Frame = ImasPortraitCrop.Frame.CARD,
    /** 丸く切る写真 (X のアイコン)。 */
    round: Boolean = false,
    note: String = "引いて動かし、2 本の指で広げると、名刺の写真の枠に合わせられます。写真は端末の中と、名刺ファイル・近くの Android で渡した相手にだけ届きます (QR には入りません)。"
) {
    var crop by remember { mutableStateOf(initial.clamped(image.width.toFloat(), image.height.toFloat(), frame)) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        // 写真を指で動かすので、引いてもシートが下がらないようにする (× で閉じる)。
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { it != SheetValue.Hidden }),
        containerColor = DS.bg
    ) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(
                ImasSheetToolbarKind.Edit(canSave = true, isSaving = false, onCancel = onDismiss, onSave = {
                    onDone(crop)
                    onDismiss()
                }),
                title = "写真の位置"
            )
            Column(
                Modifier.padding(horizontal = DS.Space.screen),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                ImasPortraitCropper(image = image, crop = crop, onCropChange = { crop = it }, frame = frame, round = round)
                ImasNote(note)
            }
        }
    }
}

@Composable
private fun FieldToggle(
    field: ProducerCardField,
    title: String,
    value: String?,
    hidden: Set<ProducerCardField>,
    onChange: (Set<ProducerCardField>) -> Unit
) {
    ImasFormToggle(
        label = value?.let { "${field.label} · $it" } ?: field.label,
        title = title,
        isOn = field !in hidden,
        onCheckedChange = { on -> onChange(if (on) hidden - field else hidden + field) }
    )
}

@Composable
private fun YearPicker(selected: Int?, onSelect: (Int?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val years = remember { (LocalDate.now().year.coerceAtLeast(2005) downTo 2005).toList() }
    Box {
        Text(
            selected?.let { "${it}年" } ?: "載せない",
            style = ImasTextRole.VALUE.style,
            color = DS.ink,
            modifier = Modifier.imasRowPress(onClick = { open = true })
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("載せない") }, onClick = { open = false; onSelect(null) })
            years.forEach { year ->
                DropdownMenuItem(text = { Text("${year}年") }, onClick = { open = false; onSelect(year) })
            }
        }
    }
}

@Composable
private fun AddLinkMenu(kinds: List<Pair<String, CardLinkKind>>, onAdd: (CardLinkKind) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.imasRowPress(onClick = { open = true }),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = DS.ink)
            Text("リンクを足す", style = ImasTextRole.ROW_LABEL.style, color = DS.ink)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            kinds.forEach { (label, kind) ->
                DropdownMenuItem(text = { Text(label) }, onClick = { open = false; onAdd(kind) })
            }
        }
    }
}

@Composable
private fun LinkEditor(
    label: String,
    placeholder: String,
    link: EditableLink,
    onChange: (String) -> Unit,
    onRemove: () -> Unit
) {
    val invalid = link.value.isNotBlank() && normalizeCardLink(CardLink(link.kind, link.value)) == null
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = ImasTextRole.VALUE.style, color = DS.ink2)
            val ink = DS.ink
            BasicTextField(
                value = link.value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = ImasTextRole.VALUE.style.copy(color = ink),
                cursorBrush = SolidColor(ink),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Uri
                ),
                modifier = Modifier.weight(1f),
                decorationBox = { inner ->
                    Box {
                        if (link.value.isEmpty()) Text(placeholder, style = ImasTextRole.VALUE.style, color = DS.ink3)
                        inner()
                    }
                }
            )
            ImasIconButton(
                icon = Icons.Filled.RemoveCircleOutline,
                label = "${label.ifEmpty { "リンク" }}を外す",
                onClick = onRemove,
                size = ImasIconButtonSize.SMALL,
                style = ImasIconButtonStyle.PLAIN
            )
        }
        if (invalid) Text("リンクの書き方を確かめてください", style = ImasTextRole.NOTE.style, color = DS.danger)
    }
}
