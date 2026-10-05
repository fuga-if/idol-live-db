package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Share
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
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasQRCode
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.cardQrLinkView

/**
 * 自分の P名刺。iOS `MyProducerCardView` の移植。担当の入場証を 1 枚に広げた紙に、担当・記録の数・リンクを載せる。
 *
 * 担当と記録の数はアプリの記録から毎回作る (名刺の表には名前・ひとこと・リンクだけ持つ)。
 * ここから「交換する」(QR を見せる / 読む)、名刺ファイルで送る、紙に刷る画像、名刺入れへ行く。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyProducerCardScreen(onBack: () -> Unit, onOpenCardCase: () -> Unit) {
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
    var shareError by remember { mutableStateOf<String?>(null) }
    var qrMode by remember { mutableStateOf(QrMode.EXCHANGE) }
    var portraitUrl by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        val repo = module.producerCardRepository
        myCard = repo.myCard()
        caseCount = repo.receivedCount()
        record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull() ?: record
        portraitUrl = withContext(Dispatchers.IO) { ProducerCardFiles.myPhotoUrl(context) }
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

    fun shareCardFile() {
        val enc = encoded ?: return
        scope.launch {
            val data = ProducerCardAssembler.myCardFile(context, module, enc)
            if (data == null) {
                shareError = "名刺の中身を組み立てられませんでした。"
                return@launch
            }
            runCatching { ProducerCardAssembler.writeShareFile(context, data, enc.card) }
                .onSuccess { ProducerCardAssembler.shareFile(context, it) }
                .onFailure { shareError = it.message ?: "名刺の中身を組み立てられませんでした。" }
        }
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
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                        ProducerCardView(
                            card = enc.card, directory = directory, ownImages = true, portraitUrl = portraitUrl,
                            onOpenLink = { link -> runCatching { uriHandler.openUri(link.url) } }
                        )
                        ImasButton(
                            title = "交換する", icon = Icons.Filled.QrCode, role = ImasButtonRole.PRIMARY,
                            size = ImasButtonSize.LARGE, fillsWidth = true, onClick = { showingExchange = true }
                        )
                        if (enc.droppedShows > 0u) {
                            ImasNote("QR に収めるため、古い参加公演 ${enc.droppedShows} 件を名刺から外しています。")
                        }
                    }
                    enc.card.qrUrl?.let { own -> QrSection(enc, own, qrMode) { qrMode = it } }
                    ImasSection("渡す・しまう") {
                        ImasCardList {
                            ImasNavRow(
                                title = "名刺ファイルで送る", subtitle = "AirDrop や Quick Share で写真と担当の画像ごと渡す",
                                icon = Icons.Filled.Share, position = ImasRowPosition.FIRST, onClick = ::shareCardFile
                            )
                            ImasNavRow(
                                title = "紙に刷る画像", subtitle = "91×55mm の名刺の表と裏を書き出す",
                                icon = Icons.Filled.Print, position = ImasRowPosition.FOLLOWING,
                                onClick = { showingPrint = true }
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
                module.producerCardRepository.saveMyCard(saved)
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
    ImasErrorAlert(message = shareError, onDismiss = { shareError = null }, title = "名刺ファイルを作れませんでした")
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
