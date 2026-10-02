package com.fugaif.imaslivedb.ui.share

import android.graphics.Bitmap
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasFitText
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlinx.coroutines.launch

// =============================================================================
// シェアカード共通基盤  ※ 公式トンマナ準拠 (編集的・プレミアム・洗練)
// iOS ImasLiveDB/Views/Share/ShareCardScaffold.swift の移植。
// -----------------------------------------------------------------------------
// アートディレクション (グラデを使わない):
// - 背景は「単色」。写真カードは near-black、写真なしカードも near-black。
// - 写真カードは「上にジャケ写フルブリード / 下にソリッド黒パネル」のハードエッジな
//   カラーブロック分割。継ぎ目に細いメンバーカラー罫線 1 本 (差し色)。
// - メンバーカラーは差し色 1 点 (細ライン・小四角・ドット) のみ。背景全体は染めない。
// - タイトルは明朝 (FontFamily.Serif) で上品・編集的に。英字キャプスは字間広め。
// - 大きな幾何学透かしを淡く 1 つ。
//
// 版権上、キャラ絵・歌詞・公式ロゴは一切含めない。
// ジャケット写真は Apple Music 由来 artwork (songs.artwork_url) のみ焼き込む。
//
// 焼いた画像にはライト/ダークの概念が無い (どの端末で開かれるか分からない) ので、
// カード内では DS の動的色ではなく固定色 ([ShareInk]) を使う。
// 差し色だけはエンティティ由来なので ImasTheme (共有コアの色エンジン) から導出する。
// =============================================================================

/** シェアカード共通の固定色。near-black / off-white をベースに置く。 */
object ShareInk {
    /** 写真カード下部パネル / ダーク背景カードのソリッド地色。 */
    val nearBlack = Color(0xFF0E0E12)

    /** 明色背景カードのソリッド地色。 */
    val offWhite = Color(0xFFFAFAF8)

    /** near-black 地の上の主インク。 */
    val ink = Color.White
    val ink2 = Color.White.copy(alpha = 0.66f)
    val ink3 = Color.White.copy(alpha = 0.40f)
}

/**
 * シェアカード専用パレット。seed からメンバーカラー (差し色) を導き、
 * 残りは near-black の固定編集色で構成する (多色グラデは持たない)。
 *
 * 色そのものの導出規則は共有コア (imas-core の color_engine) が正本なので、
 * ここで hex を計算し直したりはしない。ダークのトークンをそのまま借りる。
 */
@Immutable
data class ShareCardPalette(
    /** メンバーカラー (差し色)。罫線・小四角・ドット・プログレスにのみ使う。 */
    val accent: Color,
    /** ジャケ写が無いときの地色。「深く落としたメンバーカラー単色」。 */
    val accentDeep: Color
)

@Composable
fun rememberShareCardPalette(seed: String?): ShareCardPalette {
    val theme = ImasTheme.derive(seed = seed, brand = null, dark = true)
    return remember(theme) {
        ShareCardPalette(
            accent = theme.accent,
            // コアの heroSurface は「シード由来の暗い面」だが、カードの地としてはまだ明るい。
            // near-black 側へ寄せて、iOS の accentDeep (L≈0.10) と同じ沈み方にする。
            // 係数を掛けるだけなので、色相/彩度の決定はコアに残したまま。
            accentDeep = lerp(ShareInk.nearBlack, theme.heroSurface, 0.55f)
        )
    }
}

// MARK: - 流入導線フッター

/** 全カード共通の控えめなフッター (#アイドルライブDB)。主張しすぎないよう小さく上品に。 */
@Composable
fun ShareCardFooter(ink: Color, rule: Color) {
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(0.75.dp).background(rule))
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Mic, contentDescription = null, tint = ink, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(7.dp))
            Text("#アイドルライブDB", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = ink)
            Spacer(Modifier.weight(1f))
            Text(
                "IDOL LIVE DATABASE",
                fontSize = 9.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 2.4.sp,
                color = ink.copy(alpha = 0.7f)
            )
        }
    }
}

// MARK: - 見出しラベル (メンバーカラー小四角 + 字間広め)

/** `▬ タグを追加しました！` のような編集的ラベル。小バーは差し色のメンバーカラー。 */
@Composable
fun ShareEyebrow(text: String, accent: Color, ink: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(width = 18.dp, height = 3.dp).background(accent))
        Spacer(Modifier.width(8.dp))
        Text(
            text,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.5.sp,
            color = ink
        )
    }
}

// MARK: - 写真カードの共通骨格 (ハードエッジのカラーブロック分割)

