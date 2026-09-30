package com.fugaif.imaslivedb.ui.sortmaker

import com.fugaif.imaslivedb.data.core.VoiceActorDirectory
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.repository.IdolRepository
import com.fugaif.imaslivedb.data.repository.SongRepository

// =============================================================================
// 対戦カード・順位表の 1 件 (曲かアイドルのどちらか) と、対象の絞り込み・読み込み。
// iOS SortMakerItem.swift の移植。
// =============================================================================

/** 対戦カード・順位表の 1 件。曲かアイドルのどちらか。 */
sealed class SortMakerItem {
    data class SongItem(val song: Song) : SortMakerItem()
    data class IdolItem(val idol: Idol) : SortMakerItem()

    val id: String
        get() = when (this) {
            is SongItem -> song.id
            is IdolItem -> idol.id
        }

    val title: String
        get() = when (this) {
            is SongItem -> song.title
            is IdolItem -> idol.name
        }

    /** 曲は歌唱名義、アイドルは CV。 */
    val subtitle: String?
        get() = when (this) {
            is SongItem -> song.singerLabel ?: song.unitName
            is IdolItem -> VoiceActorDirectory.current(idol.id)?.let { "CV. $it" }
        }

    /** テーマ色の種。曲はブランド色 (曲に固有の色は無い)、アイドルはイメージカラー。 */
    val seed: String?
        get() = when (this) {
            is SongItem -> com.fugaif.imaslivedb.ui.theme.BrandColors.hex(song.brandId)
            is IdolItem -> idol.color
        }

    val brandId: String?
        get() = when (this) {
            is SongItem -> song.brandId
            is IdolItem -> idol.brandId
        }
}

/** 設定画面で選ぶ曲の種類。値は songs.song_type ("" = すべて)。 */
enum class SortMakerSongType(val rawValue: String, val label: String) {
    ANY("", "すべて"),
    SOLO("solo", "ソロ曲"),
    UNIT("unit", "ユニット曲"),
    ALL("all", "全体曲");

    companion object {
        fun fromRawValue(v: String): SortMakerSongType = entries.firstOrNull { it.rawValue == v } ?: ANY
    }
}

/** 対象の絞り込み。 */
data class SortMakerScope(
    val brandIds: Set<String> = emptySet(),
    /** 曲だけ: 歌唱アイドル (原唱者) での絞り込み。 */
    val idolIds: Set<String> = emptySet(),
    val songType: SortMakerSongType = SortMakerSongType.ANY,
    val includeRemixes: Boolean = false
)

/** 対象の読み込み。絞り込みの判定はコア (曲一覧・アイドル一覧と同じ条件) に任せる。 */
object SortMakerCandidates {

    /** 設定画面の候補読み込み (絞り込み条件から母集団を引き直す)。 */
    suspend fun load(
        subject: SortMakerSubject,
        scope: SortMakerScope,
        songRepository: SongRepository,
        idolRepository: IdolRepository
    ): List<SortMakerItem> = when (subject) {
        SortMakerSubject.SONG -> {
            val filter = SongSearchFilter(
                brandIds = scope.brandIds,
                idolIds = scope.idolIds.takeIf { it.isNotEmpty() }?.toList(),
                songType = scope.songType.rawValue.takeIf { it.isNotEmpty() },
                includeRemixes = scope.includeRemixes,
                // 曲一覧のブラウズと同じ母集団 (歌枠カバー等と、セトリにしか居ない曲は出さない)。
                includeOtherBrand = false,
                excludeLiveOnly = true
            )
            songRepository.fetchSongs(filter = filter).map { SortMakerItem.SongItem(it.song) }
        }
        SortMakerSubject.IDOL -> {
            val idols = if (scope.brandIds.isEmpty()) {
                idolRepository.fetchIdolsForList(null)
            } else {
                val merged = mutableListOf<Idol>()
                for (brandId in scope.brandIds.sorted()) {
                    merged += idolRepository.fetchIdolsForList(brandId)
                }
                merged
            }
            // fetchIdolsForList は既に is_external を除外済み (iOS `idols(brandId:)` と同一条件)。
            idols.map { SortMakerItem.IdolItem(it) }
        }
    }

    /**
     * 保存した id 列の順に引き直す (消えた id は null のまま位置を保つ)。
     *
     * コアの `sortMakerReplay` は対戦のペアを id 列の**添字**で表すので、途中で 1 件
     * 消えたからといって詰めてはいけない — 添字がずれて、以後の答えが別の曲/アイドルを
     * 指してしまう。見つからなかった位置は null にして呼び出し側で「見つかりません」を出す。
     */
    suspend fun loadByIds(
        subject: SortMakerSubject,
        ids: List<String>,
        songRepository: SongRepository,
        idolRepository: IdolRepository
    ): List<SortMakerItem?> = when (subject) {
        SortMakerSubject.SONG -> {
            val byId = songRepository.fetchSongsByIds(ids).associateBy { it.id }
            ids.map { byId[it]?.let { song -> SortMakerItem.SongItem(song) } }
        }
        SortMakerSubject.IDOL -> {
            val byId = idolRepository.fetchIdolsByIds(ids).associateBy { it.id }
            ids.map { byId[it]?.let { idol -> SortMakerItem.IdolItem(idol) } }
        }
    }
}
