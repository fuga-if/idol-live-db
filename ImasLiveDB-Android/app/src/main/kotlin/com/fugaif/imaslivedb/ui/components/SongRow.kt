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
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.core.TextSearch
import com.fugaif.imaslivedb.ui.songs.SongSearchMode
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 行がなぜ結果に入っているか。絞り込みの対象と入力語 (iOS `SongRowMatch` と 1:1)。
 *
 * 検索対象ごとに示し方を変えると、同じ一覧なのに読み方を切り替えることになる。
 * どのスコープでも「当たった箇所に同じ色を敷く」に揃える。
 */
data class SongRowMatch(val text: String, val scope: SongSearchMode)

/**
 * 楽曲一覧の行。iOS SongRowView 構成: ImasLeadBar(ブランド) + ImasArtwork(プレビュー対応) +
 * 曲名(+タグ票数バッジ) + 歌唱者/ユニット + マイマーク行(担当/現地回収) + お気に入りトグル。
 *
 * 絞り込み中は [searchMatch] を渡すと、当たった箇所に色を敷き、スコープに応じて
 * 「なぜこの行が出ているか」の補足 (当たった歌唱者を先頭に / 当たった作家の役割行) を出す。
 *
 * メモ(hasNote)は Android にメモ編集 UI が無いため対象外 (iOS のみ)。
 */
@Composable
fun SongRow(
    title: String,
    artistNames: String,
    unitName: String?,
    artworkUrl: String? = null,
    previewUrl: String? = null,
    brandId: String? = null,
    releaseDate: String? = null,
    isFavorite: Boolean = false,
    isMyPick: Boolean = false,
    collectedCount: Int? = null,
    tagVoteCount: Int? = null,
    // 作詞作曲スコープで絞ったときに「どの役割で当たったか」を出すために要る。
    // 出すのは当たった行だけなので、渡していない画面は今までどおり何も増えない。
    lyricist: String? = null,
    composer: String? = null,
    arranger: String? = null,
    searchMatch: SongRowMatch? = null,
    onFavoriteToggle: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    // 長押しで曲名などをコピーできるようにする (正式な曲名で外部検索したい用途)。
    Copyable(
        items = listOf(
            CopyItem("曲名をコピー", title),
            CopyItem("歌唱者をコピー", artistNames.ifEmpty { unitName }),
        ),
        modifier = modifier.fillMaxWidth()
    ) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
    ) {
        ImasLeadBar(brandId = brandId, height = 44.dp)
        ArtworkImage(url = artworkUrl, size = 44.dp, previewUrl = previewUrl, songTitle = title)
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
            val performerText = remember(sub, performerNeedle) {
                performerNeedle?.let { matchedPerformerText(sub, it) } ?: sub
            }
            if (performerText.isNotEmpty()) {
                Text(
                    text = rememberHighlighted(performerText, performerNeedle),
                    fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            CreatorLine(
                needle = searchMatch.needleFor(SongSearchMode.CREATOR),
                lyricist = lyricist, composer = composer, arranger = arranger
            )
            if (releaseDate != null || isMyPick || (collectedCount ?: 0) > 0) {
                MarkRow(releaseDate = releaseDate, isMyPick = isMyPick, collectedCount = collectedCount)
            }
        }
        if (onFavoriteToggle != null) {
            IconButton(onClick = onFavoriteToggle) {
                Icon(
                    imageVector = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (isFavorite) "お気に入り解除" else "お気に入りに追加",
                    tint = if (isFavorite) DS.favorite else DS.ink3
                )
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
private fun CreatorLine(needle: String?, lyricist: String?, composer: String?, arranger: String?) {
    if (needle == null) return
    val text = remember(needle, lyricist, composer, arranger) {
        matchedCreatorText(needle, lyricist, composer, arranger)
    } ?: return
    Text(
        text = rememberHighlighted(text, needle),
        fontSize = 11.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis
    )
}

/** マイマーク行 (リリース日 / 担当♥ / 現地回収✓)。iOS SongRowView.markRow 相当。 */
@Composable
private fun MarkRow(releaseDate: String?, isMyPick: Boolean, collectedCount: Int?) {
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

/**
 * 歌唱者表記から、当たった 1 人を先頭に出した文字列を作る (iOS `SongRowView.performerText` 相当)。
 *
 * 「315 ALLSTARS（天ヶ瀬冬馬、…50 人…）」をそのまま 1 行に出すと、当たった名前は右端で切れて
 * 見えない。当たった 1 人だけでは規模が分からないので「ほか N 人」を添える。
 *
 * iOS は歌唱アイドルを構造化して持つ (performerIdols) が、Android の SongWithArtists は
 * 表記文字列しか持たないので、ここで連名を割る。当たる名前が無ければ null (表記のまま出す)。
 */
private fun matchedPerformerText(label: String, needle: String): String? {
    val names = performerNames(label)
    val matched = names.firstOrNull { TextSearch.matches(it, needle) } ?: return null
    val others = names.size - 1
    return if (others > 0) "$matched ほか${others}人" else matched
}

/**
 * 連名表記から歌唱者名を取り出す。「ユニット名（A、B、C）」はカッコの中が歌唱者
 * (「315 STARS(フィジカルVer.)（…）」のようにユニット名側にも半角カッコが入るので、
 * 全角カッコの最後の開きから後ろを見る)。
 *
 * 区切りは読点だけにする。「・」は「高垣楓・川島瑞樹」のように区切りでもあるが
 * 「キャシー・グラハム」「メロウ・イエロー」のように名前の一部でもあり、割ると人名が
 * 半分になる。割れなかった表記は 1 件として扱い、そのまま色を敷く。
 */
private fun performerNames(label: String): List<String> {
    val open = label.lastIndexOf('（')
    val body = if (open >= 0) label.substring(open + 1).removeSuffix("）") else label
    return body.split('、', '，', ',').map { it.trim() }.filter { it.isNotEmpty() }
}

/** 一致した役割と名前。複数の役割で当たったらまとめて出す。 */
private fun matchedCreatorText(
    needle: String,
    lyricist: String?,
    composer: String?,
    arranger: String?
): String? =
    listOf("作詞" to lyricist, "作曲" to composer, "編曲" to arranger)
        .mapNotNull { (role, name) ->
            if (name != null && TextSearch.matches(name, needle)) "$role $name" else null
        }
        .takeIf { it.isNotEmpty() }
        ?.joinToString(" / ")
