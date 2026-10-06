package com.fugaif.imaslivedb.ui.designsystem

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 名刺の写真の切り抜き (iOS `ImasPortraitCrop`)。 */
@RunWith(RobolectricTestRunner::class)
class ImasPortraitCropTest {

    @Test
    fun fitsTheFrameAtZoomOne() {
        // 横長の写真 (4000×3000) は高さいっぱい・枠の比の幅で真ん中を切る (P名刺は正方形・前の版の 3:4)。
        val resume = ImasPortraitCrop().rect(4000f, 3000f, ImasPortraitCrop.Frame.RESUME)
        assertEquals(2250f, resume.width, 0.5f)
        assertEquals(3000f, resume.height, 0.5f)
        assertEquals(875f, resume.left, 0.5f)
        assertEquals(0f, resume.top, 0.5f)
        val card = ImasPortraitCrop().rect(4000f, 3000f, ImasPortraitCrop.Frame.CARD)
        assertEquals(3000f, card.width, 0.5f)
        assertEquals(3000f, card.height, 0.5f)
        assertEquals(500f, card.left, 0.5f)
    }

    /** 前の版の 3:4 の切り抜き (拡大と真ん中) は、正方形の枠でも真ん中を保ったまま読み替える。 */
    @Test
    fun oldPortraitCropKeepsCenterInSquareFrame() {
        val old = ImasPortraitCrop(zoom = 1.5f, centerX = 0.4f, centerY = 0.35f)
        val resume = old.rect(3000f, 4000f, ImasPortraitCrop.Frame.RESUME)
        val square = old.rect(3000f, 4000f, ImasPortraitCrop.Frame.CARD)
        assertEquals(square.width, square.height, 0.5f)
        assertEquals(resume.centerX, square.centerX, 0.5f)
        assertEquals(resume.centerY, square.centerY, 0.5f)
    }

    @Test
    fun rendersAtTheFrameOutputSize() {
        val image = android.graphics.Bitmap.createBitmap(400, 300, android.graphics.Bitmap.Config.ARGB_8888)
        for (frame in ImasPortraitCrop.Frame.entries) {
            val out = ImasPortraitCrop().render(image, frame)!!
            assertEquals(frame.outputWidth, out.width)
            assertEquals(frame.outputHeight, out.height)
        }
    }

    @Test
    fun clampsTheCenterInsideThePhoto() {
        val frame = ImasPortraitCrop.Frame.CARD
        val c = ImasPortraitCrop(zoom = 2f, centerX = 0f, centerY = 1f).clamped(4000f, 3000f, frame)
        val r = c.rect(4000f, 3000f, frame)
        assertEquals(0f, r.left, 0.5f)
        assertEquals(3000f, r.top + r.height, 0.5f)
        assertEquals(ImasPortraitCrop.MAX_ZOOM, ImasPortraitCrop(zoom = 9f).clamped(100f, 100f, frame).zoom, 0f)
    }

    @Test
    fun roundTripsThroughJson() {
        val c = ImasPortraitCrop(zoom = 1.5f, centerX = 0.25f, centerY = 0.75f)
        assertEquals(c, ImasPortraitCrop.fromJson(c.toJson()))
    }
}