/**
 * ジャケ写を主役にするカード (タグ / セトリ感想) の共通レイアウト。
 * 上をジャケ写フルブリード、下をソリッド near-black パネルにするハードエッジ分割。
 * 継ぎ目に細いメンバーカラー罫線 1 本。グラデは使わない。
 */
@Composable
fun PhotoShareScaffold(
    artwork: ImageBitmap?,
    palette: ShareCardPalette,
    size: ShareCardSize,
    content: @Composable ColumnScope.() -> Unit
) {
    // 写真の占有率 (上から)。残りがソリッドのテキストパネル。
    // 正方形は写真を大きめに、9:16 は縦に長い分テキストパネルを稼ぎたいので写真を抑える。
    val aspect = size.heightUnits.toFloat() / size.widthUnits.toFloat()
    val photoRatio = (0.78f - aspect * 0.18f).coerceIn(0.44f, 0.66f)
    val photoHeight = (size.heightUnits * photoRatio).dp

    // テキストパネルの余白も比率追従 (縦長ほどゆったり、正方形は詰める)。
    val panelHPad = (size.widthUnits * 0.074f).dp
    val panelTopPad = (size.heightUnits * 0.044f).dp
    val panelBottomPad = (size.heightUnits * 0.047f).dp

    Column(Modifier.fillMaxSize().background(ShareInk.nearBlack)) {
        Box(Modifier.fillMaxWidth().height(photoHeight)) {
            PhotoBlock(artwork = artwork, palette = palette, height = photoHeight)
            // 写真下端の可読性が要る場合に備え、均一なフラット薄黒を 1 枚だけ
            // (グラデではなくベタ)。継ぎ目付近の白ラベルの抜けを防ぐ。
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(photoHeight * 0.28f)
                    .background(Color.Black.copy(alpha = 0.12f))
            )
        }

        // 継ぎ目: 細いメンバーカラー罫線 1 本 (差し色)。
        Box(Modifier.fillMaxWidth().height(3.dp).background(palette.accent))

        // 下: ソリッド near-black のテキストパネル。
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(ShareInk.nearBlack)
                .padding(start = panelHPad, end = panelHPad, top = panelTopPad, bottom = panelBottomPad)
        ) {
            content()
            Spacer(Modifier.weight(1f))
            ShareCardFooter(ink = ShareInk.ink2, rule = Color.White.copy(alpha = 0.16f))
        }
    }
}

@Composable
private fun PhotoBlock(artwork: ImageBitmap?, palette: ShareCardPalette, height: Dp) {
    if (artwork != null) {
        Image(
            bitmap = artwork,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(height)
        )
    } else {
        // フォールバック: 深く落としたメンバーカラー単色 + 幾何透かし 1 つ。
        Box(
            modifier = Modifier.fillMaxWidth().height(height).background(palette.accentDeep),
            contentAlignment = Alignment.Center
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val center = Offset(this.size.width / 2f, this.size.height / 2f)
                val stroke = Stroke(2.dp.toPx())
                drawCircle(Color.White.copy(alpha = 0.07f), radius = height.toPx() * 0.475f, center = center, style = stroke)
                drawCircle(palette.accent.copy(alpha = 0.18f), radius = height.toPx() * 0.31f, center = center, style = stroke)
            }
            Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.10f),
                modifier = Modifier.size(height * 0.28f)
            )
        }
    }
}

// MARK: - 単色編集カードの共通骨格 (写真なし: 回収率)

/**
 * 写真を持たないカード (回収率) の骨格。単色 near-black 地 + 大きな幾何透かし 1 つ。
 * 多色グラデは使わない。メンバーカラーは差し色のみ。
 */
@Composable
fun SoloShareScaffold(
    palette: ShareCardPalette,
    size: ShareCardSize,
    badge: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Box(Modifier.fillMaxSize().background(ShareInk.nearBlack)) {
        // 大きな幾何学透かし 1 つ (淡い同心円)。カード右上隅の外側に中心を置き、
        // 上部に弧が覗く構図を全比率で再現する。
        Canvas(Modifier.fillMaxSize()) {
            val cx = this.size.width / 2f + this.size.width * 0.39f
            val cy = this.size.height / 2f - this.size.height * 0.30f
            val stroke = Stroke(1.5.dp.toPx())
            drawCircle(ShareInk.ink.copy(alpha = 0.06f), radius = this.size.width / 2f, center = Offset(cx, cy), style = stroke)
            drawCircle(palette.accent.copy(alpha = 0.14f), radius = this.size.width * 0.3335f, center = Offset(cx, cy), style = stroke)
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    horizontal = (size.widthUnits * 0.081f).dp,
                    vertical = (size.heightUnits * 0.068f).dp
                )
        ) {
            ShareEyebrow(text = badge, accent = palette.accent, ink = ShareInk.ink.copy(alpha = 0.82f))
            // iOS は content を maxHeight:.infinity の枠に入れて上下に Spacer を挟むので、
            // 縦方向は中央寄せになる。ここも Box の中央寄せで同じ見えにする。
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.CenterStart) {
                Column(Modifier.fillMaxWidth()) { content() }
            }
            ShareCardFooter(ink = ShareInk.ink2, rule = ShareInk.ink.copy(alpha = 0.16f))
        }
    }
}

