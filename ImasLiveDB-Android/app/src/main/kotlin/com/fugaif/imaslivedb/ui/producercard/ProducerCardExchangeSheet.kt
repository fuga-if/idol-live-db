package com.fugaif.imaslivedb.ui.producercard

import uniffi.imas_core.CardReceiveVia
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.producercard.IncomingProducerCard
import com.fugaif.imaslivedb.data.producercard.NearbyCardExchange
import com.fugaif.imaslivedb.data.producercard.NearbyCardPermissions
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardInbox
import com.fugaif.imaslivedb.data.producercard.ProducerCardIncoming
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasCameraFrame
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasQRCode
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlinx.coroutines.launch
import uniffi.imas_core.CardFileContents
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.ScannedCode
import uniffi.imas_core.classifyScannedCode

/**
 * 名刺交換。「見せる / 読む」の 2 択だけ。見せる側からは名刺ファイル (Quick Share 等) でも送れる。
 * iOS `ProducerCardExchangeView` の移植。
 *
 * - 見せる: 自分の名刺の QR を明るい画面で出し、近くの Android に名乗る (読んだ相手に担当の画像を送り、
 *   相手の名刺を受け取る)。
 * - 読む: 相手の QR をカメラで読み、受け取りの確認へ。近くに相手の Android がいれば担当の画像も届き、
 *   自分の名刺を送り返す (1 回のスキャンで双方向)。見つからなければ QR の中身だけで保存できる。
 *
 * @param myCard 自分の名刺。まだ作っていなければ null (読むだけはできる。相手には送り返さない)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProducerCardExchangeSheet(
    myCard: EncodedProducerCard?,
    onDismiss: () -> Unit,
    initialRead: Boolean = false
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()
    val haptics = rememberImasHaptics()
    val nearby = remember { NearbyCardExchange(context) }

    var reading by remember { mutableStateOf(initialRead) }
    var myFile by remember { mutableStateOf<ByteArray?>(null) }
    var path by remember { mutableStateOf<IncomingProducerCard?>(null) }
    var scanNotice by remember { mutableStateOf<String?>(null) }
    var lastReceived by remember { mutableStateOf<String?>(null) }
    var savedNotice by remember { mutableStateOf<String?>(null) }
    /** 確認で ✓ を押した名刺 (中身 → 名刺入れの id)。✓ の後に近くの相手から画像が届いたら足す。 */
    val savedIds = remember { mutableStateMapOf<String, String>() }
    var cameraPermitted by remember { mutableStateOf(cardCameraPermitted(context)) }
    var permissionsAsked by remember { mutableStateOf(false) }
    var applied by remember { mutableStateOf(0) }
    var shareError by remember { mutableStateOf<String?>(null) }

    /** 名刺ファイル (名刺 + 写真 + 担当の画像) を共有シートで送る。 */
    fun shareCardFile(card: EncodedProducerCard) {
        scope.launch {
            val data = myFile ?: ProducerCardAssembler.myCardFile(context, module, card)
            if (data == null) {
                shareError = "名刺の中身を組み立てられませんでした。"
                return@launch
            }
            runCatching { ProducerCardAssembler.writeShareFile(context, data, card.card) }
                .onSuccess { ProducerCardAssembler.shareFile(context, it) }
                .onFailure { shareError = it.message ?: "名刺の中身を組み立てられませんでした。" }
        }
    }

    /** 読んだ相手が送り返してきた名刺を名刺入れへ (受け取った公演は今日の参加公演)。 */
    suspend fun storeFromReader(contents: CardFileContents) {
        val record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
        val showId = record?.let { ProducerCardInbox.exchangeShowCandidates(it).firstOrNull() }
        val infos = runCatching { module.producerCardRepository.showInfos(listOfNotNull(showId)) }.getOrDefault(emptyMap())
        runCatching {
            ProducerCardInbox.store(context, contents.payload, contents.images, ReceivedProducerCard.Source.APP, CardReceiveVia.NEARBY, showId?.let { infos[it] })
        }.getOrNull() ?: return
        lastReceived = contents.card.name
        haptics.impactMedium()
    }

    fun apply() {
        nearby.stop()
        val activity = context.findActivity()
        if (!reading) {
            val card = myCard ?: return
            activity?.raiseBrightness()
            val file = myFile ?: return
            nearby.onReceive = { contents -> scope.launch { storeFromReader(contents) } }
            nearby.startShowing(ProducerCardAssembler.payload(card), file)
        } else {
            activity?.restoreBrightness()
        }
    }

    /** 権限を求めている最中 (結果が返るまで次を出さない)。 */
    var requesting by remember { mutableStateOf(false) }
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        requesting = false
        cameraPermitted = cardCameraPermitted(context)
        applied++
    }

    // カメラの権限は「読む」を開いたときに求める。権限の要求は同時に 2 つ出すと後の方が黙って捨てられるので、
    // 開いたときの要求 (近くの端末・「読む」で開いたならカメラも) を 1 回にまとめ、終わってから次を出す。
    var cameraAsked by remember { mutableStateOf(false) }
    fun needsCamera() = reading && !cameraPermitted && !cameraAsked && cardCameraAvailable(context)
    LaunchedEffect(Unit) {
        // 近くの端末に渡すための権限は開いたときに 1 回だけ求める (断られても QR だけで交換できる)。
        val wanted = buildList {
            if (!NearbyCardPermissions.granted(context)) addAll(NearbyCardPermissions.required())
            if (needsCamera()) {
                cameraAsked = true
                add(Manifest.permission.CAMERA)
            }
        }
        if (wanted.isNotEmpty() && !permissionsAsked) {
            permissionsAsked = true
            requesting = true
            permissions.launch(wanted.toTypedArray())
        } else {
            permissionsAsked = true
            applied++
        }
        myFile = myCard?.let { ProducerCardAssembler.myCardFile(context, module, it) }
        applied++
    }
    LaunchedEffect(reading, applied, requesting) {
        // 開いたときの要求が終わってから。
        if (applied > 0 && !requesting && needsCamera()) {
            cameraAsked = true
            requesting = true
            permissions.launch(arrayOf(Manifest.permission.CAMERA))
        }
    }
    LaunchedEffect(reading, applied) { if (applied > 0) apply() }

    DisposableEffect(Unit) {
        ProducerCardIncoming.exchangeOpenCount.incrementAndGet()
        onDispose {
            ProducerCardIncoming.exchangeOpenCount.decrementAndGet()
            nearby.close()
            context.findActivity()?.restoreBrightness()
        }
    }
    // 開いている間に届いた名刺のリンク・名刺ファイルは、この画面の中で受け取る。
    LaunchedEffect(Unit) {
        ProducerCardIncoming.toExchange.collect { path = it }
    }

    /**
     * 最後に読んだ中身。確認を閉じるとスキャナが作り直されるので、カメラが向いたままの同じ QR を
     * すぐ読み直して、始めたばかりの受け渡しを止めないように、ここで覚えておく (iOS は読み取り側が覚える)。
     */
    var lastScan by remember { mutableStateOf<String?>(null) }

    fun handleScan(text: String) {
        if (path != null || text == lastScan) return
        lastScan = text
        when (val code = classifyScannedCode(text)) {
            is ScannedCode.Card -> {
                scanNotice = null
                savedNotice = null
                nearby.startReading(code.payload, myFile)
                // ✓ の後に届いた画像は、しまった名刺に足す (✓ の前は確認の画面が受け取る)。
                nearby.onReceive = { contents ->
                    savedIds[contents.payload]?.let { id ->
                        scope.launch { ProducerCardInbox.attachImages(context, id, contents.images) }
                    }
                }
                path = IncomingProducerCard(code.payload, emptyList(), CardReceiveVia.CAMERA_QR)
            }
            is ScannedCode.Link ->
                scanNotice = "P名刺の QR ではありません。紙の名刺に刷られた QR は、名刺入れの「紙の名刺を取り込む」から読めます。"
            is ScannedCode.Text -> scanNotice = "P名刺の QR ではありません。"
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        val incoming = path
        if (incoming != null) {
            ProducerCardReceiveContent(
                incoming = incoming,
                nearby = if (incoming.via == CardReceiveVia.CAMERA_QR) nearby else null
            ) { saved ->
                if (saved != null) {
                    savedNotice = "${saved.first}さんの名刺を名刺入れに入れました"
                    // 近くの相手との受け渡しは、画像が届くか待ち時間が過ぎるまで続ける。
                    savedIds[incoming.payload] = saved.second
                    nearby.allowSending()
                } else if (incoming.via == CardReceiveVia.CAMERA_QR) {
                    nearby.stop()
                }
                path = null
            }
            return@ModalBottomSheet
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "名刺交換")
            Column(
                Modifier.padding(horizontal = DS.Space.screen),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                ImasTabs(labels = listOf("見せる", "読む"), selection = if (reading) 1 else 0, onSelect = { reading = it == 1 })
                if (!reading) {
                    ShowSection(myCard, lastReceived, onShareFile = ::shareCardFile)
                } else {
                    ReadSection(
                        cameraAvailable = cardCameraAvailable(context),
                        cameraPermitted = cameraPermitted,
                        onRequestCamera = { permissions.launch(arrayOf(Manifest.permission.CAMERA)) },
                        scanNotice = scanNotice,
                        savedNotice = savedNotice,
                        onScan = ::handleScan
                    )
                }
            }
        }
    }
    ImasErrorAlert(message = shareError, onDismiss = { shareError = null }, title = "名刺ファイルを作れませんでした")
}

