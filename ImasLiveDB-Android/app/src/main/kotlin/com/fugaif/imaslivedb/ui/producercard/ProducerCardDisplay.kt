package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.runtime.Composable
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardBack
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardContent
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardFaceGroup
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardLink
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardOshi
import java.text.NumberFormat
import java.util.Locale
import android.content.Context
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardDesign
import uniffi.imas_core.CardDesign
import uniffi.imas_core.CardDesignInfo
import uniffi.imas_core.ProducerCard
import com.fugaif.imaslivedb.ui.theme.rememberCardNameFamily
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.cardQrLinkView
import uniffi.imas_core.producerCardDisplayDesign
import uniffi.imas_core.CardOshiEntry
import uniffi.imas_core.CardPhotoShape
import uniffi.imas_core.CardPhotoSource
import uniffi.imas_core.cardPhotoShape
import uniffi.imas_core.cardIssuedLabel
import uniffi.imas_core.producerCardFace
import uniffi.imas_core.producerCardPayload
import uniffi.imas_core.producerCardUrlFromPayload

/**
 * 名刺を描くのに要る、端末のマスタの引き当て (担当のアイドル・ブランド・公演)。iOS `ProducerCardDirectory` と対。
 * 名刺は id しか持たないので、表示のたびにまとめて引く。端末に無い id は出さない
 * (相手の方が新しいデータを持っていた等。名刺そのものは壊さずに残す)。
 */
data class ProducerCardDirectory(
    val idols: Map<String, Idol> = emptyMap(),
    val brands: Map<String, Brand> = emptyMap(),
    val shows: Map<String, ProducerCardShowInfo> = emptyMap()
) {
    companion object {
        suspend fun load(module: AppModule, idolIds: List<String>, showIds: List<String>): ProducerCardDirectory {
            val ids = idolIds.distinct()
            val idols = if (ids.isEmpty()) emptyMap() else {
                runCatching { module.idolRepository.fetchIdolsByIds(ids) }.getOrDefault(emptyList()).associateBy { it.id }
            }
            val brands = runCatching { module.database.brandDao().fetchBrands() }.getOrDefault(emptyList()).associateBy { it.id }
            val shows = showIds.filter { it.isNotEmpty() }.let {
                if (it.isEmpty()) emptyMap() else runCatching { module.producerCardRepository.showInfos(it) }.getOrDefault(emptyMap())
            }
            return ProducerCardDirectory(idols, brands, shows)
        }
    }

    /**
     * 担当の名前とブランド (端末に無い担当は入れない)。名刺の表の組み・名刺に載せる担当の選び方はコア
     * (`producerCardFace` / `producerCardPickOshi`)。
     */
    fun oshiEntries(ids: List<String>): List<CardOshiEntry> = ids.mapNotNull { id ->
        val idol = idols[id] ?: return@mapNotNull null
        CardOshiEntry(idolId = id, name = idol.name, brandId = idol.brandId, brandLabel = brands[idol.brandId]?.shortName.orEmpty())
    }
}

/**
 * 受け取った名刺 1 枚の端末の画像 (担当の画像・名刺の写真とその出どころ・自作の名刺の画像・紙の名刺の写真)。
 * ファイルを見るので一覧・詳細を読むときに IO で引き、画面はこれを描くだけにする。
 */
