package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
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
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintImage
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintOshi
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintOshiGroup
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiLook
import com.fugaif.imaslivedb.di.AppModule
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.producerCardFace
import com.fugaif.imaslivedb.ui.share.ProducerCardPrintPreview
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.rememberCardNameFamily
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardDesign
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.cardQrLinkView

/**
 * 紙に刷る P名刺の画像 (表と裏)。iOS `ProducerCardPrintView` の移植。91×55mm の比で、
 * 印刷所に入稿できる解像度 (1638×990px) で書き出す。表は名刺のデザインの組み (自作の画像の名刺はその画像)。
 * 裏の QR は既定でアプリの交換と同じ中身、自分の QR を載せていればそちらも、自作の画像の裏があればその画像も選べる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProducerCardPrintSheet(card: EncodedProducerCard, directory: ProducerCardDirectory, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val front = rememberShareCardCapture()
    val backCapture = rememberShareCardCapture()
    var exporting by remember { mutableStateOf(false) }
    val c = card.card
    var back by remember { mutableStateOf(Back.EXCHANGE) }
    var materials by remember { mutableStateOf(ProducerCardPrintMaterials()) }
    LaunchedEffect(Unit) {
        materials = ProducerCardPrintMaterials.loadMine(context, AppModule.from(context), c)
        if (materials.faceBack != null) back = Back.FACE_BACK
    }
    val faceFront = materials.faceFront
    val faceBack = materials.faceBack
    // 表の組み (載せる担当・畳む数・ハンドルはコア)。
    val face = remember(c, directory) { producerCardFace(c, directory.oshiEntries(c.oshiIdolIds)) }
    val nameFamily = rememberCardNameFamily(ProducerCardDisplay.nameFont(c))
    val look = when (ProducerCardDisplay.design(c, null).design) {
        CardDesign.FORMAL -> ImasMeishiLook.FORMAL
        CardDesign.POP -> ImasMeishiLook.POP
        CardDesign.OSHI -> ImasMeishiLook.OSHI
        CardDesign.PASS, CardDesign.CUSTOM -> ImasMeishiLook.PASS
    }
    val backOptions = listOfNotNull(Back.FACE_BACK.takeIf { faceBack != null }, Back.EXCHANGE, Back.OWN.takeIf { c.qrUrl != null })
    // 裏の QR の中身と案内。
    val own = if (back == Back.OWN) c.qrUrl else null
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
                        val image = faceFront
                        if (image != null) {
                            ProducerCardPrintImage(image)
                        } else ProducerCardPrintFront(
                            name = c.name,
                            look = look,
                            sinceImprint = face.sinceImprint,
                            groups = face.oshiGroups.map { group ->
                                ProducerCardPrintOshiGroup(group.brandLabel, group.idolIds.mapNotNull { id ->
                                    directory.idols[id]?.let {
                                        ProducerCardPrintOshi(id, it.name, it.shortName, it.color, materials.oshiImages[id])
                                    }
                                })
                            },
                            hero = face.heroIdolIds.mapNotNull { id ->
                                directory.idols[id]?.let {
                                    ProducerCardPrintOshi(id, it.name, it.shortName, it.color, materials.oshiImages[id])
                                }
                            },
                            caption = face.oshiCaption,
                            moreOshi = face.moreOshi.toInt(),
                            // 担当の色は画面の名刺と同じく、描ける先頭の担当の色。
                            seed = face.oshiGroups.firstOrNull()?.idolIds?.firstOrNull()?.let { directory.idols[it]?.color },
                            handle = face.handle?.display,
                            nameFamily = nameFamily,
                            portrait = materials.portrait,
                            portraitRound = materials.portraitRound
                        )
                    }
                }
                ImasSection(
                    "裏",
                    style = ImasSectionHeaderStyle.SMALL,
                    footer = "日付を刷るのは、記録の数がその時点のものだからです。書き出した画像はそのまま名刺の印刷に使えます (1638×990px)。"
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                        if (backOptions.size > 1) {
                            ImasSegmented(
                                options = backOptions,
                                selection = back,
                                onSelect = { back = it },
                                label = {
                                    when (it) {
                                        Back.FACE_BACK -> "自作の裏"
                                        Back.EXCHANGE -> "交換用の QR"
                                        Back.OWN -> "自分の QR"
                                    }
                                }
                            )
                        }
                        ProducerCardPrintPreview(backCapture) {
                            val image = faceBack
                            if (back == Back.FACE_BACK && image != null) {
                                ProducerCardPrintImage(image)
                            } else ProducerCardPrintBack(
                                url = backText,
                                note = backNote,
                                showCount = c.showCount?.toLong(),
                                songCount = c.songCount?.toLong(),
                                issuedLabel = face.issuedLabel
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
                            val images = listOfNotNull(front.toBitmap(), backCapture.toBitmap())
                            if (images.isNotEmpty()) ShareCardFiles.shareAll(context, images, "producer_card")
                            exporting = false
                        }
                    }
                )
            }
        }
    }
}

/**
 * 紙に刷る画像に焼く、読み込み済みの画像。iOS `ProducerCardPrintMaterials`。焼くのは今描かれているものだけで
 * 読み込みを待たないので、書き出す前に全部 Bitmap に読んでおく (URL のまま渡すと担当の写真が焼かれない)。
 */
data class ProducerCardPrintMaterials(
    val portrait: Bitmap? = null,
    /** 名刺の写真を丸く切る (X のアイコン。切り方はコアの `cardPhotoShape`)。 */
    val portraitRound: Boolean = false,
    val faceFront: Bitmap? = null,
    val faceBack: Bitmap? = null,
    /** 担当の写真 (アイドルの id → 画像)。 */
    val oshiImages: Map<String, Bitmap> = emptyMap()
) {
    companion object {
        /** 自分の名刺の画像 (名刺の写真・担当の代表画像・自作の画像) を読む。大きな写真を丸ごと読まない。 */
        suspend fun loadMine(context: android.content.Context, module: AppModule, card: ProducerCard): ProducerCardPrintMaterials =
            withContext(Dispatchers.IO) {
                val face = ProducerCardDisplay.myFace(context)
                val design = ProducerCardDisplay.design(card, face)
                val usesFace = design.usesFaceImage
                // 担当を大きく は左半分いっぱいに刷るので、担当の画像を大きく読む (紙の 1638×990px の半分に足りる大きさ)。
                val oshiPixels = if (design.design == CardDesign.OSHI) 1600 else 600
                ProducerCardPrintMaterials(
                    portrait = ProducerCardFiles.myPhotoFile(context)?.let { ProducerCardFiles.decodeBounded(it, 900) },
                    portraitRound = ProducerCardFiles.myPhotoRound(context),
                    faceFront = if (usesFace) ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.FRONT)?.let { ProducerCardFiles.decodeBounded(it, 2000) } else null,
                    faceBack = if (usesFace) ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.BACK)?.let { ProducerCardFiles.decodeBounded(it, 2000) } else null,
                    oshiImages = card.oshiIdolIds.mapNotNull { id ->
                        module.customImageStore.primaryImageFile(id)?.let { ProducerCardFiles.decodeBounded(it, oshiPixels) }?.let { id to it }
                    }.toMap()
                )
            }
    }
}

/** 裏に刷るもの (既定は交換用の QR。自作の画像の裏があればそれ)。 */
private enum class Back { FACE_BACK, EXCHANGE, OWN }
