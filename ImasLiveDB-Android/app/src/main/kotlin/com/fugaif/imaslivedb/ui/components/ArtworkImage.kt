package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork

/**
 * 曲のジャケ表示 + 試聴 (iOS `ArtworkImageView` と対)。見た目は DS の [ImasArtwork]
 * (画像が無ければ色の面 + 曲名、色も無ければ灰の面 + 音符)。
 * 再生状態の読み出しと切り替えだけここで [AudioPreviewManager] に橋渡しする
 * (DS はアプリのサービスを知らないので、ここが唯一の橋渡し場所)。
 *
 * @param url       ジャケの URL (null 可)
 * @param size      正方形の一辺
 * @param previewUrl 渡すと押して試聴を切り替える ([AudioPreviewManager])
 * @param songTitle  画像が無いときに面に書く曲名。**表示専用** (読み上げにも使う)
 * @param songId     再生中の強調と試聴の切り替えに使う `songs.id`。
 *                   同名で別録音の曲が実在するので、ここを曲名で持つと取り違える
 * @param seed       画像が無いときの面の色 (曲・ブランドのイメージカラー hex)
 * @param brand      画像が無いときの面の色 (ブランド ID)
 */
@Composable
fun ArtworkImage(
    url: String?,
    size: Dp = 50.dp,
    previewUrl: String? = null,
    songTitle: String? = null,
    songId: String? = null,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null
) {
    val playbackState by AudioPreviewManager.playbackState.collectAsState()
    val isCurrentlyPlaying = songId != null && playbackState.isPlaying(songId)
    // 試聴は曲 id が分かるときだけ (id が無いと再生中の強調も切り替えも曲を取り違える)。
    val preview = previewUrl?.takeIf { songId != null }
    ImasArtwork(
        title = songTitle.orEmpty(),
        seed = seed,
        brand = brand,
        size = size,
        imageUrl = url,
        modifier = modifier,
        previewUrl = preview,
        isPreviewing = isCurrentlyPlaying,
        onPreview = {
            if (preview != null && songId != null) AudioPreviewManager.togglePreview(preview, songId)
        }
    )
}
