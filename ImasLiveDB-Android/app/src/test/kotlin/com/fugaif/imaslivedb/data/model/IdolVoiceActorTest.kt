package com.fugaif.imaslivedb.data.model

import com.fugaif.imaslivedb.data.core.VoiceActorDirectory
import com.fugaif.imaslivedb.testing.SeededDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * reseed で Room の `idols.voice_actors` (seed に無い列) が NULL になっても、CV は消えない
 * (RedTeam A-M1)。現任の声優は `idol_voice_actors` の履歴からコアが選ぶ。
 */
@RunWith(RobolectricTestRunner::class)
class IdolVoiceActorTest {

    private lateinit var seeded: SeededDatabase

    @Before
    fun setUp() {
        seeded = SeededDatabase(RuntimeEnvironment.getApplication())
        VoiceActorDirectory.install { seeded.snapshots.currentGeneration() }
    }

    @After
    fun tearDown() = seeded.close()

    @Test
    fun cvSurvivesTheReseedClearingTheDerivedColumn() = runBlocking {
        // reseed の後と同じ状態: idols.voice_actors は NULL。
        seeded.db.openHelper.writableDatabase.execSQL("UPDATE idols SET voice_actors = NULL")
        val idol = checkNotNull(seeded.db.idolDao().fetchIdol(IDOL))
        assertEquals("大木咲絵子", idol.currentVoiceActor)
    }

    private companion object {
        const val IDOL = "cg_大石泉"
    }
}