// MARK: - ランキング・ティアー表の骨格 (暗地 + 大見出し + 透かし + フッター)

/**
 * ランキング・ティアー表カードの共通骨格 (iOS `PosterShareScaffold`。docs/DESIGN_SYSTEM.md §13 `.poster`)。
 * `.photo`/`.solo` と同じ near-black の地に、[差し色の印字バー + 大見出し + 補足 1 行] の見出しと
 * 右上の透かしを乗せ、本文 (表彰台・段ごとの行) は呼び出し側が自由に組む。グラデは使わない。
 *
 * 地と透かしは [Modifier.drawBehind] で描く (サイズを持つ兄弟コンポーネントにしない)。兄弟にすると
 * 「中身なり」の高さを決めるときに透かしの正方形の一辺がそのまま高さの下限になり、段の少ない
 * ティアー表の下に余白が伸びてしまう (iOS 版の `PosterShareScaffold` が踏んだのと同じ不具合)。
 * `drawBehind` ならホスト (中身の Column) の確定後のサイズに合わせて描かれるだけなので、
 * 高さの決定には関与しない。
 *
 * ティアー表の書き出しのように件数で縦に伸びる画像は [height] に null を渡す
 * (下のフッターまでの間を最小 22dp の空きで詰める。固定キャンバスでは残りを埋めて
 * 下端にフッターを揃える)。
 */
@Composable
fun PosterShareScaffold(
    palette: ShareCardPalette,
    width: Dp,
    height: Dp?,
    kicker: String,
    title: String,
    modifier: Modifier = Modifier,
    trailingKicker: String? = null,
    titleSize: TextUnit = 50.sp,
    subtitle: String? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .then(if (height != null) Modifier.size(width, height) else Modifier.width(width))
            .drawBehind {
                drawRect(ShareInk.nearBlack)
                val w = width.toPx()
                val anchor = (height ?: width).toPx()
                val cx = w * 0.92f
                val cy = anchor * 0.18f
                val stroke = Stroke(1.5.dp.toPx())
                drawCircle(Color.White.copy(alpha = 0.06f), radius = w / 2f, center = Offset(cx, cy), style = stroke)
                drawCircle(palette.accent.copy(alpha = 0.16f), radius = w * 0.3335f, center = Offset(cx, cy), style = stroke)
            }
            .padding(horizontal = 36.dp)
            .padding(top = 32.dp, bottom = 28.dp)
    ) {
        PosterHeader(palette = palette, kicker = kicker, trailingKicker = trailingKicker, title = title, titleSize = titleSize, subtitle = subtitle)
        content()
        if (height != null) {
            Spacer(Modifier.weight(1f).heightIn(min = 22.dp))
        } else {
            Spacer(Modifier.height(22.dp))
        }
        ShareCardFooter(ink = Color.White.copy(alpha = 0.62f), rule = Color.White.copy(alpha = 0.16f))
    }
}

