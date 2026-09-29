package com.fugaif.imaslivedb.widget

import com.fugaif.imaslivedb.data.image.GalleryKind
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File

/**
 * ウィジェットの設定画面は DatabaseBoot を通らずに開かれる。マスタのスナップショットを
 * 読めなくても落ちず、候補を空にする (RedTeam A-L4)。
 */
@RunWith(RobolectricTestRunner::class)
class OshiCatalogTest {

    @Test
    fun candidatesAreEmptyWhenTheSnapshotCannotBeRead() = runBlocking {
        val app = RuntimeEnvironment.getApplication()
        // 画像はあるが、マスタの DB が読めない (壊れている・移行の途中など)。
        File(app.filesDir, "${GalleryKind.IDOL.directoryName}/cg_test").apply { mkdirs() }
            .resolve("a.jpg").writeBytes(byteArrayOf(1))
        app.getDatabasePath("master.sqlite").apply { parentFile?.mkdirs() }.writeText("not a database")

        assertEquals(emptyList<OshiCandidate>(), OshiCatalog.candidates(app))
    }
}
