package com.fugaif.imaslivedb.data.repository

import androidx.room.Room
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.UserMark
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 文字を持つマーク (習熟度・座席) の読み出し。
 *
 * iOS は習熟度・座席・メモを `bool_value = false` のまま `text_value` に値を入れて保存する。
 * その行はバックアップ (ファイル・引き継ぎコード) で Android にそのまま入るので、
 * `bool_value = 1` で絞って読むと、iOS から持ってきた習熟度と座席が消えて見える。
 * 読むかどうかはコアの規則 (`backup_meaningful_mark_indices`: bool が true か、文字に空白以外がある)
 * で決める。
 */
@RunWith(RobolectricTestRunner::class)
class UserMarkTextMarksTest {

    private lateinit var db: AppDatabase
    private lateinit var marks: UserMarkRepository

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(RuntimeEnvironment.getApplication(), AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        marks = UserMarkRepository(db)
    }

    @After
    fun tearDown() {
        db.close()
    }

    /** iOS の形 (bool が false・段階は文字) の習熟度も読める。 */
    @Test
    fun masteryWrittenByIosIsRead() = runBlocking {
        insert(UserMark.SONG, "ios_song", UserMark.MASTERY, bool = false, text = "3")
        insert(UserMark.SONG, "android_song", UserMark.MASTERY, bool = true, text = "5")

        assertEquals(mapOf("ios_song" to 3.toUByte(), "android_song" to 5.toUByte()), marks.masteryLevels())
    }

    /** 未設定に戻した行 (文字が空・空白だけ) と 0 段は数えない。 */
    @Test
    fun clearedMasteryIsNotRead() = runBlocking {
        insert(UserMark.SONG, "empty", UserMark.MASTERY, bool = false, text = null)
        insert(UserMark.SONG, "blank", UserMark.MASTERY, bool = false, text = "  ")
        insert(UserMark.SONG, "zero", UserMark.MASTERY, bool = true, text = "0")

        assertEquals(emptyMap<String, UByte>(), marks.masteryLevels())
    }

    /** iOS の形の座席メモも読める。空白だけなら無い扱い。 */
    @Test
    fun seatWrittenByIosIsRead() = runBlocking {
        insert(UserMark.SHOW, "sh_1", UserMarkRepository.SEAT, bool = false, text = "アリーナ A3")
        insert(UserMark.SHOW, "sh_2", UserMarkRepository.SEAT, bool = false, text = " ")

        assertEquals("アリーナ A3", marks.seat(UserMark.SHOW, "sh_1"))
        assertNull(marks.seat(UserMark.SHOW, "sh_2"))
        assertNull(marks.seat(UserMark.SHOW, "sh_none"))
    }

    /** 「メモあり」の一覧 (印と絞り込み) は、iOS の形のメモを拾い、空白だけのメモは拾わない。 */
    @Test
    fun notedIdsFollowTheCoreRule() = runBlocking {
        insert(UserMark.SONG, "ios_note", UserMark.MEMO, bool = false, text = "イントロで泣く")
        insert(UserMark.SONG, "blank_note", UserMark.MEMO, bool = false, text = "  ")
        insert(UserMark.SONG, "cleared_note", UserMark.MEMO, bool = false, text = null)
        insert(UserMark.IDOL, "idol_note", UserMark.MEMO, bool = false, text = "担当候補")

        assertEquals(setOf("ios_note"), marks.notedIds(UserMark.SONG))
        assertEquals(setOf("idol_note"), marks.notedIdolIds())
        assertEquals("イントロで泣く", marks.note(UserMark.SONG, "ios_note"))
        assertNull(marks.note(UserMark.SONG, "blank_note"))
    }

    /** Android が書いた値は今までどおり読める (書き込みは bool = true のまま)。 */
    @Test
    fun valuesWrittenByAndroidRoundTrip() = runBlocking {
        marks.setMastery("s1", 4.toUByte())
        marks.setSeat(UserMark.SHOW, "sh_1", "2階 B12")

        assertEquals(mapOf("s1" to 4.toUByte()), marks.masteryLevels())
        assertEquals("2階 B12", marks.seat(UserMark.SHOW, "sh_1"))
    }

    private suspend fun insert(type: String, id: String, kind: String, bool: Boolean, text: String?) =
        db.userMarkDao().upsert(UserMark(type, id, kind, bool, text, "2026-01-01T00:00:00Z"))
}
