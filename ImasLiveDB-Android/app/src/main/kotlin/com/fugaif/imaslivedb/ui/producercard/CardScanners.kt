package com.fugaif.imaslivedb.ui.producercard

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.os.Build
import android.net.Uri
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import java.io.File
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import java.util.concurrent.Executors
import kotlin.coroutines.resume
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

// =============================================================================
// 名刺を読むカメラ。iOS `CardScanners.swift` の移植。
//
// CardQRScanner        アプリの名刺の QR を読む (CameraX + ML Kit の QR 読み取り。端末内のモデルで、
//                      圏外でも動く)。読めた文字列を 1 回だけ返す。
// rememberPaperCardCamera  紙の名刺の表裏を撮る (ML Kit の書類カメラ。名刺の形に切り抜かれる。
//                      まだ入っていなければふつうのカメラ)。
// PaperCardCodeReader  撮った写真から QR を拾う (ML Kit)。文字の読み取りはしない。
// =============================================================================

private const val TAG = "producer_card"

private fun qrClient() = BarcodeScanning.getClient(
    BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
)

/** この端末でカメラの読み取りが使えるか (カメラが無い端末は false)。権限は画面が別に求める。 */
fun cardCameraAvailable(context: Context): Boolean =
    context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)

fun cardCameraPermitted(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

/** 名刺の QR を読む。同じ中身を何度も返さない。カメラの権限は呼ぶ側が先に取る。 */
@Composable
fun CardQRScanner(onScan: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentOnScan by rememberUpdatedState(onScan)
    val previewView = remember { PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    AndroidView(factory = { previewView }, modifier = modifier.fillMaxSize())

    DisposableEffect(lifecycleOwner) {
        val scanner = qrClient()
        val executor = Executors.newSingleThreadExecutor()
        val mainExecutor = ContextCompat.getMainExecutor(context)
        val providerFuture = ProcessCameraProvider.getInstance(context)
        var last: String? = null
        // カメラの準備が整う前に画面が閉じたら結び付けない (閉じた画面のカメラが点いたまま残る)。
        var disposed = false
        var preview: Preview? = null
        var analysis: ImageAnalysis? = null
        providerFuture.addListener({
            if (disposed) return@addListener
            val provider = runCatching { providerFuture.get() }.getOrNull() ?: return@addListener
            val p = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            val a = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            a.setAnalyzer(executor) { proxy ->
                val media = proxy.image
                if (media == null) {
                    proxy.close()
                    return@setAnalyzer
                }
                val input = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                scanner.process(input)
                    .addOnSuccessListener(mainExecutor) { codes ->
                        val text = codes.firstNotNullOfOrNull { it.rawValue } ?: return@addOnSuccessListener
                        if (text != last) {
                            last = text
                            currentOnScan(text)
                        }
                    }
                    .addOnCompleteListener { proxy.close() }
            }
            runCatching {
                provider.unbindAll()
                provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, p, a)
                preview = p
                analysis = a
            }.onFailure { Log.e(TAG, "card_camera_bind_failed", it) }
        }, mainExecutor)
        onDispose {
            disposed = true
            runCatching {
                val provider = providerFuture.get()
                listOfNotNull(preview, analysis).forEach { provider.unbind(it) }
            }
            scanner.close()
            executor.shutdown()
        }
    }
}

private fun paperScannerOptions() = GmsDocumentScannerOptions.Builder()
    .setGalleryImportAllowed(false)
    .setPageLimit(2)
    .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
    .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_BASE)
    .build()

/**
 * 書類カメラ (Google Play 開発者サービスの追加の部品) を先に端末へ入れておく。会場は圏外のことが
 * 多いので、名刺の画面を開いたとき (たいてい電波のある所) に頼んでおく。入っていれば何もしない。
 */
fun prefetchPaperCardCamera(context: Context) {
    runCatching {
        val scanner = GmsDocumentScanning.getClient(paperScannerOptions())
        ModuleInstall.getClient(context).installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
            .addOnFailureListener { Log.w(TAG, "paper_card_camera_prefetch_failed", it) }
    }
}

