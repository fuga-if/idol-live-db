package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import androidx.compose.ui.geometry.Offset
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// =============================================================================
// 写真の名刺を平らにする。iOS `CardScanners.swift` の `PaperCardRectifier` / `PhotoQRReader` の移植。
//
// PaperCardRectifier  写真から選んだ紙の名刺の四隅を見つけ、真上から撮ったように平らにして切り抜く。
//                     書類カメラ (`rememberPaperCardCamera`) で撮ったものは切り抜き済みなので通さない。
//
// iOS は Vision の書類の検出で四隅を探す。Android は重い画像処理の部品 (OpenCV 等) を入れず、
// 縮めた写真の明るさを 2 つに分け (大津の方法)、名刺らしい塊の四隅を端の点から取る。
// 平らにするのは `Matrix.setPolyToPoly` (四隅 → 長方形の射影)。見つからなければ写真のまま。
// =============================================================================

object PaperCardRectifier {
    /** 写真の元・見つけた四隅 (無ければ null)・平らにした写真 (四隅が無ければ元の写真)。 */
    data class Result(val original: Bitmap, val corners: List<Offset>?, val image: Bitmap)

    /** 四隅を直す前の初めの形 (見つからなかったとき)。写真の内側に少し寄せた四角。 */
    val defaultCorners = listOf(Offset(0.08f, 0.08f), Offset(0.92f, 0.08f), Offset(0.92f, 0.92f), Offset(0.08f, 0.92f))

    /** 四隅を探す写真の長辺 (px)。 */
    private const val DETECT_SIZE = 256

    /** 平らにした写真の長辺の上限 (px)。 */
    private const val MAX_OUTPUT = 3000

    /** 長辺 [maxPixels] までに縮めた写真 (小さければそのまま)。 */
    fun bounded(image: Bitmap, maxPixels: Int = 2400): Bitmap {
        val longSide = max(image.width, image.height)
        if (longSide <= maxPixels) return image
        val ratio = maxPixels.toFloat() / longSide
        return Bitmap.createScaledBitmap(image, (image.width * ratio).roundToInt(), (image.height * ratio).roundToInt(), true)
    }

    suspend fun rectify(image: Bitmap): Result = withContext(Dispatchers.Default) {
        val corners = runCatching { detectCorners(image) }.getOrNull()
        val flat = corners?.let { correct(image, it) }
        if (corners == null || flat == null) Result(image, null, image) else Result(image, corners, flat)
    }

    /** 四隅を探す (左上・右上・右下・左下の順、写真の中の 0〜1)。見つからなければ null。 */
    fun detectCorners(image: Bitmap): List<Offset>? {
        val ratio = DETECT_SIZE.toFloat() / max(image.width, image.height)
        val w = max(1, (image.width * min(1f, ratio)).roundToInt())
        val h = max(1, (image.height * min(1f, ratio)).roundToInt())
        val small = if (w == image.width && h == image.height) image else Bitmap.createScaledBitmap(image, w, h, true)
        val pixels = IntArray(w * h)
        small.getPixels(pixels, 0, w, 0, 0, w, h)
        val luma = IntArray(w * h) { i ->
            val c = pixels[i]
            (((c shr 16) and 0xFF) * 299 + ((c shr 8) and 0xFF) * 587 + (c and 0xFF) * 114) / 1000
        }
        return PaperCardCorners.detect(luma, w, h)
    }

