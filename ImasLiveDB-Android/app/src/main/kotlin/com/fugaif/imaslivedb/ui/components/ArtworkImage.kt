package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.player.AudioPreviewManager

/**
 * Artwork image composable with optional audio preview playback on tap.
 * Shows a music note placeholder when no image URL is provided.
 * Mirrors iOS ArtworkImageView.
 *
 * @param url       URL of the artwork image (nullable)
 * @param size      Width and height of the square image
 * @param previewUrl If non-null, tapping triggers preview playback via [AudioPreviewManager]
 * @param songTitle  Title used to match the currently playing track
 */
@Composable
fun ArtworkImage(
    url: String?,
    size: Dp = 50.dp,
    previewUrl: String? = null,
    songTitle: String? = null,
    modifier: Modifier = Modifier
) {
    val cornerRadius = size * 0.15f
    val shape = RoundedCornerShape(cornerRadius)

    val playbackState by AudioPreviewManager.playbackState.collectAsState()
    val isCurrentlyPlaying = songTitle != null
        && playbackState.isPlaying
        && playbackState.nowPlayingTitle == songTitle

    Box(
        modifier = modifier
            .size(size)
            .clip(shape)
            .then(
                if (previewUrl != null && songTitle != null) {
                    Modifier.clickable {
                        AudioPreviewManager.togglePreview(previewUrl, songTitle)
                    }
                } else Modifier
            ),
        contentAlignment = Alignment.Center
    ) {
        if (url != null) {
            SubcomposeAsyncImage(
                model = url,
                contentDescription = songTitle,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size),
                loading = { ArtworkPlaceholder(size) },
                error = { ArtworkPlaceholder(size) }
            )
        } else {
            ArtworkPlaceholder(size)
        }

        // Preview overlay
        if (previewUrl != null) {
            if (isCurrentlyPlaying) {
                Box(
                    modifier = Modifier
                        .size(size)
                        .background(Color.Black.copy(alpha = 0.4f))
                )
            }
            Icon(
                imageVector = if (isCurrentlyPlaying) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                contentDescription = if (isCurrentlyPlaying) "停止" else "プレビュー再生",
                tint = Color.White,
                modifier = Modifier.size(size * 0.3f)
            )
        }
    }
}

@Composable
private fun ArtworkPlaceholder(size: Dp) {
    Box(
        modifier = Modifier
            .size(size)
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Filled.MusicNote,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(size * 0.4f)
        )
    }
}
