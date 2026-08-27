package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.GradientHeader
import com.fugaif.imaslivedb.ui.components.ImasLabeledRow
import com.fugaif.imaslivedb.ui.filtered.ShowFilterKind
import com.fugaif.imaslivedb.ui.share.SetlistCommentComposeSheet
import com.fugaif.imaslivedb.ui.theme.BrandPalette
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.PerformerChip

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SetlistScreen(
    showId: String,
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    /**
     * 会場/日付の行から「同じ会場・同じ日の公演一覧」へ (kind, value は
     * [com.fugaif.imaslivedb.ui.filtered.ShowFilterKind] の定義に従う)。
     */
    onFilteredShowsClick: (String, String) -> Unit = { _, _ -> },
    viewModel: SetlistViewModel = viewModel(key = showId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    // 会場名は「公演日時点の名前」で出す (改名前の公演は当時名)。解決には会場マスタが要るが、
    // この画面の担当範囲外である ViewModel は変えないのでここで 1 回だけ読む
    // (244 施設ぶんの小さなマスタで、公演ごとの引き直しはしない)。
    var venues by remember { mutableStateOf(VenueDirectory.EMPTY) }
    LaunchedEffect(Unit) { venues = AppModule.from(context).eventRepository.fetchVenueDirectory() }

    LaunchedEffect(showId) { viewModel.load(context, showId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.show?.name ?: "") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { innerPadding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            val isCharacterLive = uiState.show?.isCharacterLive ?: false
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                item {
                    Box(modifier = Modifier.fillMaxWidth()) {
                        GradientHeader(color = brandColor(uiState.brandId), height = 88.dp)
                        Column(modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 40.dp, bottom = 8.dp)) {
                            Text(
                                uiState.show?.name ?: "",
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                color = DS.ink
                            )
                            uiState.show?.date?.let { d ->
                                Text(d, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
                            }
                        }
                    }
                }
                uiState.show?.let { show ->
                    item(key = "venue_date") {
                        VenueDateCard(
                            show = show,
                            venues = venues,
                            brandId = uiState.brandId,
                            onFilteredShowsClick = onFilteredShowsClick
                        )
                    }
                }
                uiState.sections.forEach { section ->
                    stickyHeader(key = section.sectionName) {
                        Surface(
                            color = DS.surface2,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = section.sectionName,
                                style = MaterialTheme.typography.labelLarge,
                                color = DS.ink2,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                            )
                        }
                    }

                    section.items.forEachIndexed { index, item ->
                        item(key = item.id) {
                            val performers = uiState.performersByItemId[item.id] ?: emptyList()
                            SetlistItemRow(
                                item = item,
                                displayNumber = index + 1,
                                performers = performers,
                                isCharacterLive = isCharacterLive,
                                showName = uiState.show?.name,
                                showDate = uiState.show?.date,
                                // 感想カードの差し色。公演のブランドカラーを hex で渡す
                                // (ブランド ID のままだと色エンジンがニュートラルへ落ちる)。
                                seed = BrandPalette.hex(uiState.brandId),
                                onSongClick = { onSongClick(item.songId) },
                                onIdolClick = { idolId -> onIdolClick(idolId) }
                            )
                            HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                        }
                    }
                }
            }
        }
    }
}

/**
 * 会場 / 日付のカード。どちらも「同じ条件の公演」への入口になる。
 *
 * 会場は ID で持つ (表記ゆれで同じ会場が分断されないように) ので、ID を持たない古い公演では
 * 押せない普通の行に落とす — 生の会場文字列でも引けはするが、押した先が表記ゆれで
 * 分断された一部だけになり、「この会場での公演」という約束を守れないため。
 */
@Composable
private fun VenueDateCard(
    show: Show,
    venues: VenueDirectory,
    brandId: String?,
    onFilteredShowsClick: (String, String) -> Unit
) {
    Column(
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth()
            .clip(RoundedCornerShape(14.dp)).background(DS.surface)
    ) {
        val venueId = show.venueId?.takeIf { it.isNotEmpty() }
        val venueLabel = venues.displayName(show) ?: show.venue
        if (!venueLabel.isNullOrEmpty()) {
            ImasLabeledRow(
                key = "会場", value = venueLabel, brand = brandId,
                tappable = venueId != null,
                onClick = venueId?.let { id -> { onFilteredShowsClick(ShowFilterKind.VENUE, id) } }
            )
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
        if (show.date.isNotEmpty()) {
            ImasLabeledRow(
                key = "日付", value = show.date, brand = brandId, tappable = true,
                onClick = { onFilteredShowsClick(ShowFilterKind.DATE, show.date) }
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun SetlistItemRow(
    item: SetlistRow,
    displayNumber: Int,
    performers: List<PerformerRow>,
    isCharacterLive: Boolean,
    showName: String?,
    showDate: String?,
    seed: String?,
    onSongClick: () -> Unit,
    onIdolClick: (String) -> Unit
) {
    // 長押し → 感想カード (曲名 + コメントのシェア画像) を作る。
    // 曲名タップは従来どおり曲詳細なので、行そのものの長押しに逃がしている。
    var showCommentShare by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                // 空タップにリップルだけ出て何も起きないのを避けるため、
                // 行のどこを押しても曲名タップと同じ挙動にしておく。
                onClick = onSongClick,
                onLongClick = { showCommentShare = true }
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        // Position number
        Text(
            text = "$displayNumber",
            style = MaterialTheme.typography.bodySmall,
            color = DS.ink2.copy(alpha = 0.6f),
            modifier = Modifier
                .width(28.dp)
                .padding(top = 2.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.End
        )

        // Artwork with preview
        ArtworkImage(
            url = item.artworkUrl,
            size = 44.dp,
            previewUrl = item.previewUrl,
            songTitle = item.songTitle
        )

        // Content column
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Song title — tap navigates to SongDetail
            Text(
                text = item.songTitle,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clickable(onClick = onSongClick)
            )

            // Unit name capsule
            if (item.unitName != null) {
                Surface(
                    shape = RoundedCornerShape(50),
                    color = DS.sys.copy(alpha = 0.1f)
                ) {
                    Text(
                        text = item.unitName,
                        style = MaterialTheme.typography.labelSmall,
                        color = DS.sys,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }

            // Performer chips in FlowRow
            if (performers.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    performers.forEach { performer ->
                        PerformerChip(
                            name = performer.name,
                            idolName = performer.idolName,
                            idolColorHex = performer.idolColor,
                            isCharacterLive = isCharacterLive,
                            modifier = Modifier.clickable(enabled = performer.idolId != null) {
                                performer.idolId?.let { onIdolClick(it) }
                            }
                        )
                    }
                }
            }

            // Notes
            if (item.notes != null) {
                Text(
                    text = item.notes,
                    style = MaterialTheme.typography.bodySmall,
                    color = DS.ink2
                )
            }
        }
    }

    if (showCommentShare) {
        SetlistCommentComposeSheet(
            songTitle = item.songTitle,
            showName = showName,
            showDate = showDate,
            seed = seed,
            artworkUrl = item.artworkUrl,
            onDismiss = { showCommentShare = false }
        )
    }
}
