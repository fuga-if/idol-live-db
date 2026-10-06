package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import com.fugaif.imaslivedb.data.local.BrandRoleStore
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.CollectionAttendance
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.ProfileBrandInput
import uniffi.imas_core.ProfileLiveRecord
import uniffi.imas_core.ProfileSheetRecord
import uniffi.imas_core.ProfileShowInput
import uniffi.imas_core.ProfileSongInput
import uniffi.imas_core.cardLinkView
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
    /** 名前・P歴・リンク・記録・ブランド・担当ブランドの設定・お気に入りの曲・都道府県の数。 */
    val record: ProfileSheetRecord,
    val oshi: List<ProfileSheetOshi> = emptyList(),
    /** 証明写真の欄の画像 (プロフィール帳の画像、無ければ P名刺の写真)。 */
    val portrait: Bitmap? = null,
    /** 自分の QR の URL (P名刺に載せていれば)。 */
    val qrUrl: String? = null
) {
    companion object {
        val EMPTY = ProfileSheetMaterials(
            record = ProfileSheetRecord(
                today = "", name = "", sinceYear = null, oshiNames = emptyList(), oshiBrandIds = emptyList(),
                attended = emptyList(), songCount = 0u, brands = emptyList(), brandRolesJson = "",
                favoriteSongs = emptyList(), links = emptyList(), hasPhoto = false, hasQr = false,
                live = ProfileLiveRecord(0u)
            )
        )
    }
}

/** プロフィール帳の材料を集める。iOS `ProfileSheetAssembler` と対 (並びと除外はコア)。 */
object ProfileSheetAssembler {
    suspend fun load(context: Context, module: AppModule, card: MyProducerCard): ProfileSheetMaterials {
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
        // 担当ブランドの既定は設定の画面と同じ材料で組む (担当の上限で切らない)。
        val brandRoleRecord = BrandRoleStore.loadRecord(module)

        // お気に入りの曲は付けた新しい順に全部 (載せる曲数はコア)。
        val favoriteIds = runCatching { marks.favoriteSongIdList() }.getOrDefault(emptyList())
        val songById = if (favoriteIds.isEmpty()) emptyMap()
        else runCatching { module.songRepository.fetchSongsByIds(favoriteIds) }.getOrDefault(emptyList()).associateBy { it.id }
        val today = JstDay.today()
        // 都道府県を数えるのは現地参加だけ。参加マークは形態つきのまま渡し、
        // 現地だけに絞るのとイベント単位の展開はコア (回収と同じ取り出し方)。
        val live = runCatching {
            val showMarks = CollectionAttendance.marks(module.database, UserMark.SHOW)
            val eventMarks = CollectionAttendance.marks(module.database, UserMark.EVENT)
            module.snapshotStoreProvider.loadedStore()
                .profileLiveRecord(showMarks, eventMarks, today)
        }.getOrDefault(ProfileSheetMaterials.EMPTY.record.live)

        val (oshi, portrait) = withContext(Dispatchers.IO) {
            oshiIdols.map { idol ->
                ProfileSheetOshi(
                    id = idol.id, name = idol.name, shortName = idol.shortName, color = idol.color,
                    brandColor = brandById[idol.brandId]?.color,
                    // 書き出しは画像の読み込みを待たないので、ここで小さく読んでおく。
                    image = module.customImageStore.primaryImageFile(idol.id)?.let { ProfileSheetFiles.decodeBounded(it, 240) }
                )
            } to ProfileSheetFiles.effectiveFile(context)?.let { ProfileSheetFiles.decodeBounded(it, 600) }
        }

        val record = ProfileSheetRecord(
            today = today,
            name = card.name,
            sinceYear = card.sinceYear?.takeIf { it in 0..65535 }?.toUShort(),
            oshiNames = oshiIdols.map { it.name },
            oshiBrandIds = brandRoleRecord.oshiBrandIds,
            attended = attendedRefs.mapNotNull { ref ->
                val info = shows[ref.showId] ?: return@mapNotNull null
                ProfileShowInput(ref.showId, ref.date, info.label, info.venue, info.brandId)
            },
            songCount = songCount.toUInt(),
            brands = brands.map { ProfileBrandInput(it.id, it.shortName, it.color, it.sortOrder.toLong()) },
            brandRolesJson = BrandRoleStore.json(context),
            favoriteSongs = favoriteIds.mapNotNull { id -> songById[id]?.let { ProfileSongInput(id, it.title) } },
            links = card.links.map { cardLinkView(it).display },
            hasPhoto = portrait != null,
            hasQr = card.qrUrl != null,
            live = live
        )
        return ProfileSheetMaterials(
            record = record,
            oshi = oshi,
            portrait = portrait,
            qrUrl = card.qrUrl
        )
    }
}
