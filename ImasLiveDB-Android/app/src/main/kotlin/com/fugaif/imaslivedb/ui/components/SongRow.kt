package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.remember
import uniffi.imas_core.songCreditLabel
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow
import com.fugaif.imaslivedb.ui.songs.SongSearchMode
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.MasteryScale
import com.fugaif.imaslivedb.ui.mastery.MasteryChip

/**
 * 行がなぜ結果に入っているか。絞り込みの対象と入力語 (iOS `SongRowMatch` と 1:1)。
 *
 * 検索対象ごとに示し方を変えると、同じ一覧なのに読み方を切り替えることになる。
 * どのスコープでも「当たった箇所に同じ色を敷く」に揃える。
 */
data class SongRowMatch(
    val text: String,
    val scope: SongSearchMode,
    /**
     * 歌唱・作詞作曲スコープで「なぜこの行が出ているか」を示す 1 行 (当たった 1 人を先頭に
     * 「ほか N 人」/ 当たった役割と名前)。作るのはコア (searchMatchTexts)。無ければ補足を出さない。
     */
    val detail: String? = null
)

/**
 * 楽曲一覧の行。DS の [ImasSongRow] (§5.1) で組む: 先頭=ジャケ (ブランドの色の帯つき・試聴対応)、
 * 題=曲名 (絞り込みで当たった所に色を敷く)、副題=歌唱者/ユニット (同じく当たった所に色を敷く)、
 * 下段=作家の絞り込み理由・マイマーク行 (リリース日・担当♥・習熟度・現地回収✓N)。
 *
 * タグ票数はジャケ横ではなく行の末尾の札に出す (`ImasRowTrailing.Badge`。DS §10.1 の
 * 置き換え先どおり「タグの票数」は `.themed` の線の札)。
 *
 * ★お気に入りトグルは行から撤去済み (2026-09、iOS と同じ)。一覧で毎行トグルできても
 * 実際にはほとんど使われず、行の情報密度だけが上がっていた。お気に入り自体は
 * 曲詳細のボタン・お気に入り一覧・絞り込みに残しているので機能は消えていない。
 *
 * メモ(hasNote)は Android にメモ編集 UI が無いため対象外 (iOS のみ)。
 */
@Composable
fun SongRow(
    title: String,
    /** 再生中の強調と試聴の切り替えに使う `songs.id`。曲名では同名別録音を取り違える。 */
    songId: String? = null,
    artistNames: String,
    unitName: String?,
    /** 名義 (`songs.singer_label`)。全体曲は個人名を連ねず、ここかユニット名を出す。 */
    singerLabel: String? = null,
    artworkUrl: String? = null,
    previewUrl: String? = null,
    brandId: String? = null,
    releaseDate: String? = null,
    isMyPick: Boolean = false,
    collectedCount: Int? = null,
    /** 習熟度の段階 (0 = 未設定)。付いているときだけ行に小さく出す。
     *  更新したのが分からないと連続で付けていく作業が成立しない。 */
    masteryLevel: UByte = 0u,
    masteryScale: MasteryScale = MasteryScale.standard,
    tagVoteCount: Int? = null,
    searchMatch: SongRowMatch? = null,
    modifier: Modifier = Modifier
) {
    val playback by AudioPreviewManager.playbackState.collectAsState()
    val isPreviewing = previewUrl != null && songId != null && playback.isPlaying(songId)

    val titleNeedle = searchMatch.needleFor(SongSearchMode.TITLE)
    val performerNeedle = searchMatch.needleFor(SongSearchMode.PERFORMER)
    val creatorNeedle = searchMatch.needleFor(SongSearchMode.CREATOR)
    // アイドルで絞っているときは当たった 1 人を先頭に出す。連名をそのまま出すと
    // 当たった名前が右端で切れて、当たった理由が行から消える。
    // 名義はユニット名 → 名義 → 個人名の並び (規則はコア)。
    val sub = remember(unitName, singerLabel, artistNames) { songCreditLabel(unitName, singerLabel, artistNames) }
    val performerText = performerNeedle?.let { searchMatch?.detail } ?: sub

    ImasSongRow(
        title = title,
        attributedTitle = rememberHighlighted(title, titleNeedle),
        attributedSubtitle = performerText.takeIf { it.isNotEmpty() }?.let { rememberHighlighted(it, performerNeedle) },
        artworkUrl = artworkUrl,
        brand = brandId,
        showsBrandBar = true,
        previewUrl = previewUrl,
        isPreviewing = isPreviewing,
        onPreviewTap = { if (previewUrl != null && songId != null) AudioPreviewManager.togglePreview(previewUrl, songId) },
        trailing = if (tagVoteCount != null) {
            ImasRowTrailing.Badge(text = "$tagVoteCount", kind = ImasBadgeKind.THEMED, icon = Icons.Filled.Sell)
        } else {
            ImasRowTrailing.None
        },
        modifier = modifier,
        detail = {
            CreatorLine(needle = creatorNeedle, text = searchMatch?.detail)
            if (releaseDate != null || isMyPick || (collectedCount ?: 0) > 0 || masteryLevel > 0u) {
                MarkRow(
                    releaseDate = releaseDate, isMyPick = isMyPick, collectedCount = collectedCount,
                    masteryLevel = masteryLevel, masteryScale = masteryScale
                )
            }
        }
    )
}

/**
 * 作詞・作曲・編曲で絞っているときだけ出す行 (iOS `SongRowView.creatorLine` 相当)。
 * 普段の一覧には要らない情報なので、当たった理由を見せる必要があるときにだけ増やす。
 */
@Composable
private fun ColumnScope.CreatorLine(needle: String?, text: String?) {
    if (needle == null || text == null) return
    Text(
        text = rememberHighlighted(text, needle),
        style = ImasTextRole.META.style,
        color = DS.ink3,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

/** マイマーク行 (リリース日 / 担当♥ / 現地回収✓)。iOS SongRowView.markRow 相当。 */
@Composable
private fun ColumnScope.MarkRow(
    releaseDate: String?, isMyPick: Boolean, collectedCount: Int?,
    masteryLevel: UByte = 0u, masteryScale: MasteryScale = MasteryScale.standard,
) {
    val iconSize = with(LocalDensity.current) { 11.sp.toDp() }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        if (!releaseDate.isNullOrEmpty()) {
            ImasText(releaseDate, ImasTextRole.META)
        }
        if (isMyPick) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                Icon(imageVector = Icons.Filled.Favorite, contentDescription = null, tint = DS.pick, modifier = Modifier.size(iconSize))
                ImasText("担当", ImasTextRole.EYEBROW, color = DS.pick)
            }
        }
        if (masteryLevel > 0u) {
            MasteryChip(masteryLevel, masteryScale)
        }
        if ((collectedCount ?: 0) > 0) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                Icon(imageVector = Icons.Filled.Check, contentDescription = null, tint = DS.success, modifier = Modifier.size(iconSize))
                ImasMetric("$collectedCount", size = ImasNumeralSize.SMALL, emphasized = true, color = DS.success)
            }
        }
    }
}

/** そのスコープで絞っているときの検索語 (前後の空白は落とす)。違うスコープなら null。 */
private fun SongRowMatch?.needleFor(scope: SongSearchMode): String? =
    this?.takeIf { it.scope == scope }?.text?.trim()?.takeIf { it.isNotEmpty() }
