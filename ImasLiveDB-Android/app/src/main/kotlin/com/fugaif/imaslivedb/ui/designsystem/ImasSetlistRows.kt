package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import uniffi.imas_core.RowNoteTone
import uniffi.imas_core.SetlistRowNoteGroupRecord
import uniffi.imas_core.SetlistRowNoteRecord
import kotlin.math.roundToInt

// =============================================================================
// セトリと予想の行 (docs/DESIGN_SYSTEM.md §5.6・§5.8)。iOS `ImasSetlistRows.swift` の移植。
//
// ImasSetlistRow  セトリの 1 曲。曲順・ジャケ・曲名・歌唱者・役割の札・事実 (初披露・回収)。
// ImasForecastRow 予想・機械予測の 1 曲。順位・ジャケ・曲名・根拠・確率 (または票)。
//                 推測なので確率は「%」付きで出し、事実の行 (セトリ) と同じ札を使わない。
//
// どちらもデータは素の値で受け取る (画面の ViewModel が組む)。見た目だけを持つ。
// =============================================================================

/**
 * 歌唱者 1 人ぶんの表示データ (iOS `ImasPerformer`)。
 *
 * @param color イメージカラーの hex。
 * @param isAbsent 欠席 (オリメンだがこの公演に出ない)。
 * @param iconLabel 判子に入れる短い名前 (アイドルの略称)。アイドルでない人 (アイドル情報の無い歌唱者) は null。
 * @param imageUrl 写真の URL。
 * @param entityId アイドルの id。渡すと端末に取り込んだ写真を引く (Android は写真を id で引くため。iOS は URL で渡す)。
 */
@Immutable
data class ImasPerformer(
    val id: String,
    val name: String,
    val color: String? = null,
    val isAbsent: Boolean = false,
    val iconLabel: String? = null,
    val imageUrl: String? = null,
    val entityId: String? = null
)

/** 札 1 枚ぶんのデータ (iOS `ImasBadgeSpec`。行の部品に並べて渡す)。[seed] は色 hex。 */
@Immutable
data class ImasBadgeSpec(
    val text: String,
    val kind: ImasBadgeKind,
    val seed: String? = null
) {
    val id: String get() = "$text-$kind"
}

// MARK: - セトリの 1 曲

/** 事実のうち、墨で強める言葉 (iOS `ImasSetlistRow.firstPerformance`)。 */
const val ImasFirstPerformance = "初披露"

private const val MineMarkId = "mine"
private const val MissingMarkId = "missing"

