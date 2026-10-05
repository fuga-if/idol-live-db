package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URLEncoder
import kotlin.math.max
import kotlin.math.roundToInt
import uniffi.imas_core.CardFileImage

/**
 * 名刺入れの画像ファイル (受け取った担当の画像・紙の名刺の写真)。iOS `ProducerCardFiles` と対。
 *
 * 写真は**端末の中だけ** (バックアップにもクラウドにも載せない。アイドルの画像と同じ扱いで、
 * res/xml の Auto Backup からも外す)。置き場所は `filesDir/producer_cards/<名刺の id>/`。
 * 名刺を消したら丸ごと消す。
 */
object ProducerCardFiles {
    /** filesDir の下の置き場所の名前 (Auto Backup の除外と対。BackupRulesTest が突き合わせる)。 */
    const val DIRECTORY_NAME = "producer_cards"

    /** 紙の名刺の写真の面。 */
    enum class Side(val key: String) { FRONT("front"), BACK("back") }

    fun root(context: Context): File = File(context.filesDir, DIRECTORY_NAME)

    private fun folder(context: Context, cardId: String): File = File(root(context), safeName(cardId))

    /** ファイル名に使える形 (アイドルの id に `/` などが入っても階層を作らない)。 */
    private fun safeName(s: String): String = URLEncoder.encode(s, "UTF-8")

    private fun oshiFile(context: Context, cardId: String, idolId: String): File =
        File(folder(context, cardId), "oshi_${safeName(idolId)}.jpg")

    private fun photoFile(context: Context, cardId: String, side: Side): File =
        File(folder(context, cardId), "${side.key}.jpg")

    // ---- 受け取った担当の画像 ----

    /** 受け取った担当の画像 (画面の `imageUrl` に渡す形)。無ければ null。 */
    fun oshiImageUrl(context: Context, cardId: String, idolId: String): String? =
        oshiFile(context, cardId, idolId).takeIf { it.exists() }?.let { Uri.fromFile(it).toString() }

    /** 受け取った担当の画像を書く。同じ担当の画像は新しいもので置き換える。 */
    fun saveOshiImages(context: Context, cardId: String, images: List<CardFileImage>) {
        if (images.isEmpty()) return
        folder(context, cardId).mkdirs()
        for (image in images) writeAtomically(oshiFile(context, cardId, image.idolId), image.jpeg)
    }

    // ---- 紙の名刺の写真 ----

    fun photoUrl(context: Context, cardId: String, side: Side): String? =
        photoFile(context, cardId, side).takeIf { it.exists() }?.let { Uri.fromFile(it).toString() }

    fun savePhoto(context: Context, bitmap: Bitmap, cardId: String, side: Side) {
        val data = jpeg(bitmap, maxPixels = 2000) ?: return
        folder(context, cardId).mkdirs()
        writeAtomically(photoFile(context, cardId, side), data)
    }

    fun deleteAll(context: Context, cardId: String) {
        folder(context, cardId).deleteRecursively()
    }

    // ---- 送る画像 ----

    /** 担当の画像を送る形 (JPEG、長辺 1600px まで) にする。透過は白地に置く (JPEG で黒く潰れる)。 */
    fun jpeg(bitmap: Bitmap, maxPixels: Int = 1600, quality: Int = 85): ByteArray? = runCatching {
        val longSide = max(bitmap.width, bitmap.height)
        val ratio = if (longSide > maxPixels) maxPixels.toFloat() / longSide else 1f
        val w = (bitmap.width * ratio).roundToInt().coerceAtLeast(1)
        val h = (bitmap.height * ratio).roundToInt().coerceAtLeast(1)
        val flat = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(flat).apply {
            drawColor(Color.WHITE)
            val scaled = if (ratio < 1f) Bitmap.createScaledBitmap(bitmap, w, h, true) else bitmap
            drawBitmap(scaled, 0f, 0f, null)
        }
        ByteArrayOutputStream().use { out ->
            flat.compress(Bitmap.CompressFormat.JPEG, quality, out)
            out.toByteArray()
        }
    }.getOrNull()

    /** 端末のファイル (担当の画像) を送る形にする。読めなければ null。 */
    fun jpeg(file: File): ByteArray? {
        val bitmap = decodeBounded(file) ?: return null
        return jpeg(bitmap)
    }

    /** 大きな写真をそのまま開いてメモリを使い切らないよう、長辺 3200px 程度まで間引いて開く。 */
    private fun decodeBounded(file: File): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 3200) sample *= 2
        BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()

    private fun writeAtomically(target: File, bytes: ByteArray) {
        val tmp = File(target.parentFile, "${target.name}.tmp")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(target)) {
            target.delete()
            tmp.renameTo(target)
        }
    }
}