data class ReceivedCardImages(
    /** 担当の画像 (アイドルの id → 画像)。 */
    val oshi: Map<String, String> = emptyMap(),
    val portraitUrl: String? = null,
    val portraitSource: CardPhotoSource = CardPhotoSource.PICKED,
    val face: ProducerCardFace? = null,
    /** 紙の名刺の写真 (表・裏)。 */
    val paperPhotos: List<String> = emptyList()
) {
    /** 名刺の写真を丸く出すか (切り方はコアの `cardPhotoShape`)。 */
    val portraitRound: Boolean get() = cardPhotoShape(portraitSource) == CardPhotoShape.ROUND

    companion object {
        /** ファイルを見るのでメインの外で呼ぶ。 */
        fun load(context: Context, cardId: String, oshiIds: List<String>): ReceivedCardImages = ReceivedCardImages(
            oshi = oshiIds.mapNotNull { id -> ProducerCardFiles.oshiImageUrl(context, cardId, id)?.let { id to it } }.toMap(),
            portraitUrl = ProducerCardFiles.cardPhotoUrl(context, cardId),
            portraitSource = ProducerCardFiles.cardPhotoSource(context, cardId),
            face = ProducerCardDisplay.receivedFace(context, cardId),
            paperPhotos = ProducerCardFiles.Side.entries.mapNotNull { ProducerCardFiles.photoUrl(context, cardId, it) }
        )
    }
}

/** 名刺の顔 (自作の名刺の画像の表・裏)。自分の名刺は端末の画像、受け取った名刺は届いた画像。iOS `ProducerCardDisplay.Face` と対。 */
data class ProducerCardFace(val front: String, val back: String? = null)

/** 名刺 (コアの `ProducerCard`) を DS の `ImasProducerCard` に載せる形にする。iOS `ProducerCardDisplay` と対。 */
object ProducerCardDisplay {
    private val numbers: NumberFormat = NumberFormat.getIntegerInstance(Locale.JAPAN)

    fun number(value: Long): String = numbers.format(value)

    /**
     * 担当の行。[imageUrls] は担当の画像の在り処 (アイドルの id → 画像。受け取った名刺は受け取った画像)。
     * [ownImages] = true は自分の名刺 (端末に取り込んだアイドルの写真を引く)。
     */
    fun oshi(
        card: ProducerCard,
        directory: ProducerCardDirectory,
        sharedWith: Set<String> = emptySet(),
        ownImages: Boolean = false,
        imageUrls: Map<String, String> = emptyMap()
    ): List<ImasProducerCardOshi> = card.oshiIdolIds.mapNotNull { id ->
        val idol = directory.idols[id] ?: return@mapNotNull null
        val brand = directory.brands[idol.brandId]
        ImasProducerCardOshi(
            id = idol.id, name = idol.name, shortName = idol.shortName,
            seed = idol.color, brand = idol.brandId,
            imageUrl = if (ownImages) null else imageUrls[idol.id],
            entityId = if (ownImages) idol.id else null,
            subtitle = brand?.shortName, isShared = idol.id in sharedWith
        )
    }

    /** リンクの行。自分の QR があれば先頭に「QR」として出す (押せば開く)。 */
    fun links(card: ProducerCard): List<ImasProducerCardLink> =
        (listOfNotNull(card.qrUrl?.let { cardQrLinkView(it) }) + card.links.map { cardLinkView(it) }).map { view ->
            ImasProducerCardLink(label = view.label, display = view.display, url = view.url)
        }

    /** 描くデザイン (自作の画像の名刺でも画像が無ければ入場証。決めるのはコア)。 */
    fun design(card: ProducerCard, face: ProducerCardFace?): CardDesignInfo = producerCardDisplayDesign(card, face != null)

    /** 名前の書体のファイルの名前 (デザインの書体。一覧と既定はコア)。 */
    fun nameFont(card: ProducerCard, face: ProducerCardFace? = null): String = design(card, face).font.fileStem

    /** DS の名刺のデザイン。 */
    fun cardDesign(card: ProducerCard, face: ProducerCardFace?): ImasProducerCardDesign = when (design(card, face).design) {
        CardDesign.PASS -> ImasProducerCardDesign.Pass
        CardDesign.FORMAL -> ImasProducerCardDesign.Formal
        CardDesign.POP -> ImasProducerCardDesign.Pop
        CardDesign.OSHI -> ImasProducerCardDesign.Oshi
        CardDesign.CUSTOM -> face?.let { ImasProducerCardDesign.Face(it.front, it.back) } ?: ImasProducerCardDesign.Pass
    }

