package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FlipToFront
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.data.producercard.StickerCutout
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishi
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiPicture
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiSticker
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCard
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardContent
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStickerEditLayer
import com.fugaif.imaslivedb.ui.designsystem.ImasStickerPreview
import com.fugaif.imaslivedb.ui.designsystem.ImasStickerThumb
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.designsystem.imasStickerFrame
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardSticker
import uniffi.imas_core.cardStickersBringToFront
import uniffi.imas_core.cardStickersMax
import uniffi.imas_core.cardStickersRemove
import uniffi.imas_core.cardStickersUpdate

/**
 * 編集の「素材」: 表に重ねる好きな画像 (背景を切り抜いた透過の画像も)。3 枚まで。iOS `stickerField` と対。
 *
 * @param images 見本に出す画像 (素材の id → 端末の画像か書きかけの一時ファイル)。
 * @param onPlace 「素材を置く」画面を開く。
 * @param onAdd 写真から素材を足す (写真の選び方は呼ぶ側)。
 */
@Composable
internal fun CardStickerField(
    stickers: List<CardSticker>,
    images: Map<String, String>,
    onPlace: () -> Unit,
    onAdd: () -> Unit
) {
    val max = remember { cardStickersMax().toInt() }
    ImasFormField(label = "素材", imprint = "STICKER") {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            if (stickers.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    stickers.forEach { s -> images[s.id]?.let { ImasStickerThumb(it) } }
                }
                ImasNavRow(
                    title = "素材を置く", subtitle = "名刺の上で動かす・大きさ・傾き・重なり",
                    icon = Icons.Filled.PanTool, onClick = onPlace
                )
            }
            if (stickers.size < max) {
                ImasNavRow(
                    title = "素材を足す", subtitle = "写真から選んで、背景を切り抜くこともできます",
                    icon = Icons.Filled.AddPhotoAlternate, showsChevron = false, subtitleLineLimit = 2, onClick = onAdd
                )
            } else {
                ImasNote("素材は $max 枚までです。")
            }
            ImasNote("素材は名刺ファイルと近くの端末で渡した相手に届きます。QR だけで受け取った人と Web では出ません。")
        }
    }
}

