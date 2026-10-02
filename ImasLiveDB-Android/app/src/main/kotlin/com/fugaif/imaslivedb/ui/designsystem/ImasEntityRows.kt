package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.components.RowAction
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.spokenDate

// =============================================================================
// 実体ごとの行 (docs/DESIGN_SYSTEM.md §5.1〜§5.5・§5.14)。iOS `ImasEntityRows.swift` の移植。
//
// 同じ実体はアプリ中どこでも同じ行で出す。中身は `ImasRow` の枠を実体のデータで埋めたもの。
// 画面ごとの足し算 (並べ替えの根拠・印・下段の札) は trailing と detail で渡す。
//
// ImasSongRow   ジャケ・曲名・歌唱者 (曲のデータから組む形は ui/components/DSAdapters.kt。試聴の配線が要るため)
// ImasIdolRow   アバター (担当は二重輪)・名前・ブランドと CV
// ImasUnitRow   ユニットのアバター・ユニット名・メンバー
// ImasEventRow  半券 (初日)・ライブ名・会場と期間
// ImasShowRow   半券 (日付)・公演名・開演と会場
// ImasRecordRow 記号・何をしたか・誰がいつ・操作の札 (編集履歴・お知らせ)
// =============================================================================

// MARK: - 曲

/**
 * 曲の行 (iOS `ImasSongRow`)。先頭はジャケ (無ければブランド色の面 + 曲名)。
 *
 * 回収は印にしない (ジャケに判子を押さない。回収は下段の札 ✓N)。
 *
 * @param brand ジャケが無いときの面とリードバーの色 (ブランド ID。iOS の `brandHex`)。[seed] は色 hex で直に渡すとき。
 * @param showsBrandBar 行頭にブランドの色の帯を立てる (楽曲一覧)。
 * @param previewUrl 試聴できる音源。渡すとジャケのタップが行のタップと別に試聴を切り替える ([onPreviewTap])。
 * @param copyItems 長押しでコピーできる項目 (曲名・よみ・歌唱者など)。空なら長押しを付けない。
 * @param attributedSubtitle 副題の代わりに強調付きの文字 (絞り込みで当たった歌唱者に色を敷くなど)。
 * @param actions 長押しメニューに足す、コピー以外の操作 (行から直に習熟度を変えるなど)。
 */
@Composable
fun ImasSongRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    artworkUrl: String? = null,
    brand: String? = null,
    seed: String? = null,
    showsBrandBar: Boolean = false,
    previewUrl: String? = null,
    isPreviewing: Boolean = false,
    onPreviewTap: (() -> Unit)? = null,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    density: ImasRowDensity = ImasRowDensity.REGULAR,
    emphasis: ImasRowEmphasis = ImasRowEmphasis.NORMAL,
    attributedTitle: AnnotatedString? = null,
    attributedSubtitle: AnnotatedString? = null,
    copyItems: List<CopyItem> = emptyList(),
    actions: List<RowAction> = emptyList(),
    onClick: (() -> Unit)? = null,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    val size = density.artworkSize
    // 試聴に対応する呼び出しだけ、ジャケに試聴の口を足す (行の先頭の種類はそのまま)。
    val leading: ImasRowLeading = if (previewUrl == null) {
        ImasRowLeading.Artwork(title = title, seed = seed, brand = brand, imageUrl = artworkUrl)
    } else {
        ImasRowLeading.Custom(width = size) {
            ImasArtwork(
                title = title,
                seed = seed,
                brand = brand,
                size = size,
                imageUrl = artworkUrl,
                previewUrl = previewUrl,
                isPreviewing = isPreviewing,
                onPreview = onPreviewTap
            )
        }
    }
    val row: @Composable () -> Unit = {
        ImasRow(
            title = title,
            subtitle = subtitle,
            leading = leading,
            leadBar = if (showsBrandBar) ImasRowLeadBar(seed = seed, brand = brand) else null,
            trailing = trailing,
            density = density,
            emphasis = emphasis,
            titleLineLimit = if (density == ImasRowDensity.COMPACT) 1 else 2,
            attributedTitle = attributedTitle,
            attributedSubtitle = attributedSubtitle,
            detail = detail
        )
    }
    ImasCopyableRow(items = copyItems, modifier = modifier.fillMaxWidth(), onClick = onClick, actions = actions, content = row)
}

// MARK: - アイドル

/**
 * アイドルの行 (iOS `ImasIdolRow`)。先頭はアイコン (写真、無ければ略称の判子。担当は二重の輪)。
 * 長押しで名前とよみをコピーできる。
 *
 * @param subtitle 既定はブランドの略称など (呼び出し側が組む)。
 * @param brand アイドル本人の色が無いときのブランド ID。null なら [Idol.brandId]。
 */
@Composable
fun ImasIdolRow(
    idol: Idol,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    brand: String? = null,
    isPick: Boolean = false,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    density: ImasRowDensity = ImasRowDensity.REGULAR,
    onClick: (() -> Unit)? = null,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    ImasCopyableRow(
        items = listOf(CopyItem("アイドル名をコピー", idol.name), CopyItem("よみをコピー", idol.nameKana)),
        modifier = modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        ImasRow(
            title = idol.name,
            subtitle = subtitle,
            leading = ImasRowLeading.Avatar(
                label = idol.shortName,
                seed = idol.color,
                brand = brand ?: idol.brandId,
                isPick = isPick,
                entityId = idol.id
            ),
            trailing = trailing,
            density = density,
            titleLineLimit = 1,
            detail = detail
        )
    }
}

// MARK: - ユニット

