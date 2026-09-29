package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.songs.SongSearchMode
import com.fugaif.imaslivedb.ui.theme.DS
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
 * 楽曲一覧の行。iOS SongRowView 構成: ImasLeadBar(ブランド) + ImasArtwork(プレビュー対応) +
 * 曲名(+タグ票数バッジ) + 歌唱者/ユニット + マイマーク行(担当/現地回収)。
 *
 * ★お気に入りトグルは行から撤去済み (2026-09、iOS と同じ)。一覧で毎行トグルできても
 * 実際にはほとんど使われず、行の情報密度だけが上がっていた。お気に入り自体は
 * 曲詳細のボタン・お気に入り一覧・絞り込みに残しているので機能は消えていない。
 *
 * 絞り込み中は [searchMatch] を渡すと、当たった箇所に色を敷き、スコープに応じて
 * 「なぜこの行が出ているか」の補足 (当たった歌唱者を先頭に / 当たった作家の役割行) を出す。
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
    /** 渡すと長押しメニューに「習熟度を変える」が出る (行から直に段階を付けるため)。 */
    onEditMastery: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    // 長押しで曲名などをコピーできるようにする (正式な曲名で外部検索したい用途)。
    Copyable(
        items = listOf(
            CopyItem("曲名をコピー", title),
            CopyItem("歌唱者をコピー", artistNames.ifEmpty { unitName }),
        ),
        actions = onEditMastery?.let { listOf(RowAction("習熟度を変える", it)) } ?: emptyList(),
        modifier = modifier.fillMaxWidth()
    ) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
    ) {
        ImasLeadBar(brandId = brandId, height = 44.dp)
        ArtworkImage(url = artworkUrl, size = 44.dp, previewUrl = previewUrl, songTitle = title, songId = songId)
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = rememberHighlighted(title, searchMatch.needleFor(SongSearchMode.TITLE)),
                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (tagVoteCount != null) {
                    TagVoteBadge(count = tagVoteCount)
                }
            }
            val performerNeedle = searchMatch.needleFor(SongSearchMode.PERFORMER)
            val sub = artistNames.ifEmpty { unitName ?: "" }
            // アイドルで絞っているときは当たった 1 人を先頭に出す。連名をそのまま出すと
            // 当たった名前が右端で切れて、当たった理由が行から消える。
            val performerText = performerNeedle?.let { searchMatch?.detail } ?: sub
            if (performerText.isNotEmpty()) {
                Text(
                    text = rememberHighlighted(performerText, performerNeedle),
                    fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            CreatorLine(
                needle = searchMatch.needleFor(SongSearchMode.CREATOR),
                text = searchMatch?.detail
            )
            if (releaseDate != null || isMyPick || (collectedCount ?: 0) > 0 || masteryLevel > 0u) {
                MarkRow(releaseDate = releaseDate, isMyPick = isMyPick, collectedCount = collectedCount,
                        masteryLevel = masteryLevel, masteryScale = masteryScale)
            }
        }
    }
}
}

@Composable
private fun TagVoteBadge(count: Int) {
    androidx.compose.material3.Surface(
        shape = CircleShape,
        color = DS.favorite.copy(alpha = 0.14f)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
        ) {
            Icon(imageVector = Icons.Filled.Sell, contentDescription = null, tint = DS.favorite, modifier = Modifier.size(11.dp))
            Text(text = "$count", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = DS.favorite)
        }
    }
}

/**
 * 作詞・作曲・編曲で絞っているときだけ出す行 (iOS `SongRowView.creatorLine` 相当)。
 * 普段の一覧には要らない情報なので、当たった理由を見せる必要があるときにだけ増やす。
 */
@Composable
private fun CreatorLine(needle: String?, text: String?) {
    if (needle == null || text == null) return
    Text(
        text = rememberHighlighted(text, needle),
        fontSize = 11.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis
    )
}

/** マイマーク行 (リリース日 / 担当♥ / 現地回収✓)。iOS SongRowView.markRow 相当。 */
@Composable
private fun MarkRow(
    releaseDate: String?, isMyPick: Boolean, collectedCount: Int?,
    masteryLevel: UByte = 0u, masteryScale: MasteryScale = MasteryScale.standard,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (!releaseDate.isNullOrEmpty()) {
            Text(text = releaseDate, fontSize = 11.sp, color = DS.ink3)
        }
        if (isMyPick) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Icon(imageVector = Icons.Filled.Favorite, contentDescription = null, tint = DS.pick, modifier = Modifier.size(11.dp))
                Text(text = "担当", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.pick)
            }
        }
        if (masteryLevel > 0u) {
            MasteryChip(masteryLevel, masteryScale)
        }
        if ((collectedCount ?: 0) > 0) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Icon(imageVector = Icons.Filled.Check, contentDescription = null, tint = DS.success, modifier = Modifier.size(11.dp))
                Text(text = "$collectedCount", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = DS.success)
            }
        }
    }
}

/** そのスコープで絞っているときの検索語 (前後の空白は落とす)。違うスコープなら null。 */
private fun SongRowMatch?.needleFor(scope: SongSearchMode): String? =
    this?.takeIf { it.scope == scope }?.text?.trim()?.takeIf { it.isNotEmpty() }