/**
 * 素材にする画像を整える (背景を切り抜くか選ぶ)。透過の PNG はそのまま使え、切り抜きは端末の中だけで行う
 * ([StickerCutout])。決めたら PNG を渡す。iOS `StickerPrepSheet` と対。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun StickerPrepSheet(image: Bitmap, onUse: (ByteArray) -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var cutout by remember { mutableStateOf<Bitmap?>(null) }
    var usesCutout by remember { mutableStateOf(false) }
    var isCutting by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    val shown = if (usesCutout) cutout ?: image else image

    suspend fun setCutout(on: Boolean) {
        notice = null
        if (!on) {
            usesCutout = false
            return
        }
        if (cutout == null) {
            isCutting = true
            try {
                cutout = StickerCutout.cutout(image)
            } catch (e: StickerCutout.Failure.NoSubject) {
                notice = "切り抜ける人や物が見つかりませんでした。写っているものがはっきりした画像で試してください。"
                return
            } catch (e: Exception) {
                notice = "この端末では切り抜けませんでした。"
                return
            } finally {
                isCutting = false
            }
        }
        usesCutout = true
    }

    fun use() {
        scope.launch {
            val png = withContext(Dispatchers.Default) { ProducerCardFiles.stickerPng(shown) }
            if (png == null) {
                notice = "画像を用意できませんでした。"
                return@launch
            }
            onUse(png)
            onDismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { it != SheetValue.Hidden || !isCutting }),
        containerColor = DS.bg
    ) {
        Box {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(canSave = !isCutting, onCancel = onDismiss, onSave = ::use),
                    title = "素材を足す"
                )
                Column(Modifier.padding(horizontal = DS.Space.screen), verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                    ImasFormCard {
                        ImasStickerPreview(
                            ImasMeishiPicture.Image(shown),
                            label = if (usesCutout) "背景を切り抜いた素材" else "素材"
                        )
                        ImasToggleRow(
                            title = "背景を切り抜く",
                            subtitle = "写っている人や物だけを残して、まわりを透明にします",
                            isOn = usesCutout,
                            onCheckedChange = { on -> scope.launch { setCutout(on) } },
                            subtitleLineLimit = 2
                        )
                        notice?.let { ImasNote(it, color = DS.ink) }
                        ImasNote("透明な部分のある画像 (PNG) はそのまま使えます。切り抜きは端末の中だけで行い、画像をどこにも送りません。")
                    }
                }
            }
            ImasSavingOverlay(isSaving = isCutting, label = "切り抜いています")
        }
    }
}

/**
 * 名刺の上で素材を指で置く画面。名刺を画面の幅いっぱいに出し、引いて動かす・つまんで大きさ・2 本指で傾ける。
 * 選んだ素材は「いちばん上に」「外す」ができる。範囲・並びの規則はコア (`cardStickerClamp` など)。
 * iOS `StickerPlacementView` と対。
 *
 * @param card 素材を重ねない名刺 (見本)。
 * @param images 素材の id → 画像の在り処。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun StickerPlacementScreen(
    card: ImasProducerCardContent,
    images: Map<String, String>,
    stickers: List<CardSticker>,
    onChange: (List<CardSticker>) -> Unit,
    onBack: () -> Unit
) {
    var selection by remember { mutableStateOf<String?>(null) }
    val views = remember(stickers, images) {
        stickers.mapNotNull { s -> images[s.id]?.let { ProducerCardDisplay.stickerView(s, ImasMeishiPicture.Url(it)) } }
    }
    val selected = selection

    Scaffold(
        containerColor = DS.bg,
        topBar = {
            TopAppBar(
                title = { Text("素材を置く") },
                actions = { ImasToolbarButton(Icons.Filled.Check, "置き終える", onClick = onBack) }
            )
        }
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(DS.Space.screen),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
        ) {
            Box(
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .widthIn(max = CARD_MAX_WIDTH)
                    .fillMaxWidth()
                    .aspectRatio(ImasMeishi.ASPECT)
                    // 紙の外にはみ出した分は名刺でも切れるので、置くときも同じに見せる。
                    .imasStickerFrame()
                    .clipToBounds()
            ) {
                ImasProducerCard(card, isFlippable = false)
                ImasStickerEditLayer(
                    stickers = views,
                    selection = selection,
                    onSelect = { selection = it },
                    onChange = { moved ->
                        val placed = CardSticker(
                            id = moved.id, x = moved.x.toDouble(), y = moved.y.toDouble(),
                            width = moved.width.toDouble(), rotationDegrees = moved.rotationDegrees.toDouble()
                        )
                        onChange(cardStickersUpdate(stickers, placed))
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
            ImasNote(
                if (selected == null) "素材を押して選び、引いて動かします。2 本指でつまむと大きさ、ひねると傾きが変わります。"
                else "2 本指でつまむと大きさ、ひねると傾きが変わります。何も無いところを押すと選び終わります。"
            )
            if (selected != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    ImasButton(
                        title = "いちばん上に", icon = Icons.Filled.FlipToFront, role = ImasButtonRole.SECONDARY,
                        onClick = { onChange(cardStickersBringToFront(stickers, selected)) }
                    )
                    ImasButton(
                        title = "外す", icon = Icons.Filled.Delete, role = ImasButtonRole.DESTRUCTIVE,
                        onClick = {
                            onChange(cardStickersRemove(stickers, selected))
                            selection = null
                        }
                    )
                }
            }
        }
    }
}

/** 名刺の幅の上限 (広い画面で紙が大きくなりすぎないように。`ImasProducerCard` と同じ)。 */
private val CARD_MAX_WIDTH = 480.dp
