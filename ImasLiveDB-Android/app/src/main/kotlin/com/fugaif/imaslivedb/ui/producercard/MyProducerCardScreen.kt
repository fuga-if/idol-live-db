package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.data.producercard.ProducerCardInbox
import com.fugaif.imaslivedb.data.producercard.ProducerCardMyRecord
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCard
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardBack
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardDetails
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasQRCode
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardDesign
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.cardQrLinkView
import uniffi.imas_core.cardIssuedLabel
import uniffi.imas_core.CardPhotoSource

/**
 * 自分の P名刺。iOS `MyProducerCardView` の移植。91:55 の名刺 1 枚と、名刺に収まらない詳細 (ひとこと・担当・リンク) を下に並べる。
 *
 * 名刺は交換するもの (誰で、どうつながれるか)。記録の数は名刺の下には出さず、裏 (紙の名刺の裏と同じ) と
 * SNS に貼る画像 (見せるもの) に載る。担当と記録の数はアプリの記録から毎回作る。
 * 出し方は 3 つ: 交換する (QR を見せる / 読む・名刺ファイル)・紙に刷る・SNS に貼る画像。それと名刺入れ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyProducerCardScreen(onBack: () -> Unit, onOpenCardCase: () -> Unit, onOpenImage: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()

    var myCard by remember { mutableStateOf<MyProducerCard?>(null) }
    var record by remember { mutableStateOf<ProducerCardMyRecord?>(null) }
    var encoded by remember { mutableStateOf<EncodedProducerCard?>(null) }
    var directory by remember { mutableStateOf(ProducerCardDirectory()) }
    var caseCount by remember { mutableIntStateOf(0) }
    var loaded by remember { mutableStateOf(false) }

    var editing by remember { mutableStateOf<MyProducerCard?>(null) }
    var showingExchange by remember { mutableStateOf(false) }
    var showingPrint by remember { mutableStateOf(false) }
    var qrMode by remember { mutableStateOf(QrMode.EXCHANGE) }
    var portraitUrl by remember { mutableStateOf<String?>(null) }
    var portraitSource by remember { mutableStateOf(CardPhotoSource.PICKED) }
    var face by remember { mutableStateOf<ProducerCardFace?>(null) }

    suspend fun load() {
        val repo = module.producerCardRepository
        myCard = repo.myCard()
        caseCount = repo.receivedCount()
        record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull() ?: record
        portraitUrl = withContext(Dispatchers.IO) {
            // 前の版のプロフィール帳だけの写真を片付ける (写真は P名刺の写真に一本化した)。
            ProducerCardFiles.removeLegacyProfileSheetPhoto(context)
            ProducerCardFiles.myPhotoUrl(context)
        }
        portraitSource = withContext(Dispatchers.IO) { ProducerCardFiles.myPhotoSource(context) }
        face = withContext(Dispatchers.IO) { ProducerCardDisplay.myFace(context) }
        val mine = myCard
        val rec = record
        val enc = if (mine != null && rec != null) ProducerCardAssembler.encode(mine, rec) else null
        encoded = enc
        if (enc != null) {
            directory = ProducerCardDirectory.load(module, enc.card.oshiIdolIds, listOfNotNull(enc.card.nextShowId))
        }
        loaded = true
    }

    // 担当・参加の記録は他の画面で変わるので、前面に来るたび組み直す。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { scope.launch { load() } }
    // 紙の名刺の書類カメラを電波のあるうちに入れておく (会場は圏外のことが多い)。
    LaunchedEffect(Unit) { prefetchPaperCardCamera(context) }
    LaunchedEffect(Unit) {
        ProducerCardInbox.changes.collect { caseCount = module.producerCardRepository.receivedCount() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("P名刺") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                },
                actions = {
                    if (encoded != null) {
                        IconButton(onClick = { editing = myCard ?: MyProducerCard.empty() }) {
                            Icon(Icons.Filled.Edit, contentDescription = "名刺を編集")
                        }
                    }
                }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            val enc = encoded
            when {
                !loaded -> ImasInlineLoading()
                enc != null -> {
                    // 名刺 1 枚。裏の QR は下の切り替え (交換用の QR / 自分の QR) と同じものを刷る。
                    val own = if (qrMode == QrMode.OWN) enc.card.qrUrl else null
                    val content = rememberProducerCardContent(
                        card = enc.card, directory = directory, ownImages = true, portraitUrl = portraitUrl,
                        portraitSource = portraitSource, face = face,
                        back = own?.let { ownQrBack(enc.card, it) }
                            ?: ImasProducerCardBack(
                                qr = enc.url, issuedLabel = cardIssuedLabel(enc.card.issuedOn),
                                showCount = enc.card.showCount?.toLong(), songCount = enc.card.songCount?.toLong()
                            ),
                        showsRecord = false
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                        ImasProducerCard(content)
                        if (enc.card.design == CardDesign.CUSTOM) {
                            ImasNote("自作の画像は名刺ファイルと近くの Android で渡した相手に届きます。QR だけで受け取った人と Web では入場証で見えます。")
                        }
                        if (enc.droppedShows > 0u) {
                            ImasNote("QR に収めるため、古い参加公演 ${enc.droppedShows} 件を名刺から外しています。")
                        }
                    }
                    ImasProducerCardDetails(content, onOpenLink = { link -> runCatching { uriHandler.openUri(link.url) } })
                    enc.card.qrUrl?.let { own -> QrSection(enc, own, qrMode) { qrMode = it } }
                    ImasSection("渡す・しまう") {
                        ImasCardList {
                            ImasNavRow(
                                title = "交換する", subtitle = "QR を見せる・読む。名刺ファイルでも送れる",
                                icon = Icons.Filled.QrCode, position = ImasRowPosition.FIRST,
                                onClick = { showingExchange = true }
                            )
                            ImasNavRow(
                                title = "紙に刷る", subtitle = "91×55mm の名刺の表と裏を画像で書き出す",
                                icon = Icons.Filled.Print, position = ImasRowPosition.FOLLOWING,
                                onClick = { showingPrint = true }
                            )
                            ImasNavRow(
                                title = "SNS に貼る画像", subtitle = "履歴書の様式で、担当・好きな曲・記録を 1 枚に",
                                icon = Icons.AutoMirrored.Filled.Article, position = ImasRowPosition.FOLLOWING,
                                onClick = onOpenImage
                            )
                            ImasNavRow(
                                title = "名刺入れ", subtitle = "受け取った名刺を公演ごとに",
                                icon = Icons.Filled.Inbox, value = "${caseCount}枚",
                                position = ImasRowPosition.FOLLOWING, onClick = onOpenCardCase
                            )
                        }
                    }
                }
                else -> ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.Badge,
                        title = "まだ P名刺がありません",
                        message = "名前とひとことを書くと、担当と参加の記録はアプリから自動で入ります。",
                        actionTitle = "名刺を作る",
                        onAction = { editing = myCard ?: MyProducerCard.empty() }
                    )
                }
            }
        }
    }

    editing?.let { card ->
        ProducerCardEditorSheet(
            card = card,
            record = record,
            onSave = { saved ->
                // 画像の選択 (大きさ・載せる項目) は画像の画面で書くので、開いた時の古い中身で戻さない
                // (読んで重ねて書くのはリポジトリが 1 本ずつ流す)。
                module.producerCardRepository.updateMyCard { latest -> saved.applyingEdit(latest) }
                load()
            },
            onDismiss = {
                editing = null
                // 名刺の写真は名刺を保存した後に書くので、閉じてから読み直す。
                scope.launch { load() }
            }
        )
    }
    if (showingExchange) {
        encoded?.let { ProducerCardExchangeSheet(myCard = it, onDismiss = { showingExchange = false }) }
    }
    if (showingPrint) {
        encoded?.let { ProducerCardPrintSheet(card = it, directory = directory, onDismiss = { showingPrint = false }) }
    }
}

/** 名刺の画面で見せる QR。自分の QR を載せていなければ交換用だけ。 */
private enum class QrMode { EXCHANGE, OWN }

/** 交換用の QR (アプリの名刺) と自分の QR を切り替えて見せる。 */
@Composable
private fun QrSection(encoded: EncodedProducerCard, own: String, mode: QrMode, onMode: (QrMode) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
        ImasTabs(
            options = QrMode.entries,
            selection = mode,
            onSelect = onMode,
            label = { if (it == QrMode.EXCHANGE) "交換用の QR" else "自分の QR" }
        )
        when (mode) {
            QrMode.EXCHANGE -> ImasQRCode(text = encoded.url, caption = "アプリで読むと名刺入れに入ります")
            QrMode.OWN -> ImasQRCode(text = own, caption = cardQrLinkView(own).display, label = "自分の QR コード")
        }
    }
}