    /** 四隅を真上から見た長方形に引き伸ばす。小さすぎる・形にならないときは null。 */
    fun correct(image: Bitmap, corners: List<Offset>): Bitmap? = runCatching {
        if (corners.size != 4) return null
        val w = image.width.toFloat()
        val h = image.height.toFloat()
        val p = corners.map { Offset(it.x * w, it.y * h) }
        fun d(a: Offset, b: Offset) = hypot(a.x - b.x, a.y - b.y)
        var outW = max(d(p[0], p[1]), d(p[3], p[2]))
        var outH = max(d(p[0], p[3]), d(p[1], p[2]))
        if (outW < 32f || outH < 32f) return null
        val shrink = min(1f, MAX_OUTPUT / max(outW, outH))
        outW *= shrink
        outH *= shrink
        val src = floatArrayOf(p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y, p[3].x, p[3].y)
        val dst = floatArrayOf(0f, 0f, outW, 0f, outW, outH, 0f, outH)
        val matrix = Matrix()
        if (!matrix.setPolyToPoly(src, 0, dst, 0, 4)) return null
        val out = Bitmap.createBitmap(outW.roundToInt(), outH.roundToInt(), Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(image, matrix, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        out
    }.getOrNull()
}

/**
 * 名刺の四隅を明るさの配列から探す (Android の画像に依らない部分。単体テストで確かめる)。
 *
 * 1. 明るさを大津の方法で 2 つに分ける (白い名刺と机、または暗い名刺と明るい机)。
 * 2. 机 (写真の縁) の明るさと違う所・明るい側・暗い側それぞれの一番大きな塊のうち、写真の 3 辺以上に
 *    触れていないもの (= 背景でないもの) を名刺の候補にする (大きい順に確かめる)。
 * 3. 塊の端の点 (x+y の最小・最大、x−y の最小・最大) を四隅にする。
 * 4. 写真の縁に 2 つ以上の角が貼り付いた四角・小さすぎる四角・塊が四角を埋めていないものは名刺とみなさない。
 */
object PaperCardCorners {
    /** 縁に貼り付いているとみなす幅 (写真の幅・高さに対して)。iOS と同じ。 */
    private const val EDGE_MARGIN = 0.015f

    /** 名刺とみなす四角の最小の面積 (写真に対して)。iOS と同じ。 */
    private const val MIN_AREA = 0.08f

    /** 塊が四角をどれだけ埋めていれば四角とみなすか。 */
    private const val MIN_FILL = 0.85f
    private const val MAX_FILL = 1.15f

    fun detect(luma: IntArray, w: Int, h: Int): List<Offset>? {
        if (w < 8 || h < 8 || luma.size != w * h) return null
        val t = otsu(luma)
        val masks = listOf(
            // 机 (写真の縁の明るさ) と違う所。名刺の縁の色の帯も名刺に含められる。
            backgroundDiffers(luma, w, h),
            BooleanArray(w * h) { luma[it] > t },
            BooleanArray(w * h) { luma[it] <= t }
        )
        val candidates = masks.mapNotNull { largestBlob(it, w, h) }.sortedByDescending { it.size }
        for (blob in candidates) {
            val quad = quadOf(blob, w, h) ?: continue
            if (plausible(quad) && fills(blob, quad, w, h)) return quad
        }
        return null
    }

    /**
     * 写真の縁 (= 机) の明るさの中央値から離れた所。離れ具合のしきい値は縁のばらつき (中央値からの
     * 隔たりの中央値) の 3 倍、少なくとも 30。机に模様が多いと塊が縁に繋がり、背景として除かれる。
     */
    private fun backgroundDiffers(luma: IntArray, w: Int, h: Int): BooleanArray {
        val border = buildList {
            for (x in 0 until w) { add(luma[x]); add(luma[(h - 1) * w + x]) }
            for (y in 1 until h - 1) { add(luma[y * w]); add(luma[y * w + w - 1]) }
        }.sorted()
        val median = border[border.size / 2]
        val spread = border.map { abs(it - median) }.sorted()[border.size / 2]
        val k = max(30, spread * 3)
        return BooleanArray(w * h) { abs(luma[it] - median) > k }
    }

    /** 大津の方法のしきい値 (この値より明るいかどうかで分ける)。 */
    fun otsu(luma: IntArray): Int {
        val hist = IntArray(256)
        luma.forEach { hist[it.coerceIn(0, 255)]++ }
        val total = luma.size.toDouble()
        var sumAll = 0.0
        for (i in 0..255) sumAll += i.toDouble() * hist[i]
        var sumB = 0.0
        var wB = 0.0
        var best = 0.0
        var threshold = 127
        for (i in 0..255) {
            wB += hist[i]
            if (wB == 0.0) continue
            val wF = total - wB
            if (wF == 0.0) break
            sumB += i.toDouble() * hist[i]
            val mB = sumB / wB
            val mF = (sumAll - sumB) / wF
            val between = wB * wF * (mB - mF) * (mB - mF)
            if (between > best) {
                best = between
                threshold = i
            }
        }
        return threshold
    }

    /** 一番大きな塊 (上下左右で繋がった点の index)。写真の 3 辺以上に触れる塊は背景なので除く。 */
    private fun largestBlob(mask: BooleanArray, w: Int, h: Int): IntArray? {
        val seen = BooleanArray(w * h)
        val queue = IntArray(w * h)
        var best: IntArray? = null
        for (start in mask.indices) {
            if (!mask[start] || seen[start]) continue
            var head = 0
            var tail = 0
            queue[tail++] = start
            seen[start] = true
            var left = false
            var right = false
            var top = false
            var bottom = false
            while (head < tail) {
                val i = queue[head++]
                val x = i % w
                val y = i / w
                if (x == 0) left = true
                if (x == w - 1) right = true
                if (y == 0) top = true
                if (y == h - 1) bottom = true
                if (x > 0 && mask[i - 1] && !seen[i - 1]) { seen[i - 1] = true; queue[tail++] = i - 1 }
                if (x < w - 1 && mask[i + 1] && !seen[i + 1]) { seen[i + 1] = true; queue[tail++] = i + 1 }
                if (y > 0 && mask[i - w] && !seen[i - w]) { seen[i - w] = true; queue[tail++] = i - w }
                if (y < h - 1 && mask[i + w] && !seen[i + w]) { seen[i + w] = true; queue[tail++] = i + w }
            }
            val touches = listOf(left, right, top, bottom).count { it }
            if (touches >= 3) continue
            if (tail > (best?.size ?: 0)) best = queue.copyOf(tail)
        }
        return best
    }

    /** 塊の端の点から四隅 (左上・右上・右下・左下、0〜1)。 */
    private fun quadOf(blob: IntArray, w: Int, h: Int): List<Offset>? {
        if (blob.isEmpty()) return null
        var tl = blob[0]
        var br = blob[0]
        var tr = blob[0]
        var bl = blob[0]
        fun sum(i: Int) = i % w + i / w
        fun diff(i: Int) = i % w - i / w
        for (i in blob) {
            if (sum(i) < sum(tl)) tl = i
            if (sum(i) > sum(br)) br = i
            if (diff(i) > diff(tr)) tr = i
            if (diff(i) < diff(bl)) bl = i
        }
        return listOf(tl, tr, br, bl).map { Offset((it % w + 0.5f) / w, (it / w + 0.5f) / h) }
    }

    /** 四角の面積 (靴紐の公式、0〜1 の座標で)。 */
    fun area(quad: List<Offset>): Float {
        var a = 0f
        for (i in quad.indices) {
            val p = quad[i]
            val q = quad[(i + 1) % quad.size]
            a += p.x * q.y - q.x * p.y
        }
        return abs(a) / 2f
    }

    /** 写真の縁に 2 つ以上の角が貼り付いた四角・小さすぎる四角は名刺ではない (iOS `plausible`)。 */
    fun plausible(quad: List<Offset>): Boolean {
        val onEdge = quad.count { it.x < EDGE_MARGIN || it.x > 1 - EDGE_MARGIN || it.y < EDGE_MARGIN || it.y > 1 - EDGE_MARGIN }
        return onEdge < 2 && area(quad) >= MIN_AREA
    }

    /** 塊 (行ごとに左端から右端までを埋めた形) が四角をほぼ埋めている (= 塊が四角い)。 */
    private fun fills(blob: IntArray, quad: List<Offset>, w: Int, h: Int): Boolean {
        val minX = IntArray(h) { Int.MAX_VALUE }
        val maxX = IntArray(h) { -1 }
        for (i in blob) {
            val x = i % w
            val y = i / w
            if (x < minX[y]) minX[y] = x
            if (x > maxX[y]) maxX[y] = x
        }
        var filled = 0L
        for (y in 0 until h) if (maxX[y] >= 0) filled += maxX[y] - minX[y] + 1
        val quadArea = area(quad) * w * h
        if (quadArea <= 0f) return false
        val ratio = filled / quadArea
        return ratio in MIN_FILL..MAX_FILL
    }
}
