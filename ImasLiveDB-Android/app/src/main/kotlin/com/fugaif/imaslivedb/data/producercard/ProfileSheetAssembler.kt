package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.graphics.Bitmap
import com.fugaif.imaslivedb.data.local.BrandRoleStore
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.imasQrMatrix
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.ProfileBrandInput
import uniffi.imas_core.ProfileSheetRecord
import uniffi.imas_core.ProfileShowInput
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.producerCardLimits
import uniffi.imas_core.producerCardOshiPickedIds

/**
 * P名刺の画像 (SNS に貼る履歴書の様式) に載る担当 1 人 (押印欄の判子と担当の行)。iOS `ProfileSheetOshi` と対。
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
 * P名刺の画像の材料。iOS `ProfileSheetMaterials` と対。中身の組み立て (欄・行・丸・詰め方) は
 * コアの `profileSheetLayout`、ここは P名刺・アプリの記録とマスタを引いて渡す形にするだけ。
 */
data class ProfileSheetMaterials(
    /** 名前・P歴・リンク・記録・ブランド・担当ブランドの設定・お気に入りの曲。 */
    val record: ProfileSheetRecord,
    val oshi: List<ProfileSheetOshi> = emptyList(),
    /** 証明写真の欄の画像 (P名刺の写真)。 */
    val portrait: Bitmap? = null,
    /** 証明写真の欄の中に丸く置く (X のアイコン。切り方はコアの `cardPhotoShape`)。 */
    val portraitRound: Boolean = false,
    /** 自分の QR の URL (P名刺に載せていれば)。 */
    val qrUrl: String? = null
) {
    companion object {
        val EMPTY = ProfileSheetMaterials(
            record = ProfileSheetRecord(
                today = "", name = "", sinceYear = null, oshiNames = emptyList(), oshiBrandIds = emptyList(),
                attended = emptyList(), songCount = 0u, brands = emptyList(), brandRolesJson = "",
                favoriteSongs = emptyList(), links = emptyList(), hasPhoto = false, hasQr = false
            )
        )
    }
}

/** P名刺の画像の材料を集める。iOS `ProfileSheetAssembler` と対 (並びと除外はコア)。 */
object ProfileSheetAssembler {
    suspend fun load(context: Context, module: AppModule, card: MyProducerCard): ProfileSheetMaterials {
        val limits = producerCardLimits()
        val marks = module.userMarkRepository
        // 載せる担当は名刺に載せた担当 (本人の選択。まだ選んでいなければブランドごとに 1 人を先に確保して
        // 上限まで。規則はコア)。
        val entries = ProducerCardAssembler.oshiEntries(
            module, runCatching { marks.pickedIdolIdList() }.getOrDefault(emptyList())
        )
        val oshiIds = producerCardOshiPickedIds(card.cardOshiChoice, entries).take(limits.maxOshi.toInt())
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

        val today = JstDay.today()
        // お気に入りの曲すべて (載せる曲と並びは選択からコアが決める。引けない曲は入れない)。
        val favorites = FavoriteSongSource.load(module)

        val oshi = withContext(Dispatchers.IO) {
            oshiIdols.map { idol ->
                ProfileSheetOshi(
                    id = idol.id, name = idol.name, shortName = idol.shortName, color = idol.color,
                    brandColor = brandById[idol.brandId]?.color,
                    // 書き出しは画像の読み込みを待たないので、ここで小さく読んでおく。
                    image = module.customImageStore.primaryImageFile(idol.id)?.let { ProducerCardFiles.decodeBounded(it, 240) }
                )
            }
        }
        // 証明写真の欄は P名刺の写真 (X のアイコンは欄の中に丸く置く)。
        val (portrait, portraitRound) = withContext(Dispatchers.IO) {
            ProducerCardFiles.myPhotoFile(context)?.let { ProducerCardFiles.decodeBounded(it, 600) } to
                ProducerCardFiles.myPhotoRound(context)
        }
        // 自分の QR は組めるものだけ (組めない URL で欄を空けない)。
        val qrUrl = card.qrUrl?.takeIf { imasQrMatrix(it) != null }

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
            favoriteSongs = favorites.map { it.input },
            links = card.links.map { cardLinkView(it).display },
            hasPhoto = portrait != null,
            hasQr = qrUrl != null
        )
        return ProfileSheetMaterials(
            record = record,
            oshi = oshi,
            portrait = portrait,
            portraitRound = portraitRound,
            qrUrl = qrUrl
        )
    }
}
