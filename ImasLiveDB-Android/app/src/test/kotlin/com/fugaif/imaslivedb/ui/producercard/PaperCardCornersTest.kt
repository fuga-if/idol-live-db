package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.ui.geometry.Offset
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 写真から選んだ紙の名刺の四隅の見つけ方 (iOS `PaperCardRectifier.detectCorners` と同じ判断)。 */
class PaperCardCornersTest {

    private val w = 200
    private val h = 160

    /** 暗い机に、白い名刺 (中心 cx, cy・幅 cw・高さ ch・deg 度回した四角) を置いた写真の明るさ。 */
    private fun photo(
        cx: Float, cy: Float, cw: Float, ch: Float, deg: Double, card: Int = 235, table: Int = 40, stripe: Int? = null
    ): IntArray {
        val rad = Math.toRadians(deg)
        val c = cos(rad).toFloat()
        val s = sin(rad).toFloat()
        return IntArray(w * h) { i ->
            val x = i % w + 0.5f - cx
            val y = i / w + 0.5f - cy
            val u = x * c + y * s
            val v = -x * s + y * c
            val inside = abs(u) <= cw / 2 && abs(v) <= ch / 2
            // 名刺には文字の点を少し入れる (塊に穴があっても四角とみなせること)。
            when {
                !inside -> table
                // 名刺の左端の色の帯 (机より明るく、紙より暗い)。
                stripe != null && u < -cw / 2 + 6 -> stripe
                (i / w) % 9 == 0 && (i % w) % 7 < 3 -> 30
                else -> card
            }
        }
    }

    private fun near(a: Offset, x: Float, y: Float) =
        assertTrue("$a は (${x / w}, ${y / h}) の近く", abs(a.x - x / w) < 0.04f && abs(a.y - y / h) < 0.04f)

    @Test
    fun findsAStraightCard() {
        val quad = PaperCardCorners.detect(photo(100f, 80f, 120f, 72f, 0.0), w, h)
        assertNotNull(quad)
        near(quad!![0], 40f, 44f)
        near(quad[1], 160f, 44f)
        near(quad[2], 160f, 116f)
        near(quad[3], 40f, 116f)
    }

    @Test
    fun findsATiltedCardInOrder() {
        val quad = PaperCardCorners.detect(photo(100f, 80f, 120f, 72f, 12.0), w, h)
        assertNotNull(quad)
        // 左上・右上・右下・左下の順。
        val q = quad!!
        assertTrue(q[0].x < q[1].x && q[3].x < q[2].x)
        assertTrue(q[0].y < q[3].y && q[1].y < q[2].y)
        assertTrue(PaperCardCorners.area(q) > 0.2f)
    }

    @Test
    fun includesAColoredBandOnTheCardEdge() {
        val quad = PaperCardCorners.detect(photo(100f, 80f, 120f, 72f, 0.0, stripe = 105), w, h)
        assertNotNull(quad)
        near(quad!![0], 40f, 44f)
        near(quad[3], 40f, 116f)
    }

    @Test
    fun aPhotoWithoutACardIsLeftAlone() {
        assertNull("何も写っていない写真", PaperCardCorners.detect(IntArray(w * h) { 128 }, w, h))
        assertNull("小さすぎる四角", PaperCardCorners.detect(photo(100f, 80f, 30f, 20f, 0.0), w, h))
    }

    @Test
    fun aCardFillingThePhotoIsNotDetected() {
        // 写真の縁に角が貼り付いた四角は名刺とみなさない (書類の検出が縁に沿った四角を返すのと同じ扱い)。
        assertNull(PaperCardCorners.detect(photo(100f, 80f, 200f, 160f, 0.0), w, h))
    }
}
