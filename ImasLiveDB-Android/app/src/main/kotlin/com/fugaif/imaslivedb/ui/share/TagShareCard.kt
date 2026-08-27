package com.fugaif.imaslivedb.ui.share

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.BrandPalette
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor

// =============================================================================
// 機能 2: タグ付与シェアカード
// タグ付与完了時に「『曲名』にタグを付けました！」のカードを生成する。
// iOS ImasLiveDB/Views/Share/TagShareCard.swift の移植。
// =============================================================================

/** タグ付与シェアの内容。タグ適用完了時に組み立てる。 */
@Immutable
data class TagShareContext(
    val songTitle: String,
    val artistNames: String?,
    /** 今回付けたタグ (カードに乗せるのは先頭 6 個まで)。 */
    val tags: List<CommunityApi.CommunityTag>,
    /** メンバーカラー seed (曲のブランドカラー → 先頭タグ色 の順でフォールバック)。 */
    val seed: String?,
    /** 曲の songs.artwork_url。表示時に非同期ロードしてカードに焼き込む。 */
    val artworkUrl: String?
)

/**
 * タグ付与カード本体。
 * 上にジャケ写フルブリード / 下を near-black のソリッドパネルにした編集レイアウト。
 * パネルに見出しラベル + 曲名 (明朝・主役) + 線画タグチップを白基調で置く。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TagShareCard(context: TagShareContext, artwork: ImageBitmap?, size: ShareCardSize) {
    val palette = rememberShareCardPalette(context.seed)

    PhotoShareScaffold(artwork = artwork, palette = palette, size = size) {
        ShareEyebrow(
            text = "タグを追加しました！",
            accent = palette.accent,
            ink = ShareInk.ink.copy(alpha = 0.82f)
        )

        // 曲名を主役に (明朝で上品・編集的)。
        Spacer(Modifier.height(12.dp))
        Text(
            context.songTitle,
            fontSize = 40.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Serif,
            color = ShareInk.ink,
            lineHeight = 46.sp,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis
        )

        if (!context.artistNames.isNullOrEmpty()) {
            Spacer(Modifier.height(8.dp))
            Text(
                context.artistNames,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = ShareInk.ink2,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        // 付けたタグを線画チップで最小限に (最大 6 個)。
        Spacer(Modifier.height(22.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            context.tags.take(6).forEach { tag -> TagChip(tag, palette.accent) }
        }
    }
}

/** タグチップ: 塗らず細い罫線 + 小ドット (線画基調)。色はタグ固有色 → accent。 */
@Composable
private fun TagChip(tag: CommunityApi.CommunityTag, accent: Color) {
    val dot = tag.color?.let { hexToColor(it) } ?: accent
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.28f), CircleShape)
            .padding(horizontal = 13.dp, vertical = 7.dp)
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(dot))
        Spacer(Modifier.width(7.dp))
        Text(
            tag.name,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.92f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * タグ付与完了後に出す「完了 + シェア」ペイン。
 *
 * ピッカーのシートを閉じて別シートを重ねると、シートが 2 枚積み上がって挙動が濁るので、
 * iOS と同じく**ピッカーの中身をこれに差し替える**形で使う (シートは 1 枚のまま)。
 *
 * 曲のメタ (タイトル/ジャケ/原唱者) はピッカーが持っていないので、ここで引く。
 * ピッカー側からは「適用できたタグ」だけ渡してもらう。
 */
@Composable
fun TagShareCompletionPane(
    songId: String,
    appliedTags: List<CommunityApi.CommunityTag>,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ctx = LocalContext.current
    var shareContext by remember(songId) { mutableStateOf<TagShareContext?>(null) }

    LaunchedEffect(songId, appliedTags) {
        val module = AppModule.from(ctx)
        val song = module.songRepository.fetchSong(songId)
        val artists = runCatching { module.songRepository.fetchSongArtists(songId, role = "original") }
            .getOrDefault(emptyList())
        shareContext = TagShareContext(
            songTitle = song?.title ?: "",
            artistNames = artists.take(4).joinToString("・") { it.name }.ifEmpty { null },
            tags = appliedTags,
            // 曲のブランドカラーを第一シードに。無ければ先頭タグの色へ落ちる。
            seed = BrandPalette.hex(song?.brandId) ?: appliedTags.firstOrNull()?.color,
            artworkUrl = song?.artworkUrl
        )
    }

    val current = shareContext
    val artwork = rememberShareArtwork(current?.artworkUrl)

    Column(
        modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = DS.success, modifier = Modifier.size(40.dp))
        Text("タグを付けました！", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text("せっかくなのでカードでシェアしませんか？", fontSize = 13.sp, color = DS.ink2)

        if (current != null) {
            ShareCardActionPane(
                // 曲メタが揃うまで、そして焼き込むジャケ写が届くまではシェアを止める
                // (ジャケ写が抜けたカードが焼かれるのを防ぐ)。
                isPreparingCard = artwork.isPreparing,
                fileNamePrefix = "tag"
            ) { size ->
                TagShareCard(context = current, artwork = artwork.image, size = size)
            }
        } else {
            ShareCardPlaceholder()
        }

        Text(
            "閉じる",
            fontSize = 15.sp,
            color = DS.ink2,
            modifier = Modifier.clickable(onClick = onClose).padding(8.dp)
        )
    }
}

/** 角丸のプレースホルダ (曲メタ待ちの間だけ出す)。 */
@Composable
private fun ShareCardPlaceholder() {
    Box(Modifier.fillMaxWidth().height(240.dp).clip(RoundedCornerShape(18.dp)).background(DS.surface))
}