/**
 * ユニットの行 (iOS `ImasUnitRow`)。先頭はユニットのアイコン、副題はメンバー (3 人まで + 「ほか N 人」)。
 */
@Composable
fun ImasUnitRow(
    unit: ImasUnit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    density: ImasRowDensity = ImasRowDensity.REGULAR
) {
    val size = density.avatarSize
    ImasRow(
        title = unit.displayName,
        modifier = modifier,
        subtitle = subtitle,
        leading = ImasRowLeading.Custom(width = size) { ImasUnitAvatar(unit, size = size) },
        trailing = trailing,
        density = density,
        titleLineLimit = 1
    )
}

// MARK: - ライブ

/**
 * ライブ 1 件の行 (iOS `ImasEventRow`)。半券の形 (左に初日、右にライブ名と日付・会場)。
 * 題はライブ名の作品名を省いた形 (設定に従う)、長押しで正式名称をコピー。
 *
 * @param date 初日 (`yyyy-MM-dd`)。半券の日付欄に出す。null なら横棒。
 * @param subtitle 会場・期間 (「Kアリーナ横浜 · 〜 11/8 (日)」)。
 * @param rainbow 合同ライブ (複数ブランド名義) は単色で表せないので、ペンライトを虹色にする。
 * @param detailAccessibilityLabel [detail] の見た目 (チップのボタンなど) に添える読み上げ。
 * @param subtitleLineLimit 副題の行数。既定は 1 行。会場 + 補足などで長い行は 2 にする。
 */
@Composable
fun ImasEventRow(
    event: Event,
    modifier: Modifier = Modifier,
    date: String? = null,
    subtitle: String? = null,
    badges: List<ImasBadgeSpec> = emptyList(),
    emphasis: ImasRowEmphasis = ImasRowEmphasis.NORMAL,
    rainbow: Boolean = false,
    showsChevron: Boolean = false,
    detailAccessibilityLabel: String? = null,
    subtitleLineLimit: Int = 1,
    onClick: (() -> Unit)? = null,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    val spoken = remember(date) { date?.let { spokenDate(it) } }
    ImasCopyableRow(
        items = listOf(CopyItem("ライブ名をコピー", event.name)),
        modifier = modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        ImasStubRow(
            date = date?.let { ImasStubDate(it) } ?: ImasStubDate.Unknown,
            title = AppPreferences.eventDisplayName(event.name),
            subtitle = subtitle,
            brand = event.brandId,
            badges = badges,
            emphasis = emphasis,
            rainbow = rainbow,
            spokenDate = spoken,
            showsChevron = showsChevron,
            detailAccessibilityLabel = detailAccessibilityLabel,
            subtitleLineLimit = subtitleLineLimit,
            detail = detail
        )
    }
}

// MARK: - 公演

/**
 * 公演 1 件の行 (iOS `ImasShowRow`)。半券の形 (左に日付、右に公演名と開演・会場)。
 *
 * @param date 公演の日 (`yyyy-MM-dd`)。読み上げはコアの `spokenDate` (「2026年11月7日 土曜日」)。
 * @param title 公演名 (DAY1 など)。
 * @param subtitle 開演・会場・出演者数。
 * @param brand ブランド ID (iOS の `brandHex`)。[seed] は色 hex で直に渡すとき。
 */
@Composable
fun ImasShowRow(
    date: String,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    brand: String? = null,
    seed: String? = null,
    badges: List<ImasBadgeSpec> = emptyList(),
    emphasis: ImasRowEmphasis = ImasRowEmphasis.NORMAL,
    rainbow: Boolean = false,
    showsChevron: Boolean = false,
    subtitleLineLimit: Int = 1,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    val spoken = remember(date) { spokenDate(date) }
    ImasStubRow(
        date = ImasStubDate(date),
        title = title,
        modifier = modifier,
        subtitle = subtitle,
        seed = seed,
        brand = brand,
        badges = badges,
        emphasis = emphasis,
        rainbow = rainbow,
        spokenDate = spoken,
        showsChevron = showsChevron,
        subtitleLineLimit = subtitleLineLimit,
        detail = detail
    )
}

// MARK: - 記録

/**
 * 編集履歴・お知らせ・支出・タグの活動など「何かが起きた記録」の行 (iOS `ImasRecordRow`)。
 *
 * 先頭は記号 ([icon]、既定の形) のほか、[leading] で渡せばアイドルのアイコンやジャケにもできる。
 * diff の本文など自由な中身を足したいときは [detail] を渡す。
 *
 * @param title 何をしたか (「THE IDOLM@STER の歌唱者を直した」)。
 * @param subtitle 誰が・いつ (「よ〜だ · 3分前」)。
 * @param badges 操作の札 (追加・変更・削除・差し戻し)。
 * @param titleLineLimit 題の行数。長い対象名などを省略したくないときに増やす。
 */
@Composable
fun ImasRecordRow(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    tone: ImasIconTileTone = ImasIconTileTone.NEUTRAL,
    leading: ImasRowLeading? = null,
    titleLineLimit: Int = 2,
    subtitle: String? = null,
    badges: List<ImasBadgeSpec> = emptyList(),
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    ImasRow(
        title = title,
        modifier = modifier,
        subtitle = subtitle,
        leading = leading ?: icon?.let { ImasRowLeading.Icon(it, tone = tone) } ?: ImasRowLeading.None,
        trailing = trailing,
        titleLineLimit = titleLineLimit
    ) {
        if (badges.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                badges.forEach { ImasBadge(it.text, kind = it.kind, seed = it.seed) }
            }
        }
        detail?.invoke(this)
    }
}
