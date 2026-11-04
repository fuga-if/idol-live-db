package com.fugaif.imaslivedb.data.producercard

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * 名刺の素材の背景を切り抜く (写っている人や物だけを残した透過の画像にする)。iOS `StickerCutout` と対。
 * 端末の中だけで切り抜く (ML Kit の被写体の切り出し。モデルは Play 開発者サービスが端末に取る。画像をどこにも送らない)。
 */
object StickerCutout {
    sealed class Failure : Exception() {
        /** 切り抜ける人や物が見つからなかった。 */
        data object NoSubject : Failure()

        /** 端末が切り抜きに対応していない (モデルを取れない)・画像を読めなかった。 */
        data object Unavailable : Failure()
    }

    /** 前景だけを残した画像 (被写体の外接に切り詰める)。 */
    suspend fun cutout(image: Bitmap): Bitmap = withContext(Dispatchers.Default) {
        val options = SubjectSegmenterOptions.Builder().enableForegroundBitmap().build()
        val segmenter = SubjectSegmentation.getClient(options)
        try {
            val foreground = suspendCancellableCoroutine<Bitmap?> { cont ->
                segmenter.process(InputImage.fromBitmap(image, 0))
                    .addOnSuccessListener { cont.resume(it.foregroundBitmap) }
                    .addOnFailureListener { cont.resume(null) }
            } ?: throw Failure.Unavailable
            crop(foreground) ?: throw Failure.NoSubject
        } finally {
            segmenter.close()
        }
    }

    /** 透けていない所の外接で切り詰める (全部透けていれば null)。 */
    private fun crop(bitmap: Bitmap): Bitmap? {
        val w = bitmap.width
        val h = bitmap.height
        val row = IntArray(w)
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for (y in 0 until h) {
            bitmap.getPixels(row, 0, w, 0, y, w, 1)
            for (x in 0 until w) {
                if ((row[x] ushr 24) > 8) {
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (maxX < minX || maxY < minY) return null
        return Bitmap.createBitmap(bitmap, minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}
