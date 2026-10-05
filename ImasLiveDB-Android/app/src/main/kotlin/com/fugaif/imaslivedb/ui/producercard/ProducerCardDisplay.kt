package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCard
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardLink
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardOshi
import java.text.NumberFormat
import java.util.Locale
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.cardLinkView

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
}

/** 名刺 (コアの `ProducerCard`) を DS の `ImasProducerCard` に載せる形にする。iOS `ProducerCardDisplay` と対。 */
object ProducerCardDisplay {
    private val numbers: NumberFormat = NumberFormat.getIntegerInstance(Locale.JAPAN)

    fun number(value: Long): String = numbers.format(value)

    /**
     * 担当の行。[imageUrl] は担当の画像の在り処 (受け取った名刺は受け取った画像)。
     * [ownImages] = true は自分の名刺 (端末に取り込んだアイドルの写真を引く)。
     */
    fun oshi(
        card: ProducerCard,
        directory: ProducerCardDirectory,
        sharedWith: Set<String> = emptySet(),
        ownImages: Boolean = false,
        imageUrl: (String) -> String? = { null }
    ): List<ImasProducerCardOshi> = card.oshiIdolIds.mapNotNull { id ->
        val idol = directory.idols[id] ?: return@mapNotNull null
        val brand = directory.brands[idol.brandId]
        ImasProducerCardOshi(
            id = idol.id, name = idol.name, shortName = idol.shortName,
            seed = idol.color, brand = idol.brandId,
            imageUrl = if (ownImages) null else imageUrl(idol.id),
            entityId = if (ownImages) idol.id else null,
            subtitle = brand?.shortName, isShared = idol.id in sharedWith
        )
    }

    fun links(card: ProducerCard): List<ImasProducerCardLink> = card.links.map { link ->
        val view = cardLinkView(link)
        ImasProducerCardLink(label = view.label, display = view.display, url = view.url)
    }

    /** 記録の数 (参加公演・回収曲・次の現場)。載っていない数は出さない。 */
    fun cells(card: ProducerCard, directory: ProducerCardDirectory): List<ImasBoardCell> = buildList {
        card.showCount?.let { add(ImasBoardCell(value = number(it.toLong()), label = "参加公演", unit = "公演")) }
        card.songCount?.let { add(ImasBoardCell(value = number(it.toLong()), label = "回収曲", unit = "曲")) }
        card.nextShowId?.let { directory.shows[it] }?.let { add(ImasBoardCell(value = monthDay(it.date), label = "次の現場")) }
    }

    fun sinceImprint(card: ProducerCard): String? = card.sinceYear?.let { "SINCE $it" }

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

/** 名刺 1 枚 (自分の名刺・受け取った名刺で同じ部品)。 */
@Composable
fun ProducerCardView(
    card: ProducerCard,
    directory: ProducerCardDirectory,
    modifier: Modifier = Modifier,
    sharedWith: Set<String> = emptySet(),
    ownImages: Boolean = false,
    imageUrl: (String) -> String? = { null },
    onOpenLink: ((ImasProducerCardLink) -> Unit)? = null,
    onOpenOshi: ((ImasProducerCardOshi) -> Unit)? = null
) {
    val oshi = ProducerCardDisplay.oshi(card, directory, sharedWith, ownImages, imageUrl)
    ImasProducerCard(
        name = card.name,
        modifier = modifier,
        sinceImprint = ProducerCardDisplay.sinceImprint(card),
        message = card.message,
        oshi = oshi,
        links = ProducerCardDisplay.links(card),
        cells = ProducerCardDisplay.cells(card, directory),
        boardTrailing = ProducerCardDisplay.boardTrailing(card),
        photoUrl = if (ownImages) null else oshi.firstNotNullOfOrNull { it.imageUrl },
        photoEntityId = if (ownImages) firstWithImage(oshi) else null,
        onOpenLink = onOpenLink,
        onOpenOshi = onOpenOshi
    )
}

/** 自分の名刺の写真: 端末に写真を取り込んだ先頭の担当。 */
@Composable
private fun firstWithImage(oshi: List<ImasProducerCardOshi>): String? {
    val store = AppModule.from(androidx.compose.ui.platform.LocalContext.current).customImageStore
    return oshi.firstOrNull { it.entityId != null && store.primaryImageFile(it.entityId) != null }?.entityId
}
