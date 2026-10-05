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
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import java.util.UUID
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.CardFileImageKind

/**
 * 名刺入れの画像ファイル (受け取った担当の画像・名刺の写真・紙の名刺の写真) と自分の名刺の写真。
 * iOS `ProducerCardFiles` と対。
 *
 * 写真は**端末の中だけ** (バックアップにもクラウドにも載せない。アイドルの画像と同じ扱いで、
 * res/xml の Auto Backup からも外す)。置き場所は `filesDir/producer_cards/<名刺の id>/`。
 * 名刺を消したら丸ごと消す。
 */
object ProducerCardFiles {
    /** filesDir の下の置き場所の名前 (Auto Backup の除外と対。BackupRulesTest が突き合わせる)。 */
    const val DIRECTORY_NAME = "producer_cards"

    /** 自分の名刺の写真の置き場所 (filesDir の下。名刺入れとは別のフォルダ。Auto Backup から外す)。 */
    const val MY_DIRECTORY_NAME = "producer_card_me"

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

    /** 受け取った画像 (担当の画像・名刺の写真) を書く。同じ担当の画像・写真は新しいもので置き換える。 */
    fun saveImages(context: Context, cardId: String, images: List<CardFileImage>) {
        if (images.isEmpty()) return
        folder(context, cardId).mkdirs()
        for (image in images) {
            val target = when (image.kind) {
                CardFileImageKind.OSHI -> oshiFile(context, cardId, image.idolId)
                CardFileImageKind.PHOTO -> cardPhotoFile(context, cardId)
            }
            writeAtomically(target, image.jpeg)
        }
    }

    // ---- 受け取った名刺の写真 (相手が名刺に載せた写真) ----

    private fun cardPhotoFile(context: Context, cardId: String): File = File(folder(context, cardId), "card_photo.jpg")

    /** 受け取った名刺の写真 (画面の `imageUrl` に渡す形)。無ければ null。 */
    fun cardPhotoUrl(context: Context, cardId: String): String? =
        cardPhotoFile(context, cardId).takeIf { it.exists() }?.let { Uri.fromFile(it).toString() }

    // ---- 自分の名刺の写真 ----

    private fun myFolder(context: Context): File = File(context.filesDir, MY_DIRECTORY_NAME)

    /**
     * 名刺に載せる写真 (切り抜いた後の JPEG)。名刺ファイルで相手にもこの画質で渡る。
     * 名前は書くたびに変える (画像の読み込みの控えが古い写真を出し続けないように)。
     */
    fun myPhotoFile(context: Context): File? =
        myFolder(context).listFiles()?.firstOrNull { it.name.startsWith("photo-") && it.name.endsWith(".jpg") }

    fun myPhotoUrl(context: Context): String? = myPhotoFile(context)?.let { Uri.fromFile(it).toString() }

    /** 切り抜く前の写真 (位置を直すとき用)。 */
    fun myPhotoSourceFile(context: Context): File? =
        File(myFolder(context), "photo_source.jpg").takeIf { it.exists() }

    /** 切り抜きの位置と拡大。 */
    fun myPhotoCrop(context: Context): ImasPortraitCrop? = runCatching {
        ImasPortraitCrop.fromJson(File(myFolder(context), "photo_crop.json").readText())
    }.getOrNull()

    /** 自分の名刺の写真を書く (元の写真・切り抜き・切り抜いた JPEG)。 */
    fun saveMyPhoto(context: Context, source: Bitmap, crop: ImasPortraitCrop) {
        val cropped = crop.render(source) ?: return
        val photo = jpeg(cropped, maxPixels = 1600) ?: return
        val original = jpeg(source, maxPixels = 3000) ?: return
        val dir = myFolder(context).apply { mkdirs() }
        writeAtomically(File(dir, "photo_source.jpg"), original)
        writeAtomically(File(dir, "photo_crop.json"), crop.toJson().toByteArray())
        val previous = myPhotoFile(context)
        writeAtomically(File(dir, "photo-${UUID.randomUUID().toString().take(8)}.jpg"), photo)
        previous?.delete()
    }

    fun deleteMyPhoto(context: Context) {
        myFolder(context).deleteRecursively()
    }

    /** 切り抜く前の写真を開く (長辺 3200px 程度まで間引く)。 */
    fun decodeMyPhotoSource(context: Context): Bitmap? = myPhotoSourceFile(context)?.let { decodeBounded(it) }

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