@Composable
private fun PosterHeader(
    palette: ShareCardPalette,
    kicker: String,
    trailingKicker: String?,
    title: String,
    titleSize: TextUnit,
    subtitle: String?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(18.dp).height(3.dp).background(palette.accent))
            Spacer(Modifier.width(8.dp))
            Text(kicker, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (trailingKicker != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    trailingKicker, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
                    letterSpacing = 2.4.sp, color = Color.White.copy(alpha = 0.45f), maxLines = 1
                )
            }
        }
        ImasFitText(
            title,
            style = TextStyle(fontSize = titleSize, fontWeight = FontWeight.Black),
            color = Color.White,
            maxLines = 2,
            minScale = 0.6f,
            modifier = Modifier.padding(top = 6.dp)
        )
        if (subtitle != null) {
            Text(subtitle, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.55f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// =============================================================================
// プレビュー + 比率切替 + 共有/保存ボタン (各エントリポイント共通のガワ)
// =============================================================================

/**
 * カードのプレビューと実行ボタンを載せた共通ペイン。
 *
 * カードは [ShareCardSize] を受け取って組み立てるので、`card` は
 * 「サイズを受け取ってカードを描くビルダー」で受け取る。
 * プレビューと出力画像が必ず同じサイズで作られることを保証するため。
 *
 * @param ratios 出せる比率。1 つだけ渡すと切替トグルは出ない (レイアウトが 4:5 前提のカード用)。
 * @param isPreparingCard ジャケ写のロード待ちなど、カードがまだ完成形でない間 true。
 * @param shareText 画像に添える本文 (イントロドンのみ)。
 */
@Composable
fun ShareCardActionPane(
    modifier: Modifier = Modifier,
    ratios: List<ShareCardRatio> = ShareCardRatio.ALL,
    isPreparingCard: Boolean = false,
    shareText: String? = null,
    fileNamePrefix: String = "imaslivedb",
    card: @Composable (ShareCardSize) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val capture = rememberShareCardCapture()

    var ratio by remember(ratios) { mutableStateOf(ratios.firstOrNull { it == ShareCardRatio.DEFAULT } ?: ratios.first()) }
    var isBusy by remember { mutableStateOf(false) }

    // Android 9 以下の保存経路。ピッカーから戻ってくるまで Bitmap を持っておく。
    var pendingSave by remember { mutableStateOf<Bitmap?>(null) }
    val documentPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("image/png")
    ) { uri ->
        val bitmap = pendingSave
        pendingSave = null
        if (uri == null || bitmap == null) return@rememberLauncherForActivityResult
        scope.launch {
            val ok = ShareCardFiles.writeTo(context, uri, bitmap)
            Toast.makeText(context, if (ok) "画像を保存しました" else "保存に失敗しました", Toast.LENGTH_SHORT).show()
        }
    }

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(DS.rLG))
        ) {
            ShareCardCanvas(size = ratio.size, capture = capture) { card(ratio.size) }
        }

        if (ratios.size > 1) {
            RatioSwitcher(ratios = ratios, selected = ratio, onSelect = { ratio = it })
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            ImasButton(
                title = if (isPreparingCard) "画像を準備中…" else "シェアする",
                onClick = {
                    scope.launch {
                        isBusy = true
                        val bitmap = capture.toBitmap()
                        isBusy = false
                        if (bitmap == null) {
                            Toast.makeText(context, "シェア画像の生成に失敗しました", Toast.LENGTH_SHORT).show()
                            return@launch
                        }
                        ShareCardFiles.share(context, bitmap, fileNamePrefix, shareText)
                    }
                },
                icon = if (isPreparingCard) null else Icons.Filled.Share,
                role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.LARGE,
                enabled = !isPreparingCard && !isBusy,
                isLoading = isBusy,
                modifier = Modifier.weight(1f)
            )

            ImasButton(
                title = "保存",
                onClick = {
                    scope.launch {
                        isBusy = true
                        val bitmap = capture.toBitmap()
                        isBusy = false
                        if (bitmap == null) {
                            Toast.makeText(context, "シェア画像の生成に失敗しました", Toast.LENGTH_SHORT).show()
                            return@launch
                        }
                        when (ShareCardFiles.saveToPictures(context, bitmap, fileNamePrefix)) {
                            ShareCardSaveResult.Saved ->
                                Toast.makeText(context, "ピクチャに保存しました", Toast.LENGTH_SHORT).show()
                            ShareCardSaveResult.NeedsDocumentPicker -> {
                                pendingSave = bitmap
                                documentPicker.launch(ShareCardFiles.fileName(fileNamePrefix))
                            }
                            ShareCardSaveResult.Failed ->
                                Toast.makeText(context, "保存に失敗しました", Toast.LENGTH_SHORT).show()
                        }
                    }
                },
                icon = Icons.Filled.Download,
                role = ImasButtonRole.SECONDARY,
                size = ImasButtonSize.LARGE,
                enabled = !isPreparingCard && !isBusy,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/** 1:1 / 4:5 / 9:16 の切替 (`ImasSegmented`。2 行目に用途の一言を添える)。 */
@Composable
private fun RatioSwitcher(
    ratios: List<ShareCardRatio>,
    selected: ShareCardRatio,
    onSelect: (ShareCardRatio) -> Unit
) {
    ImasSegmented(
        labels = ratios.map { it.label },
        captions = ratios.map { it.caption },
        selection = ratios.indexOf(selected),
        onSelect = { onSelect(ratios[it]) }
    )
}

/**
 * シェアカードを出すシートの外枠。
 *
 * 4 つの入口がそれぞれ ModalBottomSheet + スクロール + 見出し + 「閉じる」を書いていると、
 * 閉じるの位置や余白が入口ごとにズレる。枠はここに一本化する (iOS ShareCardSheet と同じ役割)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareCardSheet(
    title: String,
    onDismiss: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = DS.Space.screen)
                .padding(bottom = DS.sp7),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
        ) {
            ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = title)
            content()
        }
    }
}
