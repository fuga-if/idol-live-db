package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import kotlin.math.max
import kotlin.math.roundToInt
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import java.util.UUID
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.CardFileImageKind
import uniffi.imas_core.CardPhotoShape
import uniffi.imas_core.CardPhotoSource
import uniffi.imas_core.cardPhotoShape
import uniffi.imas_core.cardPhotoSourceFromKey
import uniffi.imas_core.cardPhotoSourceKey

/**
 * 名刺入れの画像ファイル (受け取った担当の画像・名刺の写真・紙の名刺の写真・自作の名刺の画像) と、
 * 自分の名刺の写真・自作の名刺の画像。
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

    /**
     * 自分の自作の名刺の画像の置き場所 (filesDir の下。写真のフォルダとは別で、写真を外しても画像は残す。
     * Auto Backup から外す)。
     */
    const val MY_FACE_DIRECTORY_NAME = "producer_card_face"

    /**
     * 前の版のプロフィール帳だけの写真の置き場所 (filesDir の下)。プロフィール帳は P名刺の画像に一本化し、
     * 写真は P名刺の写真を使う。残っていれば P名刺の画面を開いたときに片付ける ([removeLegacyProfileSheetPhoto])。
     * 片付けるまでは Auto Backup から外したまま (BackupRulesTest が突き合わせる)。
     */
    const val LEGACY_PROFILE_SHEET_DIRECTORY_NAME = "profile_sheet_photo"

    /** 名刺の面 (紙の名刺の写真・自作の名刺の画像)。 */
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

    /**
     * 受け取った画像 (担当の画像・名刺の写真・自作の名刺の画像) を書く。同じ担当の画像・写真・面は
     * 新しいもので置き換える。
     */
    fun saveImages(context: Context, cardId: String, images: List<CardFileImage>) {
        if (images.isEmpty()) return
        folder(context, cardId).mkdirs()
        // 表が届いたら前の裏は捨てる (相手が裏を外した名刺を送り直したとき、古い裏を出し続けない)。
        if (images.any { it.kind == CardFileImageKind.FACE_FRONT }) faceFile(context, cardId, Side.BACK).delete()
        for (image in images) {
            when (image.kind) {
                CardFileImageKind.OSHI -> writeAtomically(oshiFile(context, cardId, image.idolId), image.jpeg)
                CardFileImageKind.PHOTO -> {
                    writeCardPhoto(context, cardId, image.jpeg)
                    // 写真の出どころ (X のアイコンなら丸く出す)。写真から選んだ写真は書かない (無ければ写真から選んだ写真)。
                    val source = image.photoSource ?: CardPhotoSource.PICKED
                    val file = cardPhotoSourceFile(context, cardId)
                    if (source == CardPhotoSource.PICKED) file.delete()
                    else writeAtomically(file, cardPhotoSourceKey(source).toByteArray())
                }
                CardFileImageKind.FACE_FRONT -> writeAtomically(faceFile(context, cardId, Side.FRONT), image.jpeg)
                CardFileImageKind.FACE_BACK -> writeAtomically(faceFile(context, cardId, Side.BACK), image.jpeg)
            }
        }
    }

    // ---- 受け取った自作の名刺の画像 (相手が自分で作った名刺の表・裏) ----

    private fun faceFile(context: Context, cardId: String, side: Side): File =
        File(folder(context, cardId), "face_${side.key}.jpg")

    /** 受け取った自作の名刺の画像 (画面の `imageUrl` に渡す形)。無ければ null。 */
    fun faceUrl(context: Context, cardId: String, side: Side): String? =
        faceFile(context, cardId, side).takeIf { it.exists() }?.let { Uri.fromFile(it).toString() }

    // ---- 受け取った名刺の写真 (相手が名刺に載せた写真) ----

    /** 受け取った名刺の写真。名前は書くたびに変える (画像の読み込みの控えが前の写真を出し続けないように)。 */
    private fun cardPhotoFile(context: Context, cardId: String): File? =
        folder(context, cardId).listFiles()?.firstOrNull { it.name.startsWith("card_photo") && it.name.endsWith(".jpg") }

    private fun writeCardPhoto(context: Context, cardId: String, jpeg: ByteArray) {
        val name = "card_photo-${UUID.randomUUID().toString().take(8)}.jpg"
        writeAtomically(File(folder(context, cardId), name), jpeg)
        folder(context, cardId).listFiles()?.filter { it.name.startsWith("card_photo") && it.name != name }?.forEach { it.delete() }
    }

    /** 受け取った名刺の写真 (画面の `imageUrl` に渡す形)。無ければ null。 */
    fun cardPhotoUrl(context: Context, cardId: String): String? =
        cardPhotoFile(context, cardId)?.let { Uri.fromFile(it).toString() }

    private fun cardPhotoSourceFile(context: Context, cardId: String): File = File(folder(context, cardId), "card_photo_source.txt")

    /** 受け取った名刺の写真の出どころ (届いたまま。無ければ写真から選んだ写真)。 */
    fun cardPhotoSource(context: Context, cardId: String): CardPhotoSource = readPhotoSource(cardPhotoSourceFile(context, cardId))

    /** 受け取った名刺の写真を丸く出すか (切り方はコアの `cardPhotoShape`)。 */
    fun cardPhotoRound(context: Context, cardId: String): Boolean =
        cardPhotoShape(cardPhotoSource(context, cardId)) == CardPhotoShape.ROUND

    /** 写真の出どころのキーのファイルを読む (キーの読み方はコア。無ければ写真から選んだ写真)。 */
    fun readPhotoSource(file: File): CardPhotoSource =
        cardPhotoSourceFromKey(runCatching { file.readText() }.getOrDefault(""))

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

    /** 名刺の写真の出どころ (写真から選んだ写真か X のアイコン)。前の版で選んだ写真は写真から選んだ写真。 */
    fun myPhotoSource(context: Context): CardPhotoSource = readPhotoSource(File(myFolder(context), "photo_source_kind.txt"))

    /** 自分の名刺の写真を丸く出すか (切り方はコアの `cardPhotoShape`)。 */
    fun myPhotoRound(context: Context): Boolean = cardPhotoShape(myPhotoSource(context)) == CardPhotoShape.ROUND

    /** 切り抜きの位置と拡大。前の版の 3:4 の切り抜きも、正方形の枠で真ん中を保ったまま読み替える。 */
    fun myPhotoCrop(context: Context): ImasPortraitCrop? = runCatching {
        ImasPortraitCrop.fromJson(File(myFolder(context), "photo_crop.json").readText())
    }.getOrNull()

    /**
     * 自分の名刺の写真を書く (元の写真・切り抜き・出どころ・切り抜いた正方形の JPEG)。[writeSource] = false は位置を直しただけ
     * (元の写真が残っていれば書き直さない。書き直すたびに JPEG の画質が落ちる)。書けなければ投げる。
     */
    fun saveMyPhoto(context: Context, source: Bitmap, crop: ImasPortraitCrop, origin: CardPhotoSource, writeSource: Boolean = true) {
        val cropped = crop.render(source, ImasPortraitCrop.Frame.CARD) ?: throw IOException("名刺の写真を切り抜けませんでした")
        val photo = jpeg(cropped, maxPixels = 1600) ?: throw IOException("名刺の写真を書き出せませんでした")
        val dir = myFolder(context).apply { mkdirs() }
        val sourceFile = File(dir, "photo_source.jpg")
        if (writeSource || !sourceFile.exists()) {
            val original = jpeg(source, maxPixels = 3000) ?: throw IOException("名刺の写真を書き出せませんでした")
            writeAtomically(sourceFile, original)
        }
        writeAtomically(File(dir, "photo_crop.json"), crop.toJson().toByteArray())
        writeAtomically(File(dir, "photo_source_kind.txt"), cardPhotoSourceKey(origin).toByteArray())
        val name = "photo-${UUID.randomUUID().toString().take(8)}.jpg"
        writeAtomically(File(dir, name), photo)
        // 前の写真は全部消す (途中で落ちて 2 枚残っていても、次の保存で 1 枚に戻る)。
        dir.listFiles()?.filter { it.name.startsWith("photo-") && it.name != name }?.forEach { it.delete() }
    }

    fun deleteMyPhoto(context: Context) {
        myFolder(context).deleteRecursively()
    }

    /** 切り抜く前の写真を開く (長辺 3200px 程度まで間引く)。 */
    fun decodeMyPhotoSource(context: Context): Bitmap? = myPhotoSourceFile(context)?.let { decodeBounded(it) }

    /**
     * 前の版のプロフィール帳だけの写真 (`filesDir/profile_sheet_photo/`) を片付ける。iOS `removeLegacyProfileSheetPhoto`。
     * 端末の中だけの写しで、元は端末の写真の中にある。ファイルを見るのでメインの外で呼ぶ。
     */
    fun removeLegacyProfileSheetPhoto(context: Context) {
        val dir = File(context.filesDir, LEGACY_PROFILE_SHEET_DIRECTORY_NAME)
        if (dir.exists()) dir.deleteRecursively()
    }

    // ---- 自分の自作の名刺の画像 ----

    private fun myFaceFolder(context: Context): File = File(context.filesDir, MY_FACE_DIRECTORY_NAME)

    /** その面のファイル (新しい順)。書き込みの途中で落ちて 2 枚残っても新しい方を使う。 */
    private fun myFaceFiles(context: Context, side: Side): List<File> =
        myFaceFolder(context).listFiles()
            ?.filter { it.name.startsWith("${side.key}-") && it.name.endsWith(".jpg") }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()

    /**
     * 自作の名刺の画像 (平らにして切り抜いた後の JPEG)。名刺ファイル・近くの端末で相手にこの画質で渡る。
     * 名前は書くたびに変える (画像の読み込みの控えが古い画像を出し続けないように)。
     */
    fun myFaceFile(context: Context, side: Side): File? = myFaceFiles(context, side).firstOrNull()

    fun myFaceUrl(context: Context, side: Side): String? = myFaceFile(context, side)?.let { Uri.fromFile(it).toString() }

    /** 自作の名刺の画像を書く (長辺 2000px まで。比率はそのまま)。書けなければ投げる。 */
    fun saveMyFace(context: Context, image: Bitmap, side: Side) {
        val data = jpeg(image, maxPixels = 2000, quality = 90) ?: throw IOException("自作の名刺の画像を書き出せませんでした")
        val dir = myFaceFolder(context).apply { mkdirs() }
        val previous = myFaceFiles(context, side)
        writeAtomically(File(dir, "${side.key}-${UUID.randomUUID().toString().take(8)}.jpg"), data)
        previous.forEach { it.delete() }
    }

    fun deleteMyFace(context: Context, side: Side) {
        myFaceFiles(context, side).forEach { it.delete() }
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

    /**
     * 大きな写真をそのまま開いてメモリを使い切らないよう、長辺 [maxPixels] 程度まで間引いて開く。
     * 書き出しに焼く画像も、焼くのは今描かれているものだけで読み込みを待たないので、刷る前にこれで読んでおく。
     */
    fun decodeBounded(file: File, maxPixels: Int = 3200): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixels) sample *= 2
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