    /** 自分の名刺の顔 (自作の画像の表があれば)。ファイルを見るのでメインの外で呼ぶ。 */
    fun myFace(context: Context): ProducerCardFace? =
        ProducerCardFiles.myFaceUrl(context, ProducerCardFiles.Side.FRONT)?.let {
            ProducerCardFace(front = it, back = ProducerCardFiles.myFaceUrl(context, ProducerCardFiles.Side.BACK))
        }

    /** 受け取った名刺の顔 (届いた自作の画像の表があれば)。 */
    fun receivedFace(context: Context, cardId: String): ProducerCardFace? =
        ProducerCardFiles.faceUrl(context, cardId, ProducerCardFiles.Side.FRONT)?.let {
            ProducerCardFace(front = it, back = ProducerCardFiles.faceUrl(context, cardId, ProducerCardFiles.Side.BACK))
        }

    /** 記録の数 (参加公演・回収曲・次の現場)。載っていない数は出さない。 */
    fun cells(card: ProducerCard, directory: ProducerCardDirectory): List<ImasBoardCell> = buildList {
        card.showCount?.let { add(ImasBoardCell(value = number(it.toLong()), label = "参加公演", unit = "公演")) }
        card.songCount?.let { add(ImasBoardCell(value = number(it.toLong()), label = "回収曲", unit = "曲")) }
        card.nextShowId?.let { directory.shows[it] }?.let { add(ImasBoardCell(value = monthDay(it.date), label = "次の現場")) }
    }

    /** 掲示板の右上 (「2014 — 2026」)。P 歴が無ければ名刺を作った年だけ。 */
    fun boardTrailing(card: ProducerCard): String? {
        val issued = card.issuedOn.take(4)
        if (issued.length != 4) return null
        return card.sinceYear?.let { "$it — $issued" } ?: issued
    }

    /** 次の現場の掲示板の値 (`10/18`)。 */
    fun monthDay(date: String): String {
        val parts = date.split("-")
        val m = parts.getOrNull(1)?.toIntOrNull()
        val d = parts.getOrNull(2)?.take(2)?.toIntOrNull()
        return if (m != null && d != null) "$m/$d" else "—"
    }

    /** 1 行の要約 (「如月千早 · 63 公演」)。名刺入れの行の副題。 */
    fun summaryLine(card: ProducerCard, directory: ProducerCardDirectory): String {
        val parts = mutableListOf<String>()
        val names = card.oshiIdolIds.mapNotNull { directory.idols[it]?.name }
        names.firstOrNull()?.let { first ->
            parts += if (names.size > 1) "$first ほか${names.size - 1}人" else first
        }
        card.showCount?.let { parts += "${number(it.toLong())} 公演" }
        if (parts.isEmpty()) card.links.firstOrNull()?.let { parts += cardLinkView(it).display }
        return parts.joinToString(" · ")
    }
}

/**
 * 名刺 1 枚に載せるもの (自分の名刺・受け取った名刺で同じ部品)。名刺は [ImasProducerCard]、名刺の下の詳細は
 * [ImasProducerCardDetails] に同じものを渡す。iOS `ProducerCardDisplay.view`。
 * [portraitUrl] は名刺の写真 ([portraitSource] はその出どころ。X のアイコンは丸く出す)、[face] は自作の名刺の画像 (自分の名刺は端末の画像、受け取った名刺は届いた画像。
 * QR だけで受け取った名刺には無いので、自作の画像の名刺も入場証で描く)。
 * [back] は裏の QR (渡さなければ交換用)。[payload] は受け取ったままの名刺の中身 (交換用の QR に使う。組み直すと、
 * 新しい版のアプリが足した項目を落とした QR になる)。
 * [imageUrls] は担当の画像 (アイドルの id → 画像。受け取った名刺は受け取った画像。近くの端末から後で届いても組み直す)。
 * [showsRecord] は名刺の下の記録の掲示板 (自分の名刺は出さない。自分の記録は P名刺の画像で見せる)。
 */
