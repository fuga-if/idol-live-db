package com.fugaif.imaslivedb.ui.idols

import com.fugaif.imaslivedb.data.model.Idol

/**
 * アイドル一覧の並び順 (iOS `IdolSortOrder` の 1:1 移植)。
 *
 * [OFFICIAL] 以外を選ぶと **ブランドの区切りを外した通し並び** になる。
 * 「誰がいちばん背が高いか」はブランドを跨いで初めて意味を持つ指標で、
 * ブランド別セクションの中で身長順にしても知りたいことが分からないため。
 */
enum class IdolSortOrder(
    val label: String,
    /** 未指定時の並び方向。数値系は「大きい順」の方が知りたい形 (背が高い順・年上順)。 */
    val defaultAscending: Boolean,
    val ascendingLabel: String,
    val descendingLabel: String
) {
    OFFICIAL("公式順", true, "公式順", "逆順"),
    NAME_KANA("五十音順", true, "あ→ん", "ん→あ"),
    AGE("年齢", false, "年下から", "年上から"),
    HEIGHT("身長", false, "低い順", "高い順"),
    WEIGHT("体重", false, "軽い順", "重い順"),
    BIRTHDAY("誕生日", true, "1月から", "12月から"),
    DEBUT("デビュー日", true, "古い順", "新しい順");

    /** ブランド別セクションを維持するか。 */
    val keepsBrandGrouping: Boolean get() = this == OFFICIAL

    /** 行に併記する指標のラベル (null ならバッジを出さない)。 */
    fun metricLabel(idol: Idol): String? = when (this) {
        OFFICIAL, NAME_KANA -> null
        AGE -> idol.age?.let { "${it}歳" }
        HEIGHT -> idol.height?.let { "${it.toInt()}cm" }
        WEIGHT -> idol.weight?.let { "${it.toInt()}kg" }
        BIRTHDAY -> idol.birthday?.let(::formatBirthdayLabel)
        DEBUT -> idol.debutDate
    }
}

/** "--04-03" → "4月3日" (iOS `Idol.birthdayDisplay` 相当)。 */
private fun formatBirthdayLabel(birthday: String): String =
    birthday.removePrefix("--").split("-")
        .let { if (it.size == 2) "${it[0].toIntOrNull() ?: it[0]}月${it[1].toIntOrNull() ?: it[1]}日" else birthday }

/**
 * アイドル一覧を指定の並び順で整列する。
 *
 * 値が無いアイドル (年齢・身長 未設定の外部ゲスト等) は **並び方向に関わらず必ず末尾**へ送る。
 * 昇順で先頭に空欄が並ぶと「若い順」を見に来た人の視界を潰すため。
 * 同値は公式順 (sortOrder) で安定させる。
 */
fun sortIdols(idols: List<Idol>, order: IdolSortOrder, ascending: Boolean? = null): List<Idol> {
    val asc = ascending ?: order.defaultAscending

    if (order == IdolSortOrder.OFFICIAL) {
        return if (asc) idols.sortedBy { it.sortOrder } else idols.sortedByDescending { it.sortOrder }
    }

    fun numberKey(idol: Idol): Double? = when (order) {
        IdolSortOrder.AGE -> idol.age?.toDouble()
        IdolSortOrder.HEIGHT -> idol.height
        IdolSortOrder.WEIGHT -> idol.weight
        else -> null
    }

    fun textKey(idol: Idol): String? = when (order) {
        IdolSortOrder.NAME_KANA -> (idol.nameKana ?: idol.name).ifEmpty { null }
        IdolSortOrder.BIRTHDAY -> idol.birthday?.ifEmpty { null }
        IdolSortOrder.DEBUT -> idol.debutDate?.ifEmpty { null }
        else -> null
    }

    fun hasValue(idol: Idol): Boolean = numberKey(idol) != null || textKey(idol) != null

    val comparator = Comparator<Idol> { a, b ->
        // 値なしは方向に関わらず末尾
        val aHas = hasValue(a)
        val bHas = hasValue(b)
        if (aHas != bHas) return@Comparator if (aHas) -1 else 1
        if (!aHas) return@Comparator a.sortOrder.compareTo(b.sortOrder)

        val cmp = numberKey(a)?.let { na -> numberKey(b)?.let { nb -> na.compareTo(nb) } }
            ?: textKey(a)?.let { ta -> textKey(b)?.let { tb -> ta.compareTo(tb) } }
            ?: 0
        if (cmp != 0) (if (asc) cmp else -cmp) else a.sortOrder.compareTo(b.sortOrder)
    }
    return idols.sortedWith(comparator)
}
