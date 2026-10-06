package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlin.math.max
import uniffi.imas_core.CardPhotoShape
import uniffi.imas_core.CardPhotoSource
import uniffi.imas_core.cardPhotoShape
import uniffi.imas_core.cardPhotoSourceKey

/**
 * プロフィール帳の証明写真の欄に入れる、プロフィール帳だけの画像 (P名刺の写真とは別)。iOS `ProfileSheetFiles` と対。
 *
 * 置き場所は `filesDir/profile_sheet_photo/`。切り抜く前の元・切り抜きの位置と拡大・切り抜いた JPEG を持つ
 * (P名刺の写真と同じ形)。画像は**端末の中だけ** (アプリのバックアップにも Auto Backup にも載せない)。
 * 無ければ証明写真の欄は P名刺の写真を使う。
 */
object ProfileSheetFiles {
    const val DIRECTORY_NAME = "profile_sheet_photo"

    private fun folder(context: Context): File = File(context.filesDir, DIRECTORY_NAME)

    /** 切り抜いた後の JPEG。名前は書くたびに変える (画像の読み込みの控えが古い写真を出し続けないように)。 */
    fun photoFile(context: Context): File? =
        folder(context).listFiles()?.firstOrNull { it.name.startsWith("photo-") && it.name.endsWith(".jpg") }

    /** 切り抜く前の元 (位置を直すとき用)。 */
    fun sourceFile(context: Context): File? = File(folder(context), "photo_source.jpg").takeIf { it.exists() }

    fun crop(context: Context): ImasPortraitCrop? = runCatching {
        ImasPortraitCrop.fromJson(File(folder(context), "photo_crop.json").readText())
    }.getOrNull()

    /** 写真の出どころ (写真から選んだ写真か X のアイコン)。 */
    fun source(context: Context): CardPhotoSource =
        ProducerCardFiles.readPhotoSource(File(folder(context), "photo_source_kind.txt"))

    /** 切り抜く枠。X のアイコンは丸く出すので正方形で切り、証明写真の欄 (3:4) の中に丸く置く。 */
    fun cropFrame(origin: CardPhotoSource): ImasPortraitCrop.Frame =
        if (cardPhotoShape(origin) == CardPhotoShape.ROUND) ImasPortraitCrop.Frame.CARD else ImasPortraitCrop.Frame.RESUME

    /** 書く (元・切り抜き・出どころ・切り抜いた JPEG)。書けなければ投げる。 */
    fun save(context: Context, source: Bitmap, crop: ImasPortraitCrop, origin: CardPhotoSource) {
        val cropped = crop.render(source, cropFrame(origin)) ?: throw IOException("写真を切り抜けませんでした")
        val photo = ProducerCardFiles.jpeg(cropped, maxPixels = 1600) ?: throw IOException("写真を書き出せませんでした")
        val original = ProducerCardFiles.jpeg(source, maxPixels = 3000) ?: throw IOException("写真を書き出せませんでした")
        val dir = folder(context).apply { mkdirs() }
        File(dir, "photo_source.jpg").writeBytes(original)
        File(dir, "photo_crop.json").writeText(crop.toJson())
        File(dir, "photo_source_kind.txt").writeText(cardPhotoSourceKey(origin))
        val name = "photo-${UUID.randomUUID().toString().take(8)}.jpg"
        File(dir, name).writeBytes(photo)
        // 前の写真をすべて片付ける (2 つ残るとどちらが出るか決まらない)。
        dir.listFiles()?.filter { it.name.startsWith("photo-") && it.name != name }?.forEach {
            if (!it.delete()) throw IOException("前の写真を消せませんでした")
        }
    }

    /** 消す (証明写真の欄は P名刺の写真に戻る)。 */
    fun delete(context: Context) {
        folder(context).deleteRecursively()
    }

    /** 証明写真の欄に入れる画像のファイル: プロフィール帳の画像、無ければ P名刺の写真。 */
    fun effectiveFile(context: Context): File? = photoFile(context) ?: ProducerCardFiles.myPhotoFile(context)

    fun effectiveUrl(context: Context): String? = effectiveFile(context)?.let { Uri.fromFile(it).toString() }

    /** 証明写真の欄に入れる画像を丸く置くか (X のアイコン。切り方はコアの `cardPhotoShape`)。 */
    fun effectiveRound(context: Context): Boolean {
        val source = if (photoFile(context) != null) source(context) else ProducerCardFiles.myPhotoSource(context)
        return cardPhotoShape(source) == CardPhotoShape.ROUND
    }

    /** 切り抜く前の元を開く (長辺 3200px 程度まで間引く)。 */
    fun decodeSource(context: Context): Bitmap? = sourceFile(context)?.let { decodeBounded(it, 3200) }

    /**
     * 書き出しに焼く小さな画像 (長辺 [maxPixels] 程度まで)。焼くのは今描かれているものだけで読み込みを待たないので、
     * 刷る前に読んでおく。大きな写真を丸ごと読まない。
     */
    fun decodeBounded(file: File, maxPixels: Int): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixels) sample *= 2
        BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()
}
