package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
 * 曲名 + 歌唱者 / ユニット。
 */
@Composable
fun SongRow(
    title: String,
    artistNames: String,
    unitName: String?,
    artworkUrl: String? = null,
    previewUrl: String? = null,
    brandId: String? = null,
    modifier: Modifier = Modifier
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = modifier.fillMaxWidth().padding(vertical = 4.dp)
    ) {
        ImasLeadBar(brand = brandId, height = 40.dp)
        ArtworkImage(url = artworkUrl, size = 44.dp, previewUrl = previewUrl, songTitle = title)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            val sub = artistNames.ifEmpty { unitName ?: "" }
            if (sub.isNotEmpty()) {
                Text(text = sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
