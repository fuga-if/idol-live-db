package com.fugaif.imaslivedb.ui.share

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Size
import coil3.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// =============================================================================
// シェアカードの画像化 / 共有 / 保存まわりの共通インフラ。
// iOS ImasLiveDB/Views/Share/ShareCardRenderer.swift の移植。
//
// iOS は SwiftUI View を ImageRenderer(scale: 2) で UIImage 化する。Compose には
// 相当物が無いので GraphicsLayer で同じことをする:
//   drawWithContent { layer.record { drawContent() } ; drawLayer(layer) }
//   → layer.toImageBitmap()
// Modifier.drawWithContent で「画面に描くついでに録っておく」形なので、オフスクリーンで
// もう一度コンポーズし直す必要がない = プレビューと出力が必ず同じ木から出る。
//
// 旧来の View.draw(Canvas) / PixelCopy は Compose では使えない (前者は View 階層が要り、
// 後者は「画面に見えているピクセル」しか取れないので、縮小プレビューを撮ると縮小画像になる)。
// =============================================================================

private const val TAG = "share_card"

/**
 * カードの論理サイズ。単位は iOS の pt (= カード単位) にそのまま合わせてある。
 *
 * **なぜ論理サイズでレンダリングするか**: 出力画像の解像度を端末の画面密度から切り離すため。
 * Compose の dp は端末密度でピクセルに化けるので、素直に組むと mdpi 端末では 540×675px、
 * xxhdpi 端末では 1620×2025px と、同じカードが端末ごとに違う大きさで焼き上がる。
 * レンダリング時に [LocalDensity] を [SHARE_CARD_SCALE] に固定してしまえば
 * 「540 単位 × 2 = 必ず 1080px」になり、どの端末でも iOS と同じ 1080×1350 が出る
 * (iOS の `ImageRenderer.scale = 2` と同じ考え方)。
 * fontScale も 1 に固定する。端末の文字サイズ設定に追随させると、出力画像のレイアウトが
 * ユーザーごとに崩れてしまうため (iOS 側も同じ理由で Dynamic Type を切っている)。
 */
@Immutable
data class ShareCardSize(val widthUnits: Int, val heightUnits: Int) {
    val widthPx: Int get() = (widthUnits * SHARE_CARD_SCALE).toInt()
    val heightPx: Int get() = (heightUnits * SHARE_CARD_SCALE).toInt()
    val aspectRatio: Float get() = widthUnits.toFloat() / heightUnits.toFloat()
}

/** 論理サイズ → ピクセルの倍率。540 単位 × 2 = 1080px (iOS の ImageRenderer.scale = 2 と同値)。 */
const val SHARE_CARD_SCALE = 2f

/**
 * シェアシートで選べるアスペクト比。iOS `ShareCard.Ratio` の移植で、論理サイズも同じ。
 * 長辺基準を揃えてあり、X / Instagram フィード / ストーリーズに最適化している。
 */
enum class ShareCardRatio(val label: String, val caption: String, val size: ShareCardSize) {
    /** 1:1 正方形 (1080×1080px)。Instagram フィードの基本形。 */
    SQUARE("1:1", "正方形", ShareCardSize(540, 540)),

    /** 4:5 縦長 (1080×1350px)。既定。X タイムラインで存在感が出る。 */
    PORTRAIT("4:5", "縦長", ShareCardSize(540, 675)),

    /** 9:16 縦長 (1080×1920px)。ストーリーズ / リール向け。 */
    STORY("9:16", "ストーリーズ", ShareCardSize(540, 960));

    companion object {
        /** 既定の比率。デザインの主役は 4:5。 */
        val DEFAULT = PORTRAIT

        /** 比率トグルに出す標準の並び。 */
        val ALL: List<ShareCardRatio> = listOf(SQUARE, PORTRAIT, STORY)
    }
}

/**
 * [ShareCardCanvas] が描いた内容を保持し、任意のタイミングで Bitmap 化する取っ手。
 * 1 つの Canvas につき 1 つ。
 */
@Stable
class ShareCardCapture internal constructor(internal val layer: GraphicsLayer) {

    /**
     * 直近に描かれたカードを Bitmap 化する。まだ一度も描かれていなければ null。
     *
     * 返る Bitmap は論理サイズ×[SHARE_CARD_SCALE] の実寸 (例 1080×1350) で、
     * プレビューの縮小率とは無関係。縮小は描画時の変形でしか掛けていないため。
     */
    suspend fun toBitmap(): Bitmap? = runCatching {
        layer.toImageBitmap().asAndroidBitmap()
    }.onFailure { Log.e(TAG, "share_card_render_failed", it) }.getOrNull()
}

@Composable
fun rememberShareCardCapture(): ShareCardCapture {
    val layer = rememberGraphicsLayer()
    return remember(layer) { ShareCardCapture(layer) }
}

