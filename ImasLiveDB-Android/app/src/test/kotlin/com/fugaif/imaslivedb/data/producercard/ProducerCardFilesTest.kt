package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.CardFileImageKind

/** 名刺の画像の置き方 (iOS `ProducerCardStoreTests` の画像の部分と対)。 */
@RunWith(RobolectricTestRunner::class)
class ProducerCardFilesTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    @After
    fun cleanUp() {
        ProducerCardFiles.deleteAll(context, "c1")
        ProducerCardFiles.deleteMyPhoto(context)
        ProducerCardFiles.deleteMyFace(context, ProducerCardFiles.Side.FRONT)
        ProducerCardFiles.deleteMyFace(context, ProducerCardFiles.Side.BACK)
    }

    /** 名刺ファイルの自作の画像 (表・裏) は受け取った名刺の顔として書き、写真とは混ぜない。表が届けば前の裏は捨てる。 */
    @Test
    fun receivedFaceImagesAreStored() {
        val jpeg = byteArrayOf(-1, -40, -1, 2)
        ProducerCardFiles.saveImages(
            context, "c1",
            listOf(
                CardFileImage(idolId = "", jpeg = jpeg, kind = CardFileImageKind.FACE_FRONT),
                CardFileImage(idolId = "", jpeg = jpeg, kind = CardFileImageKind.FACE_BACK)
            )
        )
        assertNotNull(ProducerCardFiles.faceUrl(context, "c1", ProducerCardFiles.Side.FRONT))
        assertNotNull(ProducerCardFiles.faceUrl(context, "c1", ProducerCardFiles.Side.BACK))
        assertNull(ProducerCardFiles.cardPhotoUrl(context, "c1"))

        // 裏を外して送り直した名刺 (表だけ) を受け取ると、古い裏は残らない。
        ProducerCardFiles.saveImages(context, "c1", listOf(CardFileImage(idolId = "", jpeg = jpeg, kind = CardFileImageKind.FACE_FRONT)))
        assertNotNull(ProducerCardFiles.faceUrl(context, "c1", ProducerCardFiles.Side.FRONT))
        assertNull(ProducerCardFiles.faceUrl(context, "c1", ProducerCardFiles.Side.BACK))
    }

    /** 自分の自作の画像は書くたびに名前が変わり、前の画像は残らない。消すと無くなる。 */
    @Test
    fun myFaceIsReplacedAndRemoved() {
        val image = Bitmap.createBitmap(91, 55, Bitmap.Config.ARGB_8888)
        assertNull(ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.FRONT))
        ProducerCardFiles.saveMyFace(context, image, ProducerCardFiles.Side.FRONT)
        val first = ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.FRONT)!!
        ProducerCardFiles.saveMyFace(context, image, ProducerCardFiles.Side.FRONT)
        val second = ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.FRONT)!!
        assertEquals(false, first.exists())
        assertEquals(true, second.exists())
        assertNull("裏は別", ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.BACK))
        ProducerCardFiles.deleteMyFace(context, ProducerCardFiles.Side.FRONT)
        assertNull(ProducerCardFiles.myFaceFile(context, ProducerCardFiles.Side.FRONT))
    }

    @Test
    fun receivedPhotoIsNotMixedWithOshiImages() {
        val oshi = byteArrayOf(1, 2, 3)
        val photo = byteArrayOf(4, 5, 6)
        ProducerCardFiles.saveImages(
            context, "c1",
            listOf(
                CardFileImage(idolId = "765_haruka", jpeg = oshi, kind = CardFileImageKind.OSHI),
                CardFileImage(idolId = "", jpeg = photo, kind = CardFileImageKind.PHOTO)
            )
        )
        assertNotNull(ProducerCardFiles.oshiImageUrl(context, "c1", "765_haruka"))
        assertNull("写真が担当の画像 (id 空) として書かれない", ProducerCardFiles.oshiImageUrl(context, "c1", ""))
        val url = ProducerCardFiles.cardPhotoUrl(context, "c1")
        assertNotNull(url)
        assertArrayEquals(photo, java.io.File(android.net.Uri.parse(url).path!!).readBytes())
    }

    @Test
    fun myPhotoIsSavedWithItsCropAndRemoved() {
        assertNull(ProducerCardFiles.myPhotoFile(context))
        val source = Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888)
        val crop = ImasPortraitCrop(zoom = 1.5f, centerX = 0.4f, centerY = 0.5f)
        ProducerCardFiles.saveMyPhoto(context, source, crop)
        val first = ProducerCardFiles.myPhotoFile(context)
        assertNotNull(first)
        assertNotNull(ProducerCardFiles.myPhotoSourceFile(context))
        assertEquals(crop, ProducerCardFiles.myPhotoCrop(context))

        // 書き直すと名前が変わり、前の写真は残らない (読み込みの控えが古い写真を出さない)。
        ProducerCardFiles.saveMyPhoto(context, source, ImasPortraitCrop())
        val second = ProducerCardFiles.myPhotoFile(context)
        assertNotNull(second)
        assertEquals(false, first!!.exists())

        ProducerCardFiles.deleteMyPhoto(context)
        assertNull(ProducerCardFiles.myPhotoFile(context))
        assertNull(ProducerCardFiles.myPhotoCrop(context))
    }
}
