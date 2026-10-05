package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintBack
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintFront
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintPreview
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.rememberCardNameFamily
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.cardIssuedLabel
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.cardQrLinkView

/**
 * 紙に刷る P名刺の画像 (表と裏)。iOS `ProducerCardPrintView` の移植。91×55mm の比で、
 * 印刷所に入稿できる解像度 (1638×990px) で書き出す。表は選んだ書体の名前と名刺の写真。
 * 裏の QR は既定でアプリの交換と同じ中身、自分の QR を載せていればそちらも選べる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProducerCardPrintSheet(card: EncodedProducerCard, directory: ProducerCardDirectory, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val front = rememberShareCardCapture()
    val back = rememberShareCardCapture()
    var exporting by remember { mutableStateOf(false) }
    val c = card.card
    val oshiNames = c.oshiIdolIds.mapNotNull { directory.idols[it]?.name }
    var backQr by remember { mutableStateOf(BackQr.EXCHANGE) }
    var portrait by remember { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(Unit) {
        portrait = withContext(Dispatchers.IO) {
            ProducerCardFiles.myPhotoFile(context)?.let { runCatching { BitmapFactory.decodeFile(it.path) }.getOrNull() }
        }
    }
    val nameFamily = rememberCardNameFamily(ProducerCardDisplay.nameFont(c))
    // 裏の QR の中身と案内。
    val own = if (backQr == BackQr.OWN) c.qrUrl else null
    val backText = own ?: card.url
    val backNote = own?.let { "読み取ると ${cardQrLinkView(it).display} が開きます。" }
        ?: "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。"

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "紙に刷る")
            Column(
                Modifier.padding(horizontal = DS.Space.screen),
                verticalArrangement = Arrangement.spacedBy(DS.Space.section)
            ) {
                ImasSection("表", style = ImasSectionHeaderStyle.SMALL) {
                    ProducerCardPrintPreview(front) {
                        ProducerCardPrintFront(
                            name = c.name,
                            sinceYear = c.sinceYear?.toInt(),
                            oshiNames = oshiNames,
                            seed = c.oshiIdolIds.firstOrNull()?.let { directory.idols[it]?.color },
                            handle = c.links.firstOrNull()?.let { cardLinkView(it).display },
                            nameFamily = nameFamily,
                            portrait = portrait
                        )
                    }
                }
                ImasSection(
                    "裏",
                    style = ImasSectionHeaderStyle.SMALL,
                    footer = "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。"
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                        if (c.qrUrl != null) {
                            ImasSegmented(
                                options = BackQr.entries,
                                selection = backQr,
                                onSelect = { backQr = it },
                                label = { if (it == BackQr.EXCHANGE) "交換用の QR" else "自分の QR" }
                            )
                        }
                        ProducerCardPrintPreview(back) {
                            ProducerCardPrintBack(
                                url = backText,
                                note = backNote,
                                showCount = c.showCount?.toLong(),
                                songCount = c.songCount?.toLong(),
                                issuedLabel = cardIssuedLabel(c.issuedOn)
                            )
                        }
                    }
                }
                ImasButton(
                    title = "画像を書き出す", icon = Icons.Filled.Share, role = ImasButtonRole.PRIMARY,
                    size = ImasButtonSize.LARGE, fillsWidth = true, isLoading = exporting,
                    onClick = {
                        exporting = true
                        scope.launch {
                            val images = listOfNotNull(front.toBitmap(), back.toBitmap())
                            if (images.isNotEmpty()) ShareCardFiles.shareAll(context, images, "producer_card")
                            exporting = false
                        }
                    }
                )
            }
        }
    }
}

/** 裏に刷る QR (既定は交換用)。 */
private enum class BackQr { EXCHANGE, OWN }