/**
 * カードを「論理サイズのまま」組み、画面には縮小して見せるプレビュー兼レンダリング面。
 *
 * レイアウトは常に論理サイズ ([ShareCardSize]) で行い、画面に収めるための縮小は
 * `graphicsLayer { scaleX/scaleY }` = **描画時の変形**だけで掛ける。レイアウトを縮めて
 * しまうと録画される内容も縮み、出力画像がプレビューの解像度になってしまう。
 */
@Composable
fun ShareCardCanvas(
    size: ShareCardSize,
    capture: ShareCardCapture,
    modifier: Modifier = Modifier,
    card: @Composable () -> Unit
) {
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .aspectRatio(size.aspectRatio)
    ) {
        // 制約は px なので、密度を差し替えても計算がずれない。
        val available = constraints.maxWidth
        val previewScale = if (available > 0) available.toFloat() / size.widthPx else 1f

        CompositionLocalProvider(
            // ここから内側の 1.dp = SHARE_CARD_SCALE px に固定する (端末密度を無視する)。
            LocalDensity provides Density(density = SHARE_CARD_SCALE, fontScale = 1f)
        ) {
            Box(
                Modifier
                    // requiredSize は親の制約を無視するので、小さな枠の中でも実寸で組める。
                    .requiredSize(size.widthUnits.dp, size.heightUnits.dp)
                    .graphicsLayer {
                        scaleX = previewScale
                        scaleY = previewScale
                        transformOrigin = TransformOrigin(0f, 0f)
                    }
            ) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .drawWithContent {
                            // 画面に出すのと同じ描画を、変形が掛かる手前で層に録っておく。
                            capture.layer.record { this@drawWithContent.drawContent() }
                            drawLayer(capture.layer)
                        }
                ) { card() }
            }
        }
    }
}

// =============================================================================
// 共有 (ACTION_SEND) と保存 (MediaStore)
// =============================================================================

/** 保存の結果。端末世代で経路が変わるので、呼び出し側が分岐できるように型で返す。 */
sealed interface ShareCardSaveResult {
    data object Saved : ShareCardSaveResult

    /**
     * Android 9 以下は権限なしで MediaStore に書けないので、保存先をユーザーに選ばせる。
     * 呼び出し側が `ACTION_CREATE_DOCUMENT` を出し、得た Uri を [ShareCardFiles.writeTo] に渡す。
     */
    data object NeedsDocumentPicker : ShareCardSaveResult

    data object Failed : ShareCardSaveResult
}

object ShareCardFiles {
    /** cacheDir 配下の受け渡し用ディレクトリ。res/xml/provider_paths.xml の cache-path と対。 */
    private const val CACHE_DIR = "share_cards"

    /** ギャラリーのアルバム名 (Pictures/<ここ>)。 */
    private const val ALBUM = "アイドルライブDB"

