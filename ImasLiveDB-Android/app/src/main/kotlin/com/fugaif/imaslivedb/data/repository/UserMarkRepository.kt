package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import uniffi.imas_core.BackupUserMarkRecord
import uniffi.imas_core.backupMeaningfulMarkIndices
import java.time.Instant

/** 参加が付いた (取り消しではない) 直後の通知。iOS `.attendanceMarked` 通知と対。 */
data class AttendanceMarkedEvent(val showId: String, val type: AttendanceType)

/**
 * 担当/お気に入り等のユーザーマークを管理 (端末ローカル)。
 *
 * @param onSongFavoriteChanged 曲のお気に入りを付け外ししたときに呼ぶ (みんなの集計に送る。iOS と同じ)。
 */
class UserMarkRepository(
    private val db: AppDatabase,
    private val onSongFavoriteChanged: (songId: String, value: Boolean) -> Unit = { _, _ -> }
) {

    private val dao get() = db.userMarkDao()

    private val _attendanceMarked = MutableSharedFlow<AttendanceMarkedEvent>(extraBufferCapacity = 1)

    /**
     * 参加登録の入口は複数ある (行のスワイプ / 公演の参加シート / セトリ画面) が、
     * どこから付けても [setAttendance] を必ず通るので、ここ 1 箇所に集めて流す。
     * 「チケット代を記録するか」の判断はここに持たせない (DB を引く判断なので、
     * 受け手 ([com.fugaif.imaslivedb.ui.ledger.TicketExpensePrompt]) に任せる)。
     */
    val attendanceMarked: SharedFlow<AttendanceMarkedEvent> = _attendanceMarked.asSharedFlow()

    suspend fun isOn(type: String, id: String, kind: String): Boolean = dao.isOn(type, id, kind)

    /** ON/OFF をトグルして新しい状態を返す。 */
    suspend fun toggle(type: String, id: String, kind: String): Boolean {
        val now = !dao.isOn(type, id, kind)
        if (now) {
            dao.upsert(UserMark(type, id, kind, true, null, Instant.now().toString()))
        } else {
            dao.delete(type, id, kind)
        }
        if (type == UserMark.SONG && kind == UserMark.FAVORITE) onSongFavoriteChanged(id, now)
        return now
    }

    /**
     * 参加形態を返す (未参加は null)。種別が入っていない旧データは現地扱い。
     * 参加は公演 (show) 単位で持つのが正で、イベント単位のマークは旧データの互換のみ。
     */
    suspend fun attendance(type: String, id: String): AttendanceType? {
        if (!dao.isOn(type, id, UserMark.ATTENDED)) return null
        return AttendanceType.from(dao.textValue(type, id, UserMark.ATTENDED)) ?: AttendanceType.LIVE
    }

    /** 参加形態を設定する。null で不参加に戻す。 */
    suspend fun setAttendance(type: String, id: String, value: AttendanceType?) {
        if (value == null) {
            dao.delete(type, id, UserMark.ATTENDED)
        } else {
            dao.upsert(UserMark(type, id, UserMark.ATTENDED, true, value.raw, Instant.now().toString()))
            // 公演単位で付いたときだけ流す。取り消しは対象外 (チケット代の確認は
            // 「付けた直後」の一度きりでよい) — イベント単位の互換マークも対象外
            // (どの公演のチケットか特定できない)。
            if (type == UserMark.SHOW) {
                _attendanceMarked.tryEmit(AttendanceMarkedEvent(id, value))
            }
        }
    }

    /**
     * メモ本文 (未入力は null)。空白だけの保存は「無い」と同じ扱いにする
     * (空文字が残ると UI の「メモあり」判定が立ちっぱなしになるため)。
     */
    suspend fun note(type: String, id: String): String? =
        dao.memo(type, id)?.takeIf { it.isNotBlank() }

    /** メモを保存する。null / 空白のみ なら行ごと削除して「メモなし」に戻す。 */
    suspend fun setNote(type: String, id: String, text: String?) =
        setText(type, id, UserMark.MEMO, text)

    /** 座席メモ (未入力は null)。 */
    suspend fun seat(type: String, id: String): String? =
        meaningful(listOfNotNull(dao.mark(type, id, SEAT))).firstOrNull()?.textValue?.takeIf { it.isNotBlank() }

    /** 座席メモを保存する。null / 空白のみ なら行ごと削除。 */
    suspend fun setSeat(type: String, id: String, text: String?) =
        setText(type, id, SEAT, text)

    // ---- 習熟度 (段階) ----
    //
    // 保存するのは**序数だけ** (text_value に "1".."8")。ラベルはユーザーが設定で決めるので
    // 保存値に入れない (入れると「ラベルを直したら記録が迷子になる」が必ず起きる)。
    // 段数から導ける規則 (次の段 / 重み / 段数を変えたときの寄せ先) と群化・集計は
    // 共有コア (imas-core `domain/mastery.rs`) にある。ここは読み書きだけ。

    /** 全曲の習熟度。一覧の全行が読むので、行ごとに引かずまとめて 1 回。 */
    suspend fun masteryLevels(): Map<String, UByte> =
        meaningful(dao.marksOf(UserMark.SONG, UserMark.MASTERY))
            .mapNotNull { row ->
                val level = row.textValue?.toUByteOrNull() ?: return@mapNotNull null
                if (level > 0u) row.entityId to level else null
            }
            .toMap()

    /** 1 曲の段階を決める。0 で未設定に戻す (行ごと消す)。 */
    suspend fun setMastery(songId: String, level: UByte) {
        setText(UserMark.SONG, songId, UserMark.MASTERY,
                if (level.toInt() == 0) null else level.toString())
    }

    /** まとめて決める。1 曲ずつ書くのと同じ結果だが、呼び出し側の再読込を 1 回で済ませる。 */
    suspend fun setMastery(songIds: List<String>, level: UByte) {
        val text = if (level.toInt() == 0) null else level.toString()
        songIds.forEach { setText(UserMark.SONG, it, UserMark.MASTERY, text) }
    }

    /**
     * 読む価値のあるマークだけに絞る (bool が true か、文字に空白以外がある)。
     *
     * iOS は習熟度・座席・メモを `bool_value = false` のまま文字に値を入れて保存し、
     * その行はバックアップでそのまま Android に入る。`bool_value = 1` で絞ると iOS から
     * 持ってきた値が読めない。規則はコア (`backup_meaningful_mark_indices`) が持つ。
     */
    private fun meaningful(marks: List<UserMark>): List<UserMark> {
        if (marks.isEmpty()) return marks
        val records = marks.map {
            BackupUserMarkRecord(it.entityType, it.entityId, it.kind, it.boolValue, it.textValue, it.updatedAt)
        }
        return backupMeaningfulMarkIndices(records).map { marks[it.toInt()] }
    }

    /**
     * text_value を持つマークの共通の書き込み口。
     *
     * `bool_value` は true で入れる (iOS は false で入れるが、読む側はどちらも読める)。
     */
    private suspend fun setText(type: String, id: String, kind: String, text: String?) {
        val trimmed = text?.trim()
        if (trimmed.isNullOrEmpty()) {
            dao.delete(type, id, kind)
        } else {
            dao.upsert(UserMark(type, id, kind, true, trimmed, Instant.now().toString()))
        }
    }

    /** 与えた公演のうち参加マークが付いているものの id。 */
    suspend fun attendedShowIds(showIds: List<String>): Set<String> =
        if (showIds.isEmpty()) emptySet()
        else dao.onIdsIn(UserMark.SHOW, UserMark.ATTENDED, showIds).toSet()

    /** 担当アイドル一覧。 */
    suspend fun pickedIdols(): List<Idol> =
        db.songDao().let { _ -> fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.PICK)) }

    /** 担当アイドルの ID セット (回収ダッシュボードの担当スコープ絞り込み用)。 */
    suspend fun pickedIdolIds(): Set<String> = dao.idsFor(UserMark.IDOL, UserMark.PICK).toSet()

    /** お気に入りアイドルの ID セット。 */
    suspend fun favoriteIdolIds(): Set<String> = dao.idsFor(UserMark.IDOL, UserMark.FAVORITE).toSet()

    /** メモがあるアイドルの ID セット。 */
    suspend fun notedIdolIds(): Set<String> = notedIds(UserMark.IDOL)

    /** メモがあるエンティティの ID セット (「メモあり」の印と絞り込み)。 */
    suspend fun notedIds(type: String): Set<String> =
        meaningful(dao.marksOf(type, UserMark.MEMO)).mapTo(mutableSetOf()) { it.entityId }

    /**
     * 回収に配信参加も含めるか (既定 = 現地参加のみ)。地方勢など配信中心の人向けの設定。
     *
     * 設定の保存先 ([com.fugaif.imaslivedb.ui.theme.AppPreferences]) は Context を要るので、
     * リポジトリから読みに行かず**押し込んでもらう**。逆向き (data → ui) の依存を作らずに
     * 済ませるための向きで、押し込みは設定の読み込み時と変更時の 2 箇所。
     *
     * 実体は [CollectionPreferences] (回収の判定に絡む [SongRepository] / [EventRepository]
     * とも共有するため、このリポジトリのインスタンスには閉じ込めていない)。
     */
    var includeStreamInCollection: Boolean
        get() = CollectionPreferences.includeStream
        set(value) { CollectionPreferences.includeStream = value }

    /** お気に入りアイドル一覧。 */
    suspend fun favoriteIdols(): List<Idol> =
        fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.FAVORITE))

    /** お気に入り曲一覧。 */
    suspend fun favoriteSongs(): List<Song> =
        db.songDao().let { sdao ->
            val ids = dao.idsFor(UserMark.SONG, UserMark.FAVORITE)
            ids.mapNotNull { sdao.fetchSong(it) }
        }

    /** お気に入り曲 ID セット (曲一覧行アイコン/絞り込み用の軽量版)。 */
    suspend fun favoriteSongIds(): Set<String> = dao.idsFor(UserMark.SONG, UserMark.FAVORITE).toSet()

    /** カード所持 (KAMISABI 等) をマークした曲 ID セット。曲詳細のコンプ率計算用。 */
    suspend fun ownedSongIds(): Set<String> = dao.idsFor(UserMark.SONG, UserMark.OWNED).toSet()

    private suspend fun fetchIdols(ids: List<String>): List<Idol> {
        val idao = db.idolDao()
        return ids.mapNotNull { idao.fetchIdol(it) }
    }

    /** バックアップエクスポート用の全件取得。 */
    suspend fun getAll(): List<UserMark> = dao.getAll()

    /**
     * バックアップからの復元 (非破壊): ローカルに無い (entityType, entityId, kind) の組だけ追加する。
     * 既存のマークは一切上書きしない。
     */
    suspend fun restoreIfAbsent(marks: List<UserMark>): Int {
        val existingKeys = dao.getAll().map { Triple(it.entityType, it.entityId, it.kind) }.toSet()
        val toInsert = marks.filter { Triple(it.entityType, it.entityId, it.kind) !in existingKeys }
        if (toInsert.isNotEmpty()) dao.insertAll(toInsert)
        return toInsert.size
    }

    companion object {
        /**
         * 座席メモの kind (iOS `UserMarkKind.seat` と同じ生値)。
         *
         * `UserMark` の定数群には無いので、ここをマークの意味の持ち主として正本にする。
         * 画面側で "seat" を直接書かないこと (綴りがズレると別のマークになる)。
         */
        const val SEAT = "seat"
    }
}

data class AttendedEventTypeSets(
    val live: Set<String>,
    val stream: Set<String>,
    val liveViewing: Set<String>
)
