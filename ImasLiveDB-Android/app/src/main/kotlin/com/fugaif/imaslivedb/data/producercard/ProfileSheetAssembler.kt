package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.ProfileBrandInput
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.ProfileSheetRecord
import uniffi.imas_core.ProfileShowInput
import uniffi.imas_core.ProfileSongInput
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.cardNameFontInfo
import uniffi.imas_core.cardNameFonts
import uniffi.imas_core.producerCardLimits

/**
 * プロフィール帳に載る担当 1 人 (押印欄の判子と担当の行)。iOS `ProfileSheetOshi` と対。
 * 画像は焼く前に読んでおく (焼くのは今描かれているものだけで、読み込みを待たない)。
 */
data class ProfileSheetOshi(
    val id: String,
    val name: String,
    val shortName: String,
    val color: String?,
    val brandColor: String?,
    val image: Bitmap?
)

/**
 * プロフィール帳の材料。iOS `ProfileSheetMaterials` と対。中身の組み立て (欄・行・丸・詰め方) は
 * コアの `profileSheetLayout`、ここはアプリの記録とマスタを引いて渡す形にするだけ。
 */
data class ProfileSheetMaterials(
    /** 名前・P歴・リンク・記録・ブランド・好きな曲 (好きな曲は `favoriteSongIds` を引いたもの)。 */
    val record: ProfileSheetRecord,
    val oshi: List<ProfileSheetOshi> = emptyList(),
    /** P名刺の写真。 */
    val portrait: Bitmap? = null,
    /** 自分の QR の URL (P名刺に載せていれば)。 */
    val qrUrl: String? = null,
    /** 答え・名前の書体 (P名刺の書体のファイルの名前)。 */
    val nameFont: String = cardNameFonts().first().fileStem,
    /** 好きな曲を選ぶ候補 (お気に入りの曲)。 */
    val favoriteCandidates: List<Song> = emptyList(),
    /** 好きな曲の題 (id → 題)。 */
    val songTitles: Map<String, String> = emptyMap()
) {
    /** 好きな曲を選び直したら、題を引き直さずに材料へ反映する。 */
    fun withFavoriteSongIds(ids: List<String>): ProfileSheetMaterials = copy(
        record = record.copy(favoriteSongs = ids.mapNotNull { id -> songTitles[id]?.let { ProfileSongInput(id, it) } })
    )

    /** 担当の色 (帯・罫・押印の判子)。担当がいなければ null (墨)。 */
    val seed: String? get() = oshi.firstOrNull()?.color

    companion object {
        val EMPTY = ProfileSheetMaterials(
            record = ProfileSheetRecord(
                today = "", name = "", sinceYear = null, oshiBrandIds = emptyList(), attended = emptyList(),
                songCount = 0u, brands = emptyList(), favoriteSongs = emptyList(), links = emptyList()
            )
        )
    }
}

/** プロフィール帳の材料を集める。iOS `ProfileSheetAssembler` と対 (並びと除外はコア)。 */
object ProfileSheetAssembler {
    suspend fun load(context: Context, module: AppModule, card: MyProducerCard, sheet: ProfileSheet): ProfileSheetMaterials {
        val limits = producerCardLimits()
        val marks = module.userMarkRepository
        val oshiIds = runCatching { marks.pickedIdolIdList() }.getOrDefault(emptyList()).take(limits.maxOshi.toInt())
        val repo = module.producerCardRepository
        val attendedRefs = runCatching { repo.attendedShowRefs() }.getOrDefault(emptyList())
        val shows = runCatching { repo.showInfos(attendedRefs.map { it.showId }) }.getOrDefault(emptyMap())
        val songCount = runCatching { module.songRepository.fetchCollectedSongIds().size }.getOrDefault(0)
        val brands = runCatching { module.statsRepository.fetchBrands() }.getOrDefault(emptyList())
        val brandById = brands.associateBy { it.id }
        val idols = if (oshiIds.isEmpty()) emptyList()
        else runCatching { module.idolRepository.fetchIdolsByIds(oshiIds) }.getOrDefault(emptyList())
        val idolById = idols.associateBy { it.id }
        val oshiIdols = oshiIds.mapNotNull { idolById[it] }

        // 好きな曲の候補はお気に入りの曲 (選んだ曲がお気に入りから外れていても題は引く)。
        val favoriteIds = runCatching { marks.favoriteSongIdList() }.getOrDefault(emptyList())
        val songIds = (favoriteIds + sheet.favoriteSongIds).distinct()
        val songs = if (songIds.isEmpty()) emptyList()
        else runCatching { module.songRepository.fetchSongsByIds(songIds) }.getOrDefault(emptyList())
        val songById = songs.associateBy { it.id }

        val (oshi, portrait) = withContext(Dispatchers.IO) {
            oshiIdols.map { idol ->
                ProfileSheetOshi(
                    id = idol.id, name = idol.name, shortName = idol.shortName, color = idol.color,
                    brandColor = brandById[idol.brandId]?.color,
                    image = module.customImageStore.primaryImageFile(idol.id)?.let(::decode)
                )
            } to ProducerCardFiles.myPhotoFile(context)?.let(::decode)
        }

        val record = ProfileSheetRecord(
            today = JstDay.today(),
            name = card.name,
            sinceYear = card.sinceYear?.takeIf { it in 0..65535 }?.toUShort(),
            oshiBrandIds = oshiIdols.map { it.brandId },
            attended = attendedRefs.mapNotNull { ref ->
                val info = shows[ref.showId] ?: return@mapNotNull null
                ProfileShowInput(ref.showId, ref.date, info.label, info.venue, info.brandId)
            },
            songCount = songCount.toUInt(),
            brands = brands.map { ProfileBrandInput(it.id, it.shortName, it.color, it.sortOrder.toLong()) },
            favoriteSongs = emptyList(),
            links = card.links.map { cardLinkView(it).display }
        )
        return ProfileSheetMaterials(
            record = record,
            oshi = oshi,
            portrait = portrait,
            qrUrl = card.qrUrl,
            nameFont = cardNameFontInfo(card.font).fileStem,
            favoriteCandidates = favoriteIds.mapNotNull { songById[it] },
            songTitles = songById.mapValues { it.value.title }
        ).withFavoriteSongIds(sheet.favoriteSongIds)
    }

    private fun decode(file: File): Bitmap? = runCatching { BitmapFactory.decodeFile(file.path) }.getOrNull()
}