    private val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)

    fun fileName(prefix: String): String = "${prefix}_${stamp.format(Date())}.png"

    /**
     * 共有シートを開く。
     *
     * **なぜ FileProvider が要るか**: Android 7 (API 24) 以降、`file://` の Uri を他アプリへ
     * 渡した瞬間に `FileUriExposedException` でクラッシュする。アプリ専用領域である cacheDir は
     * そもそも他アプリから読めないので、`content://` に化かして一時的な読み取り権限を
     * 相手に渡す仕組み = FileProvider を通すしかない。Bitmap を Intent の extra に直接
     * 積む手 (Parcelable) は 1MB の Binder 制限に引っかかるため使えない。
     *
     * @param text 画像に添える本文。イントロドンのように「画像 + 一言」で出したいときだけ渡す。
     */
    suspend fun share(context: Context, bitmap: Bitmap, prefix: String, text: String? = null): Boolean {
        val uri = cacheUri(context, bitmap, fileName(prefix)) ?: return false
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            if (!text.isNullOrEmpty()) putExtra(Intent.EXTRA_TEXT, text)
            // EXTRA_STREAM だけだと権限付与を拾わない受け手がいるので ClipData にも載せる。
            clipData = ClipData.newUri(context.contentResolver, "share_card", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return runCatching {
            context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.onFailure { Log.e(TAG, "share_card_share_failed", it) }.isSuccess
    }

    /** cacheDir に PNG を書き出し、FileProvider 経由の content:// を返す。 */
    private suspend fun cacheUri(context: Context, bitmap: Bitmap, name: String): Uri? =
        withContext(Dispatchers.IO) {
            runCatching {
                val dir = File(context.cacheDir, CACHE_DIR).apply { mkdirs() }
                val file = File(dir, name)
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                FileProvider.getUriForFile(context, "${context.packageName}.shareprovider", file)
            }.onFailure { Log.e(TAG, "share_card_cache_write_failed", it) }.getOrNull()
        }

    /**
     * 端末のギャラリー (Pictures/アイドルライブDB) に保存する。
     *
     * Android 10 (API 29) 以降は Scoped Storage により、自分が挿入したエントリへ書くだけなら
     * WRITE_EXTERNAL_STORAGE が不要 (そもそも API 29+ では同権限が無効化されている)。
     * それ以前は権限が要るため、権限を求める代わりに保存先ピッカー (SAF) へ倒す。
     */
    suspend fun saveToPictures(context: Context, bitmap: Bitmap, prefix: String): ShareCardSaveResult {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return ShareCardSaveResult.NeedsDocumentPicker
        return withContext(Dispatchers.IO) { insertViaMediaStore(context, bitmap, fileName(prefix)) }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun insertViaMediaStore(context: Context, bitmap: Bitmap, name: String): ShareCardSaveResult {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$ALBUM")
            // 書き終わるまで他アプリから見えないようにする (中途半端な画像がギャラリーに出ない)。
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = runCatching { resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) }
            .onFailure { Log.e(TAG, "share_card_mediastore_insert_failed", it) }
            .getOrNull() ?: return ShareCardSaveResult.Failed

        return runCatching {
            resolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            ShareCardSaveResult.Saved
        }.getOrElse {
            Log.e(TAG, "share_card_mediastore_write_failed", it)
            // 途中で落ちた IS_PENDING=1 のエントリはゴミなので消しておく。
            runCatching { resolver.delete(uri, null, null) }
            ShareCardSaveResult.Failed
        }
    }

    /** SAF (ACTION_CREATE_DOCUMENT) で選ばせた保存先へ書き出す。Android 9 以下の保存経路。 */
    suspend fun writeTo(context: Context, uri: Uri, bitmap: Bitmap): Boolean =
        withContext(Dispatchers.IO) {
            runCatching {
                context.contentResolver.openOutputStream(uri)!!
                    .use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }.onFailure { Log.e(TAG, "share_card_saf_write_failed", it) }.isSuccess
        }
}

// =============================================================================
// カードに焼き込むジャケ写のロード
// =============================================================================

/**
 * シェアカードに焼き込むジャケット画像のローダ。
 *
 * レンダリングは「今画面に描かれているもの」を録るだけなので、非同期ロードの完了を待たない。
 * カード側で AsyncImage を使うと、まだ届いていないジャケ写が抜けた画像が焼ける。必ず
 * ここでロード済みの [ImageBitmap] を先に用意し、それをカードへ渡すこと。
 */
object ShareCardArtwork {
    /** mzstatic 形式の末尾 `/{w}x{h}bb....jpg`。 */
    private val SIZE_SUFFIX = Regex("""/(\d+)x(\d+)(bb[^/]*)$""")

    suspend fun load(context: Context, urlString: String?): ImageBitmap? {
        if (urlString.isNullOrBlank()) return null
        val request = ImageRequest.Builder(context)
            .data(highResolution(urlString))
            .size(Size.ORIGINAL)
            // HARDWARE bitmap はソフトウェア経路で読めないことがあるので、焼き込み用は素の
            // ARGB_8888 で受け取る (画面表示用の既定とは要件が違う)。
            .allowHardware(false)
            .build()
        val result = runCatching { SingletonImageLoader.get(context).execute(request) }
            .onFailure { Log.e(TAG, "share_card_artwork_load_failed", it) }
            .getOrNull()
        return (result as? SuccessResult)?.image?.toBitmap()?.asImageBitmap()
    }

    /**
     * 600px 未満の URL を 600x600 に引き上げる。
     * (DB 上はほぼ 600x600 だが、低解像度 URL が混ざっても焼き込みがボケないように)
     */
    fun highResolution(urlString: String): String {
        val match = SIZE_SUFFIX.find(urlString) ?: return urlString
        val w = match.groupValues[1].toIntOrNull() ?: return urlString
        val h = match.groupValues[2].toIntOrNull() ?: return urlString
        if (w >= 600 && h >= 600) return urlString
        return urlString.replaceRange(match.range, "/600x600${match.groupValues[3]}")
    }
}

/** ジャケ写ロードの状態。iOS `ShareArtworkLoader` の移植。 */
@Immutable
data class ShareArtwork(
    val image: ImageBitmap? = null,
    /** 成功/失敗を問わずロードが終わったか。URL 無しの曲は最初から完了扱い。 */
    val isFinished: Boolean = false
) {
    /** カードがまだ完成形でないか。true の間はシェアボタンを「準備中」にする。 */
    val isPreparing: Boolean get() = !isFinished
}

/**
 * ジャケ写を非同期にロードして状態で返す。カードを出す画面はこれを呼び、
 * [ShareArtwork.isPreparing] が下りるまでシェアを止める (中途半端なカードを焼かないため)。
 */
@Composable
fun rememberShareArtwork(url: String?): ShareArtwork {
    val context = LocalContext.current
    var state by remember(url) { mutableStateOf(ShareArtwork(isFinished = url.isNullOrBlank())) }
    LaunchedEffect(url) {
        if (!url.isNullOrBlank()) {
            state = ShareArtwork(image = ShareCardArtwork.load(context, url), isFinished = true)
        }
    }
    return state
}