/**
 * セトリの 1 曲 (iOS `ImasSetlistRow`)。曲名は折り返し優先で省略しない (全体曲の長い曲名も最後まで出す)。
 *
 * @param number 曲順 (「01」)。MC・幕間は null。
 * @param artworkUrl ジャケ。無い曲はブランド色の面に曲名。
 * @param seed ジャケが無いときの色の手がかり (曲の実体の色 hex)。[brand] はブランド ID。
 * @param performerSummary 歌唱者が多いとき (全体曲) に名前の代わりに出す要約 (「全員」「13 人」)。
 * @param badges 役割の札 (ユニット・全員・カバー・一部・主演・ゲスト)。「全員」は [onSelectPerformers] で押せる。
 * @param facts 下段の事実 (「初披露」「12 回目」「回収」)。
 * @param performerLimit 歌唱者の名前を何人まで並べるか。超えたら要約に替える。
 * @param customArtwork ジャケの代わりに置く試聴できるジャケなど (曲順はそのまま左)。試聴の配線は画面側が済ませる。
 * @param onSelectTitle 曲名を押せるようにする (曲の詳細などへ)。
 * @param performersOverride 歌唱者の表示を画面側で組みたいとき ([performers] より優先)。
 * @param onSelectPerformers 歌唱者のアイコンの束を押したとき (歌唱者の一覧シートを開く)。
 * @param highlightsPick 担当 (マイピック) の強調。行の左端に細い帯を立てる。
 * @param avatarSize 歌唱者のアイコンの束の直径 (文字の大きさに合わせて画面側が倍率をかける)。
 * @param artworkSize ジャケの一辺 ([customArtwork] の幅に使う)。
 * @param noteGroups この披露についての事実を軸 (披露・回収) ごとにまとめたもの。分け方・ラベル・順・強さはコアが決める。
 * @param note 自由記述のメモ (MC・コメント等)。斜体の小さい文字で最後に添える。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasSetlistRow(
    number: String?,
    title: String,
    modifier: Modifier = Modifier,
    artworkUrl: String? = null,
    seed: String? = null,
    brand: String? = null,
    performers: List<ImasPerformer> = emptyList(),
    performerSummary: String? = null,
    badges: List<ImasBadgeSpec> = emptyList(),
    facts: List<String> = emptyList(),
    performerLimit: Int = 6,
    customArtwork: (@Composable () -> Unit)? = null,
    onSelectTitle: (() -> Unit)? = null,
    performersOverride: (@Composable () -> Unit)? = null,
    onSelectPerformers: (() -> Unit)? = null,
    highlightsPick: Boolean = false,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    avatarSize: Dp = 26.dp,
    artworkSize: Dp = 44.dp,
    noteGroups: List<SetlistRowNoteGroupRecord> = emptyList(),
    note: String? = null,
    position: ImasRowPosition? = null
) {
    val leading: ImasRowLeading = if (customArtwork == null) {
        ImasRowLeading.NumberedArtwork(
            number = number ?: "",
            title = title,
            seed = seed,
            brand = brand,
            imageUrl = artworkUrl
        )
    } else {
        // 前と同じく上揃え (曲順・ジャケ・末尾を縦の真ん中に寄せない)。
        ImasRowLeading.Custom(width = 24.dp + 10.dp + artworkSize, alignment = Alignment.Top) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                Text(
                    number ?: "",
                    style = ImasType.mono(11.5.sp, FontWeight.Bold),
                    color = DS.ink2,
                    textAlign = TextAlign.End,
                    maxLines = 1,
                    modifier = Modifier
                        .width(24.dp)
                        .padding(top = 2.dp)
                )
                customArtwork()
            }
        }
    }
    Box(modifier) {
        ImasRow(
            title = title,
            leading = leading,
            trailing = trailing,
            titleLineLimit = 99,
            onSelectTitle = onSelectTitle,
            position = position
        ) {
            if (performersOverride != null) {
                performersOverride()
            } else if (performers.isNotEmpty() || performerSummary != null) {
                PerformerLine(performers, performerSummary, performerLimit, avatarSize, onSelectPerformers)
            }
            // 横一列ではなく回り込みにする。幅が足りないとき、横一列だと札の中の文字が折り返して
            // 「1 年 1 か月 / ぶり」と割れて読めなくなる。回り込みなら札ごと次の行に落ちる。
            if (badges.isNotEmpty() || facts.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    badges.forEach { b ->
                        // 「全員」だけは押せる (歌唱者の一覧シートを開く)。他の札はただの表示。
                        if (b.kind == ImasBadgeKind.ALL && onSelectPerformers != null) {
                            ImasBadge(
                                b.text,
                                kind = b.kind,
                                seed = b.seed,
                                modifier = Modifier
                                    .align(Alignment.CenterVertically)
                                    .imasPress(onClick = onSelectPerformers)
                            )
                        } else {
                            ImasBadge(b.text, kind = b.kind, seed = b.seed, modifier = Modifier.align(Alignment.CenterVertically))
                        }
                    }
                    facts.forEach { fact ->
                        val first = fact == ImasFirstPerformance
                        Text(
                            fact,
                            style = ImasType.text(12.sp, if (first) FontWeight.ExtraBold else FontWeight.Normal),
                            color = if (first) DS.ink else DS.ink2,
                            modifier = Modifier.align(Alignment.CenterVertically)
                        )
                    }
                }
            }
            if (noteGroups.isNotEmpty()) {
                NoteGroupsBlock(noteGroups, imasThemeForBrand(seed, brand).accent)
            }
            if (note != null) {
                Text(note, style = ImasTextRole.NOTE.style.copy(fontStyle = FontStyle.Italic), color = ImasTextRole.NOTE.color)
            }
        }
        if (highlightsPick) {
            Box(Modifier.matchParentSize()) {
                Box(
                    Modifier
                        .align(Alignment.CenterStart)
                        .padding(vertical = DS.Space.gap)
                        .width(DS.Size.leadBar)
                        .fillMaxHeight()
                        .background(DS.pick.copy(alpha = 0.7f), RoundedCornerShape(DS.Size.leadBar / 2))
                )
            }
        }
    }
}

/**
 * 歌唱者。アイドルのアイコン (写真か判子) が分かる人がいれば束ねて見せる (アイコンを消さない)。
 * アイコンが分からない人だけのときは名前のチップ、人数だけ多いときはペンライト + 人数。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PerformerLine(
    performers: List<ImasPerformer>,
    summary: String?,
    limit: Int,
    avatarSize: Dp,
    onSelectPerformers: (() -> Unit)?
) {
    when {
        performers.any { it.iconLabel != null || it.imageUrl != null || it.entityId != null } ->
            ImasAvatarStack(performers, maxVisible = 5, size = avatarSize, onTap = onSelectPerformers)
        performers.size > limit || (performers.isEmpty() && summary != null) -> Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(summary ?: "${performers.size} 人", style = ImasTextRole.ROW_SUBTITLE.style, color = DS.ink2)
        }
        else -> FlowRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            performers.forEach { p -> ImasPerformerChip(p.name, seed = p.color, isAbsent = p.isAbsent) }
        }
    }
}

/**
 * **この披露についての事実**の段。軸の名前を固定幅で左に置き、値を右に流す
 * (丸い札を並べると「・」繋ぎの 1 行になって構造が消えるため)。
 */