@Composable
fun rememberProducerCardContent(
    card: ProducerCard,
    directory: ProducerCardDirectory,
    sharedWith: Set<String> = emptySet(),
    ownImages: Boolean = false,
    imageUrls: Map<String, String> = emptyMap(),
    portraitUrl: String? = null,
    portraitSource: CardPhotoSource = CardPhotoSource.PICKED,
    face: ProducerCardFace? = null,
    back: ImasProducerCardBack? = null,
    payload: String? = null,
    showsRecord: Boolean = true
): ImasProducerCardContent {
    val nameFamily = rememberCardNameFamily(ProducerCardDisplay.nameFont(card, face))
    val photoEntityId = if (ownImages) firstWithImage(card, directory) else null
    return remember(
        card, directory, sharedWith, ownImages, imageUrls, portraitUrl, portraitSource, face, back, payload, showsRecord,
        nameFamily, photoEntityId
    ) {
        val oshi = ProducerCardDisplay.oshi(card, directory, sharedWith, ownImages, imageUrls)
        val cardFace = producerCardFace(card, directory.oshiEntries(oshi.map { it.id }))
        val byId = oshi.associateBy { it.id }
        ImasProducerCardContent(
            name = card.name,
            design = ProducerCardDisplay.cardDesign(card, face),
            sinceImprint = cardFace.sinceImprint,
            message = card.message,
            oshi = oshi,
            faceGroups = cardFace.oshiGroups.map { group ->
                ImasProducerCardFaceGroup(group.brandLabel, group.idolIds.mapNotNull { byId[it] })
            },
            oshiCaption = cardFace.oshiCaption,
            heroOshi = cardFace.heroIdolIds.mapNotNull { byId[it] },
            moreOshi = cardFace.moreOshi.toInt(),
            handle = cardFace.handle?.display,
            links = ProducerCardDisplay.links(card),
            cells = if (showsRecord) ProducerCardDisplay.cells(card, directory) else emptyList(),
            boardTrailing = ProducerCardDisplay.boardTrailing(card),
            photoUrl = if (ownImages) null else oshi.firstNotNullOfOrNull { it.imageUrl },
            photoEntityId = photoEntityId,
            portraitUrl = portraitUrl,
            portraitRound = cardPhotoShape(portraitSource) == CardPhotoShape.ROUND,
            nameFamily = nameFamily,
            back = back ?: ImasProducerCardBack(
                qr = producerCardUrlFromPayload(payload ?: producerCardPayload(card)),
                issuedLabel = cardFace.issuedLabel,
                showCount = card.showCount?.toLong(),
                songCount = card.songCount?.toLong()
            )
        )
    }
}

/** 自分の QR の裏 (「自分の QR」を選んだとき)。iOS `ProducerCardDisplay.ownQRBack`。 */
fun ownQrBack(card: ProducerCard, url: String): ImasProducerCardBack = ImasProducerCardBack(
    qr = url, issuedLabel = cardIssuedLabel(card.issuedOn), qrLabel = "自分の QR コード",
    note = "読み取ると ${cardQrLinkView(url).display} が開きます。",
    showCount = card.showCount?.toLong(), songCount = card.songCount?.toLong()
)

/** 自分の名刺の写真: 端末に写真を取り込んだ先頭の担当。 */
@Composable
private fun firstWithImage(card: ProducerCard, directory: ProducerCardDirectory): String? {
    val store = AppModule.from(androidx.compose.ui.platform.LocalContext.current).customImageStore
    val version by store.galleryVersion.collectAsState()
    return remember(card.oshiIdolIds, directory, version) {
        card.oshiIdolIds.firstOrNull { it in directory.idols && store.primaryImageFile(it) != null }
    }
}