@Composable
private fun ShowSection(myCard: EncodedProducerCard?, lastReceived: String?, onShareFile: (EncodedProducerCard) -> Unit) {
    if (myCard == null) {
        ImasCard {
            ImasEmptyState(
                icon = Icons.Filled.Badge,
                title = "まだ P名刺がありません",
                message = "プロデュースの「P名刺」から作ると、ここで QR を見せられます。"
            )
        }
        return
    }
    ImasQRCode(text = myCard.url, caption = caption(myCard))
    if (lastReceived != null) {
        ImasNotice(kind = ImasNoticeKind.SUCCESS, title = "${lastReceived}さんの名刺を受け取りました", message = "名刺入れに入れました。")
    }
    ImasNote("相手のアプリで読むと、近くの Android どうしなら担当の画像も元の画質のまま届き、相手の名刺も受け取れます。アプリが無い人がカメラで読むと、Web の名刺ページが開きます。")
    ImasCardList {
        ImasNavRow(
            title = "名刺ファイルで送る", subtitle = "AirDrop や Quick Share で写真と担当の画像ごと渡す",
            icon = Icons.Filled.Share, position = ImasRowPosition.FIRST, onClick = { onShareFile(myCard) }
        )
    }
}

private fun caption(myCard: EncodedProducerCard): String {
    val parts = mutableListOf(myCard.card.name)
    if (myCard.card.oshiIdolIds.isNotEmpty()) parts += "担当 ${myCard.card.oshiIdolIds.size}"
    myCard.card.showCount?.let { parts += "${ProducerCardDisplay.number(it.toLong())} 公演" }
    return parts.joinToString(" · ")
}

