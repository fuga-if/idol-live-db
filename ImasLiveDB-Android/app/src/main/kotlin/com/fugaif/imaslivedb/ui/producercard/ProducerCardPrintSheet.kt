package com.fugaif.imaslivedb.ui.producercard

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
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintBack
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintFront
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintPreview
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.cardIssuedLabel
import uniffi.imas_core.cardLinkView

/**
 * 紙に刷る P名刺の画像 (表と裏)。iOS `ProducerCardPrintView` の移植。91×55mm の比で、
 * 印刷所に入稿できる解像度 (1638×990px) で書き出す。裏の QR はアプリの交換と同じ中身。
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
                            handle = c.links.firstOrNull()?.let { cardLinkView(it).display }
                        )
                    }
                }
                ImasSection(
                    "裏",
                    style = ImasSectionHeaderStyle.SMALL,
                    footer = "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。"
                ) {
                    ProducerCardPrintPreview(back) {
                        ProducerCardPrintBack(
                            url = card.url,
                            showCount = c.showCount?.toLong(),
                            songCount = c.songCount?.toLong(),
                            issuedLabel = cardIssuedLabel(c.issuedOn)
                        )
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
