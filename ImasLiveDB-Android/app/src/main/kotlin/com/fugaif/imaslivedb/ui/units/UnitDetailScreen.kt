package com.fugaif.imaslivedb.ui.units

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/** ユニット詳細。iOS 構造: hero(ユニット名) → メンバー(アバターグリッド) → 楽曲。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnitDetailScreen(
    unitId: String,
    onNavigateBack: () -> Unit,
    onNavigateToIdolDetail: (String) -> Unit,
    onNavigateToSongDetail: (String) -> Unit,
    viewModel: UnitDetailViewModel = viewModel(
        factory = UnitDetailViewModel.Factory(
            LocalContext.current.applicationContext as android.app.Application, unitId
        )
    )
) {
    val state by viewModel.uiState.collectAsState()
    val unit = state.unit
    val t = ImasTheme.derive(null, unit?.brandId, dark = true)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(unit?.displayName ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading || unit == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                Hero(unit, t)
                if (state.members.isNotEmpty()) MembersSection(state, onNavigateToIdolDetail)
                if (state.songs.isNotEmpty()) {
                    ImasSectionHeader("楽曲", count = "${state.songs.size}")
                    state.songs.forEach { song ->
                        SongRow(
                            title = song.title, artistNames = song.singerLabel ?: "", unitName = song.unitName,
                            artworkUrl = song.artworkUrl, previewUrl = song.previewUrl, brandId = song.brandId,
                            modifier = Modifier.clickable { onNavigateToSongDetail(song.id) }
                                .padding(horizontal = 16.dp)
                        )
                    }
                }
                Box(Modifier.size(24.dp))
            }
        }
    }
}

@Composable
private fun Hero(unit: ImasUnit, t: ImasTheme) {
    Column(
        modifier = Modifier.fillMaxWidth().background(t.heroSurface).padding(vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(unit.displayName, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink, textAlign = TextAlign.Center)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MembersSection(state: UnitDetailUiState, onIdol: (String) -> Unit) {
    Column {
        ImasSectionHeader("メンバー", count = "${state.members.size}")
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            state.members.forEach { idol ->
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.width(64.dp).clickable { onIdol(idol.id) }
                ) {
                    ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 52.dp)
                    Text(idol.name, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = DS.ink2,
                        textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 6.dp))
                }
            }
        }
    }
}
