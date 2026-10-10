package com.fugaif.imaslivedb.data.producercard

import uniffi.imas_core.CardReceiveVia
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardFileContents
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.ScannedCode
import uniffi.imas_core.classifyScannedCode
import uniffi.imas_core.decodeCardFile

private const val TAG = "producer_card"

/** 受け取りの確認に渡す名刺 (QR・リンク・名刺ファイルのどれから来たか)。iOS `IncomingProducerCard` と対。 */
data class IncomingProducerCard(
    val payload: String,
    /** 名刺ファイルに入っていた担当の画像。 */
    val images: List<CardFileImage>,
    /** 受け取り方 (カメラの QR・リンク・名刺ファイル)。 */
    val via: CardReceiveVia
)

/** アプリの外から開かれた P名刺 (iOS `Deeplink.producerCard` / `.producerCardFile` と対)。 */
sealed interface ProducerCardIntent {
    /** 名刺の URL (`https://idollivedb.fugaapp.site/p/#…` / `imaslivedb://p#…`)。中身は `#` の後ろ。 */
    data class Card(val payload: String) : ProducerCardIntent

    /** 名刺ファイル (`.imascard`) を「このアプリで開く」・共有で渡されたとき。 */
    data class File(val uri: Uri) : ProducerCardIntent
}

/**
 * Intent から P名刺を拾う。どの形を名刺と読むかはコア (`classifyScannedCode`) 一本。
 * 名刺ファイルかどうかは中身をコア (`decodeCardFile`) が確かめる (拡張子・MIME だけでは決めない)。
 */
object ProducerCardIntents {
    /** 名刺ファイルの大きさの上限 (担当 5 人の画像でも 10MB 前後)。 */
    private const val MAX_CARD_FILE_BYTES = 64 * 1024 * 1024

    fun parse(intent: Intent?): ProducerCardIntent? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> {
                val data = intent.data ?: return null
                when (data.scheme) {
                    "content", "file" -> ProducerCardIntent.File(data)
                    else -> parseUrl(data.toString())?.let { ProducerCardIntent.Card(it) }
                }
            }
            Intent.ACTION_SEND -> stream(intent)?.let { ProducerCardIntent.File(it) }
            else -> null
        }
    }

    /** 名刺の URL なら `#` の後ろ。そうでなければ null。 */
    fun parseUrl(url: String): String? = (classifyScannedCode(url) as? ScannedCode.Card)?.payload

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    /** 渡された名刺ファイルを読む (中身の検査はコア)。読み込みはメインの外で行う。 */
    suspend fun readCardFile(context: Context, uri: Uri): CardFileContents? = withContext(Dispatchers.IO) {
        runCatching {
            context.contentResolver.openInputStream(uri)?.use { input -> readBounded(input) }
        }.onFailure { Log.e(TAG, "producer_card_file_read_failed", it) }.getOrNull()?.let { decodeCardFile(it) }
    }

    /** 上限を超えるファイルは読まない (読み切る前に打ち切る)。 */
    internal fun readBounded(input: java.io.InputStream, limit: Int = MAX_CARD_FILE_BYTES): ByteArray? {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var total = 0
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            total += n
            if (total > limit) return null
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }
}

/**
 * 外から届いた名刺の受け渡し口。iOS `ContentView.presentIncomingCard` と対。
 *
 * 名刺交換の画面が開いていればその中で受け取りの確認を開く (Quick Share は交換の最中に届く)。
 * 開いていなければアプリのルートが受け取りの確認のシートを出す。
 */
object ProducerCardIncoming {
    private val _pending = MutableStateFlow<IncomingProducerCard?>(null)

    /** ルートが出す受け取りの確認。出し終えたら [consume]。 */
    val pending: StateFlow<IncomingProducerCard?> = _pending.asStateFlow()

    private val _toExchange = MutableSharedFlow<IncomingProducerCard>(extraBufferCapacity = 4)

    /** 交換の画面が開いている間に届いた名刺。 */
    val toExchange: SharedFlow<IncomingProducerCard> = _toExchange.asSharedFlow()

    private val _fileFailed = MutableStateFlow(false)

    /** 名刺ファイルを読めなかった (ルートが知らせを出す)。 */
    val fileFailed: StateFlow<Boolean> = _fileFailed.asStateFlow()

    /** 開いている交換の画面の数。 */
    val exchangeOpenCount = AtomicInteger(0)

    fun present(incoming: IncomingProducerCard) {
        if (exchangeOpenCount.get() > 0) _toExchange.tryEmit(incoming) else _pending.value = incoming
    }

    fun consume() {
        _pending.value = null
    }

    fun reportFileFailed() {
        _fileFailed.value = true
    }

    fun dismissFileFailed() {
        _fileFailed.value = false
    }
}