@Composable
private fun ReadSection(
    cameraAvailable: Boolean,
    cameraPermitted: Boolean,
    onRequestCamera: () -> Unit,
    scanNotice: String?,
    savedNotice: String?,
    onScan: (String) -> Unit
) {
    if (cameraAvailable && cameraPermitted) {
        ImasCameraFrame { CardQRScanner(onScan = onScan) }
        ImasNote("相手の P名刺の QR を枠に入れてください。")
    } else {
        ImasCard {
            ImasEmptyState(
                icon = Icons.Filled.PhotoCamera,
                title = "この端末ではカメラで読めません",
                message = "相手に「名刺ファイルで送る」で送ってもらうか、カメラアプリで QR を読むと、受け取りの確認が開きます。",
                actionTitle = if (cameraAvailable) "カメラを許可する" else null,
                onAction = if (cameraAvailable) onRequestCamera else null
            )
        }
    }
    scanNotice?.let { ImasNotice(kind = ImasNoticeKind.INFO, title = it, message = null) }
    savedNotice?.let { ImasNotice(kind = ImasNoticeKind.SUCCESS, title = it, message = null) }
}

// ---- 画面の明るさ (QR を読みやすく) ----

private var previousBrightness: Float? = null

private fun Activity.raiseBrightness() {
    if (previousBrightness != null) return
    val attrs = window.attributes
    previousBrightness = attrs.screenBrightness
    attrs.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
    window.attributes = attrs
}

private fun Activity.restoreBrightness() {
    val previous = previousBrightness ?: return
    val attrs = window.attributes
    attrs.screenBrightness = previous
    window.attributes = attrs
    previousBrightness = null
}

internal fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}