@Composable
private fun NoteGroupsBlock(groups: List<SetlistRowNoteGroupRecord>, accent: Color) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Box(
            Modifier
                .padding(top = 3.dp, bottom = 2.dp)
                .fillMaxWidth()
                .height(0.5.dp)
                .background(DS.sep)
        )
        groups.forEach { group ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    group.label,
                    style = ImasType.text(11.sp).copy(letterSpacing = 0.4.sp),
                    color = DS.ink3,
                    modifier = Modifier
                        .width(26.dp)
                        .alignByBaseline()
                )
                NotesText(group.notes, accent, Modifier.weight(1f).alignByBaseline())
            }
        }
    }
}

/**
 * 1 つの軸の値を 1 本の文字に連結する。折り返しは文として扱われ、語の途中で割れない。
 * 事実 1 つの見え方は **判断しない** — コアが付けた [RowNoteTone] に対応表を当てるだけ。
 * 色だけで意味を分けず、自分の記録 (回収 / 未回収) には印を付ける。
 */
@Composable
private fun NotesText(notes: List<SetlistRowNoteRecord>, accent: Color, modifier: Modifier) {
    val ink = DS.ink
    val ink2 = DS.ink2
    val ink3 = DS.ink3
    val mine = DS.successInk
    val text = buildAnnotatedString {
        notes.forEachIndexed { index, note ->
            if (index > 0) append("  ")
            when (note.tone) {
                RowNoteTone.VALUE -> withStyle(SpanStyle(color = ink, fontWeight = FontWeight.Medium)) { append(note.text) }
                RowNoteTone.DETAIL -> withStyle(SpanStyle(color = ink3)) { append(note.text) }
                RowNoteTone.DEBUT -> withStyle(SpanStyle(color = accent, fontWeight = FontWeight.SemiBold)) { append(note.text) }
                RowNoteTone.MINE -> {
                    appendInlineContent(MineMarkId, "✓")
                    append(" ")
                    withStyle(SpanStyle(color = mine, fontWeight = FontWeight.SemiBold)) { append(note.text) }
                }
                RowNoteTone.MISSING -> {
                    appendInlineContent(MissingMarkId, "○")
                    append(" ")
                    withStyle(SpanStyle(color = ink2)) { append(note.text) }
                }
            }
        }
    }
    Text(
        text,
        style = ImasType.text(12.sp),
        color = ink2,
        modifier = modifier,
        inlineContent = mapOf(
            MineMarkId to InlineTextContent(Placeholder(10.sp, 10.sp, PlaceholderVerticalAlign.TextCenter)) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = mine, modifier = Modifier.fillMaxSize())
            },
            MissingMarkId to InlineTextContent(Placeholder(10.sp, 10.sp, PlaceholderVerticalAlign.TextCenter)) {
                Icon(Icons.Outlined.RadioButtonUnchecked, contentDescription = null, tint = ink3, modifier = Modifier.fillMaxSize())
            }
        )
    )
}

