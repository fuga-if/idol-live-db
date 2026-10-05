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
        // 横長の写真 (4000×3000) は高さいっぱい・3:4 の幅で真ん中を切る。
        val r = ImasPortraitCrop().rect(4000f, 3000f)
        assertEquals(2250f, r.width, 0.5f)
        assertEquals(3000f, r.height, 0.5f)
        assertEquals(875f, r.left, 0.5f)
        assertEquals(0f, r.top, 0.5f)
    }

    @Test
    fun clampsTheCenterInsideThePhoto() {
        val c = ImasPortraitCrop(zoom = 2f, centerX = 0f, centerY = 1f).clamped(4000f, 3000f)
        val r = c.rect(4000f, 3000f)
        assertEquals(0f, r.left, 0.5f)
        assertEquals(3000f, r.top + r.height, 0.5f)
        assertEquals(ImasPortraitCrop.MAX_ZOOM, ImasPortraitCrop(zoom = 9f).clamped(100f, 100f).zoom, 0f)
    }

    @Test
    fun roundTripsThroughJson() {
        val c = ImasPortraitCrop(zoom = 1.5f, centerX = 0.25f, centerY = 0.75f)
        assertEquals(c, ImasPortraitCrop.fromJson(c.toJson()))
    }
}
