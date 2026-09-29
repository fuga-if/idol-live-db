package com.fugaif.imaslivedb.data.image

import android.content.Context
import com.fugaif.imaslivedb.R
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.xmlpull.v1.XmlPullParser

/**
 * 取り込んだキャラクター画像は Auto Backup (クラウド) に載せない。画像のディレクトリ名を
 * 変えたときに、バックアップの除外だけが古い名前のまま残らないよう、ここで突き合わせる。
 */
@RunWith(RobolectricTestRunner::class)
class BackupRulesTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private val imageDirectories =
        (GalleryKind.entries.map { it.directoryName } + CustomImageStore.BRAND_DIRECTORY_NAME)
            .map { "$it/" }.toSet()

    @Test
    fun cloudBackupExcludesAllImageDirectories() {
        assertEquals(imageDirectories, excludedFiles(R.xml.data_extraction_rules, section = "cloud-backup"))
    }

    @Test
    fun legacyFullBackupExcludesAllImageDirectories() {
        assertEquals(imageDirectories, excludedFiles(R.xml.backup_rules, section = null))
    }

    /** [section] (null なら全体) の中の `<exclude domain="file">` の path。 */
    private fun excludedFiles(xml: Int, section: String?): Set<String> {
        val parser = context.resources.getXml(xml)
        val paths = mutableSetOf<String>()
        var inSection = section == null
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> when {
                    parser.name == section -> inSection = true
                    inSection && parser.name == "exclude" &&
                        parser.getAttributeValue(null, "domain") == "file" ->
                        paths += parser.getAttributeValue(null, "path")
                }
                XmlPullParser.END_TAG -> if (parser.name == section) inSection = false
            }
        }
        return paths
    }
}