// MARK: - 予想・機械予測の 1 曲

/** 予想の量 (iOS `ImasForecastRow.Measure`)。 */
@Immutable
sealed interface ImasForecastMeasure {
    /** 機械予測の確率 (0〜1)。 */
    data class Probability(val value: Double) : ImasForecastMeasure

    /** みんなの予想の票数と、いちばん多い票数に対する割合 (0〜1)。 */
    data class Votes(val count: Int, val share: Double) : ImasForecastMeasure
}

/**
 * 曲でなくアイドルの予想 (お題の投票) のときの先頭 (iOS `ImasForecastRow.avatar`)。
 * 写真があれば写真、無ければ判子。[entityId] で端末に取り込んだ写真を引く。
 */
@Immutable
data class ImasForecastAvatar(
    val label: String,
    val imageUrl: String? = null,
    val seed: String? = null,
    val entityId: String? = null
)

/**
 * 予想・機械予測の 1 曲 (iOS `ImasForecastRow`)。順位・ジャケ・曲名・根拠・確率 (または票)。
 *
 * @param subtitle 題の下に 1 行 (ユニット名・歌唱者など)。
 * @param brand ジャケが無いときの面の色 (ブランド ID)。
 * @param avatar 曲でなくアイドルの予想のとき。
 * @param unit 曲でなくユニットの予想のとき ([avatar] より優先)。
 * @param previewUrl 曲の試聴。渡すとジャケのタップが行のタップと別に試聴を切り替える ([onPreviewTap])。
 * @param showsProportionLine 割合の線を出すか。お題の投票 (最多との比較を出さない) では外す。
 * @param reasonLabel 根拠の見出し (「オリメン」「理由」)。[reason] は根拠の文、[performers] は根拠の人 (欠席は薄字と取り消し線)。
 * @param secondReason 2 行目の根拠 (オリメンの行の下に「理由」を出すとき)。見出しと文。
 * @param isVoteDisabled 「予想する」を押せないとき (残りの票が無い)。予想済みの取り消しはいつでも押せる。
 * @param isVoting 「予想する」を送っている最中 (ボタンがくるくるになる)。
 * @param onVote 「予想する」の押し場所。null なら出さない (機械予測)。
 * @param voteAccessibilityLabel 読み上げだけ見た目の文言と変えたいとき (お題の投票はトグルなので「投票」「投票を取消」)。
 * @param voteDisabled 投票ボタンだけを無効にする (他の行の処理中など)。[isVoteDisabled] と違い予想済みの取り消しも止める (お題の投票)。
 * @param isVoteLoading 投票/取消の通信中 ([isVoting] と同じ。お題の投票が使う呼び名)。
 * @param showsChevron 別画面へ進む矢印。行のタップで遷移するときに出す。
 * @param copyItems 長押しでコピーできる項目 (曲名・よみなど)。空なら長押しを付けない。
 * @param combineAccessibility 行の読み上げを 1 つにまとめてよいか。押せるもの (予想・投票のボタン、開く中身) を持つ行は
 *   この値に関わらずまとめない (まとめると中のボタンを読み上げから押せない)。false なら押せるものが無くても分ける
 *   (呼び出し側が行に「詳細を開く」の読み上げの操作を足すとき)。
 * @param accessory 「予想する」の横に並べる補助の操作 (歌唱メンバー予想の開閉など)。
 * @param expansion 行の下に開く中身 (歌唱メンバー予想)。
 * @param onClick 行のタップ (詳細を開く)。長押しのコピーと両立させるため、行の部品が受ける (Android だけ)。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasForecastRow(
    rank: Int,
    title: String,
    measure: ImasForecastMeasure,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    artworkUrl: String? = null,
    brand: String? = null,
    avatar: ImasForecastAvatar? = null,
    unit: ImasUnit? = null,
    previewUrl: String? = null,
    isPreviewing: Boolean = false,
    onPreviewTap: (() -> Unit)? = null,
    showsProportionLine: Boolean = true,
    reasonLabel: String? = null,
    reason: String? = null,
    performers: List<ImasPerformer> = emptyList(),
    secondReason: Pair<String, String>? = null,
    isMine: Boolean = false,
    isVoteDisabled: Boolean = false,
    isVoting: Boolean = false,
    onVote: (() -> Unit)? = null,
    voteLabel: String = "予想する",
    votedLabel: String = "予想した",
    voteAccessibilityLabel: String? = null,
    votedAccessibilityLabel: String? = null,
    voteDisabled: Boolean = false,
    isVoteLoading: Boolean = false,
    showsChevron: Boolean = false,
    copyItems: List<CopyItem> = emptyList(),
    combineAccessibility: Boolean = true,
    accessory: (@Composable () -> Unit)? = null,
    expansion: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    val fraction = when (measure) {
        is ImasForecastMeasure.Probability -> measure.value
        is ImasForecastMeasure.Votes -> measure.share
    }
    // 押せるものを持つ行は要素をまとめない (まとめると中のボタンを読み上げから押せない)。
    val combines = combineAccessibility && onVote == null && expansion == null
    val mainRow: @Composable () -> Unit = {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
            verticalAlignment = Alignment.Top
        ) {
            ImasRankNumber(rank, Modifier.padding(top = 10.dp))
            when {
                unit != null -> ImasUnitAvatar(unit, size = 40.dp)
                // アイドル・ユニットの候補は写真があれば写真、無ければ判子 (アイコンを消さない)。
                avatar != null -> ImasAvatar(
                    label = avatar.label,
                    seed = avatar.seed,
                    brand = brand,
                    size = 40.dp,
                    imageUrl = avatar.imageUrl,
                    entityId = avatar.entityId,
                    reservesPickRing = false
                )
                else -> ImasArtwork(
                    title = title,
                    brand = brand,
                    size = 44.dp,
                    imageUrl = artworkUrl,
                    previewUrl = previewUrl,
                    isPreviewing = isPreviewing,
                    onPreview = onPreviewTap
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    Text(
                        title,
                        style = ImasTextRole.ROW_TITLE.style,
                        color = DS.ink,
                        maxLines = 2,
                        modifier = Modifier
                            .weight(1f)
                            .alignByBaseline()
                    )
                    val (value, unitText) = when (measure) {
                        is ImasForecastMeasure.Probability -> "${(measure.value * 100).roundToInt()}" to "%"
                        is ImasForecastMeasure.Votes -> "${measure.count}" to "票"
                    }
                    ImasMetric(
                        value,
                        modifier = Modifier.alignByBaseline(),
                        unit = unitText,
                        size = ImasNumeralSize.MEDIUM,
                        emphasized = rank <= 3
                    )
                    if (showsChevron) ImasRowChevron(Modifier.align(Alignment.CenterVertically))
                }
                if (!subtitle.isNullOrEmpty()) {
                    Text(subtitle, style = ImasTextRole.ROW_SUBTITLE.style, color = DS.ink2, maxLines = 1)
                }
                if (reason != null || performers.isNotEmpty()) {
                    ReasonLine(reasonLabel, reason, performers)
                }
                if (secondReason != null) {
                    ReasonLine(secondReason.first, secondReason.second, emptyList())
                }
                if (showsProportionLine) {
                    ImasProportionLine(fraction, Modifier.padding(top = 2.dp))
                }
                if (onVote != null || accessory != null) {
                    Row(
                        Modifier.padding(top = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (onVote != null) {
                            ImasButton(
                                title = if (isMine) votedLabel else voteLabel,
                                onClick = onVote,
                                icon = if (isMine) Icons.Filled.Check else Icons.Outlined.ThumbUp,
                                role = if (isMine) ImasButtonRole.PRIMARY else ImasButtonRole.SECONDARY,
                                size = ImasButtonSize.SMALL,
                                isLoading = isVoting || isVoteLoading,
                                // 予想済みの取り消しは残りの票に関わらず押せる (isVoteDisabled)。
                                // お題の投票は他の行の処理中なども含めてボタンごと止める (voteDisabled)。
                                enabled = !(voteDisabled || (isVoteDisabled && !isMine)),
                                accessibilityLabel = if (isMine) votedAccessibilityLabel ?: votedLabel else voteAccessibilityLabel ?: voteLabel
                            )
                        }
                        accessory?.invoke()
                    }
                } else if (isMine) {
                    // 投票できない状態 (締切後など) でも、自分が選んだことは押せない印で残す。
                    Row(
                        Modifier.padding(top = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Filled.Check,
                            contentDescription = null,
                            tint = DS.ink2,
                            modifier = Modifier.size(with(LocalDensity.current) { 12.sp.toDp() })
                        )
                        Text(votedLabel, style = ImasTextRole.BADGE.style, color = DS.ink2)
                    }
                }
            }
        }
    }
    val row: @Composable () -> Unit = {
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (combines) Modifier.semantics(mergeDescendants = true) { } else Modifier)
        ) {
            mainRow()
            if (expansion != null) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(start = DS.Space.rowH + ImasRankNumberWidth + DS.Space.rowGap, end = DS.Space.rowH, bottom = DS.Space.rowV)
                ) { expansion() }
            }
        }
    }
    ImasCopyableRow(items = copyItems, modifier = modifier.fillMaxWidth(), onClick = onClick, content = row)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ReasonLine(label: String?, reason: String?, performers: List<ImasPerformer>) {
    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        if (label != null) {
            Text(label, style = ImasTextRole.BADGE.style, color = DS.ink3, maxLines = 1, modifier = Modifier.alignByBaseline())
        }
        if (performers.isNotEmpty()) {
            FlowRow(
                Modifier
                    .weight(1f)
                    .alignByBaseline(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                performers.forEach { p ->
                    ImasPerformerChip(p.name, seed = p.color, isAbsent = p.isAbsent, modifier = Modifier.align(Alignment.CenterVertically))
                }
                if (reason != null) {
                    Text(
                        reason,
                        style = ImasTextRole.ROW_SUBTITLE.style,
                        color = DS.ink2,
                        modifier = Modifier.align(Alignment.CenterVertically)
                    )
                }
            }
        } else if (reason != null) {
            Text(
                reason,
                style = ImasTextRole.ROW_SUBTITLE.style,
                color = DS.ink2,
                maxLines = 2,
                modifier = Modifier
                    .weight(1f)
                    .alignByBaseline()
            )
        }
    }
}
