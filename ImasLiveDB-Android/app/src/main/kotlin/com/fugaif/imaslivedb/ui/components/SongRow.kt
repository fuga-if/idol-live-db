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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 楽曲一覧の行。iOS SongRowView 構成: ImasLeadBar(ブランド) + ImasArtwork(プレビュー対応) +
 * 曲名(+タグ票数バッジ) + 歌唱者/ユニット + マイマーク行(担当/現地回収) + お気に入りトグル。
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
        ImasLeadBar(brand = brandId, height = 44.dp)
        ArtworkImage(url = artworkUrl, size = 44.dp, previewUrl = previewUrl, songTitle = title)
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = title,
                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (tagVoteCount != null) {
                    TagVoteBadge(count = tagVoteCount)
                }
            }
            val sub = artistNames.ifEmpty { unitName ?: "" }
            if (sub.isNotEmpty()) {
                Text(text = sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
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
