package com.fugaif.imaslivedb.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 回収数/回収率ソートの母集合が「スナップショット経路と SQL フォールバックで一致する」
 * ことを守る回帰テスト。
 *
 * 背景: 一覧バッジ用の fetchSongCollectedCounts は現地参加 (text_value NULL/'live') +
 * リアルライブ (event.kind live/festival) 限定だが、ソートの母集合は iOS
 * attendedSongCountMap と同じ「参加種別・イベント kind 無制限」が確定仕様。
 * 過去にフォールバック側だけバッジ用マップを流用し、配信参加マークを持つユーザーの
 * 並び順が経路間 (.so 無しビルド・load 失敗時・初回同期前) で食い違う退行があった。
 *
 * ソーステキスト検証なのは制約による: Room の @Query は BINARY retention で
 * リフレクションから読めず、Room 自体も JVM 単体テストでは動かない (Robolectric 未導入)。
 * ファイル移動時はパス解決が fail して気づけるので、定数を更新すること。
 */
class SongCollectedSortParityTest {

    @Test
    fun fallbackSortUsesUnrestrictedAttendedCounts() {
        val fallback = fallbackRegion(sourceOf(REPOSITORY_PATH))
        // COLLECTED_COUNT と COLLECTED_RATE の 2 箇所が無制限の attended マップを使う
        assertEquals(
            "フォールバックの回収数系ソートは fetchAttendedSongCounts (無制限) を 2 箇所で使う",
            2,
            Regex("""fetchAttendedSongCounts\(\)""").findAll(fallback).count()
        )
        // バッジ用 (現地 + リアルライブ限定) マップの流用が復活していないこと
        assertFalse(
            "フォールバックのソートにバッジ用 fetchSongCollectedCounts を流用してはいけない",
            fallback.contains("fetchSongCollectedCounts()")
        )
    }

    @Test
    fun attendedCountQueryHasNoAttendanceTypeOrEventKindFilter() {
        // iOS AppDatabase.attendedSongCountMap と同じく、参加種別もイベント kind も絞らない
        val query = daoQueryOf("fetchAttendedSongCounts")
        assertFalse("ソート用クエリは参加種別 (text_value) を絞らない", query.contains("text_value"))
        assertFalse("ソート用クエリはイベント kind を絞らない", query.contains("kind IN"))
    }

    @Test
    fun badgeQueryKeepsItsRestrictions() {
        // 逆方向の退行防止: バッジ (行アイコン / 回収済みフィルタ) は現地 + リアルライブ限定のまま
        val query = daoQueryOf("fetchSongCollectedCounts")
        assertTrue("バッジ用クエリは現地参加 (text_value) 限定を維持する", query.contains("text_value"))
        assertTrue("バッジ用クエリはリアルライブ限定を維持する", query.contains("('live', 'festival')"))
    }

    /** fetchSongs の SQL フォールバック部分 (スナップショット経路のヘルパは含めない)。 */
    private fun fallbackRegion(source: String): String {
        val start = source.indexOf("以下フォールバック")
        val end = source.indexOf("private suspend fun fetchSongsViaSnapshot")
        require(start in 0 until end) { "SongRepository のフォールバック区間が見つからない (構造変更ならテストを更新して)" }
        return source.substring(start, end)
    }

    /** SongDao の指定関数直前の @Query ブロックを取り出す。 */
    private fun daoQueryOf(function: String): String {
        val source = sourceOf(DAO_PATH)
        val fn = source.indexOf("suspend fun $function")
        require(fn >= 0) { "SongDao.$function が見つからない (改名ならテストを更新して)" }
        val query = source.lastIndexOf("@Query", fn)
        require(query >= 0) { "SongDao.$function の @Query が見つからない" }
        return source.substring(query, fn)
    }

    private fun sourceOf(relative: String): String {
        // Gradle の JVM テストは作業ディレクトリがモジュール (app/) だが、
        // IDE から実行するとリポジトリルートのこともあるので両方を辿る。
        val file = listOf(File(relative), File("app/$relative")).firstOrNull { it.isFile }
            ?: error("ソースが見つからない (ファイル移動ならパス定数を更新して): $relative")
        return file.readText()
    }

    companion object {
        private const val REPOSITORY_PATH =
            "src/main/kotlin/com/fugaif/imaslivedb/data/repository/SongRepository.kt"
        private const val DAO_PATH =
            "src/main/kotlin/com/fugaif/imaslivedb/data/db/dao/SongDao.kt"
    }
}