/**
 * 紙の名刺を撮るカメラ。返す関数を呼ぶと開く。
 *
 * ML Kit の書類カメラ (名刺の形に切り抜かれる。表と裏の 2 枚まで) を使う。書類カメラがまだ端末に
 * 入っていない (圏外で落とせない等) ときは、ふつうのカメラで 1 枚撮る (QR は同じく読める)。
 */
@Composable
fun rememberPaperCardCamera(onFinish: (List<Uri>) -> Unit): () -> Unit {
    val context = LocalContext.current
    val currentFinish by rememberUpdatedState(onFinish)
    val scan = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        if (result.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult
        val pages = GmsDocumentScanningResult.fromActivityResultIntent(result.data)?.pages.orEmpty()
        // 表と裏の 2 枚まで。3 枚目以降は名刺ではないので使わない。
        currentFinish(pages.take(2).map { it.imageUri })
    }
    var captureUri by remember { mutableStateOf<Uri?>(null) }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = captureUri
        if (ok && uri != null) currentFinish(listOf(uri))
    }
    fun takePlainPhoto() {
        val uri = runCatching {
            val dir = File(context.cacheDir, PAPER_CAPTURE_DIR).apply { mkdirs() }
            FileProvider.getUriForFile(context, "${context.packageName}.shareprovider", File(dir, "paper_card.jpg"))
        }.getOrNull() ?: return
        captureUri = uri
        photo.launch(uri)
    }
    return remember(context) {
        {
            val activity = context.findActivity()
            val scanner = GmsDocumentScanning.getClient(paperScannerOptions())
            if (activity == null) {
                takePlainPhoto()
            } else {
                ModuleInstall.getClient(context).areModulesAvailable(scanner)
                    .addOnSuccessListener { availability ->
                        if (!availability.areModulesAvailable()) {
                            prefetchPaperCardCamera(context)
                            takePlainPhoto()
                            return@addOnSuccessListener
                        }
                        scanner.getStartScanIntent(activity)
                            .addOnSuccessListener { sender -> scan.launch(IntentSenderRequest.Builder(sender).build()) }
                            .addOnFailureListener {
                                Log.e(TAG, "paper_card_camera_unavailable", it)
                                takePlainPhoto()
                            }
                    }
                    .addOnFailureListener {
                        Log.e(TAG, "paper_card_camera_unavailable", it)
                        takePlainPhoto()
                    }
            }
        }
    }
}

/** ふつうのカメラで撮った紙の名刺の置き場所 (res/xml/provider_paths.xml の cache-path と対)。 */
private const val PAPER_CAPTURE_DIR = "paper_card_capture"

/** 撮った写真・選んだ写真から QR を拾う。文字の読み取りはしない。 */
object PaperCardCodeReader {
    /** 写真に刷られた QR の中身 (写真の順、重複なし)。 */
    suspend fun codes(images: List<Bitmap>): List<String> {
        val scanner = qrClient()
        return try {
            val found = mutableListOf<String>()
            for (image in images) {
                val codes = scanner.process(InputImage.fromBitmap(image, 0)).awaitOrNull().orEmpty()
                for (code in codes) {
                    val text = code.rawValue ?: continue
                    if (text !in found) found += text
                }
            }
            found
        } finally {
            scanner.close()
        }
    }

    /** 写真を開く (大きな写真は長辺 2400px 程度まで間引く。保存のときに 2000px に縮める)。 */
    suspend fun loadBitmap(context: Context, uri: Uri): Bitmap? = withContext(Dispatchers.IO) {
        runCatching {
            val resolver = context.contentResolver
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 2400) sample *= 2
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // ImageDecoder は写真の向き (EXIF) を当てて開く。
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, _, _ ->
                    decoder.setTargetSampleSize(sample)
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            } else {
                resolver.openInputStream(uri)?.use {
                    BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
                }
            }
        }.onFailure { Log.e(TAG, "paper_card_photo_load_failed", it) }.getOrNull()
    }
}

private suspend fun <T> Task<T>.awaitOrNull(): T? = suspendCancellableCoroutine { cont ->
    addOnCompleteListener { task -> cont.resume(if (task.isSuccessful) task.result else null) }
}
