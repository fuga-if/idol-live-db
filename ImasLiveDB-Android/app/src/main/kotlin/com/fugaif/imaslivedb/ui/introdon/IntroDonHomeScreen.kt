package com.fugaif.imaslivedb.ui.introdon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * イントロドンのホーム画面。iOS IntroDonHomeView の移植。
 *
 * iOS 版は Apple Music (MusicKit) のフル再生 (実イントロを頭出し) を使えるが、Android には
 * 同等のカタログストリーミング手段が無いため、常に楽曲の `preview_url` (30秒プレビュー) で
 * イントロを再現する。フル再生/プレビュー切替 UI は Android では意味を持たないため省略し、
 * 代わりにその旨を伝える案内カードを出す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IntroDonHomeScreen(onBack: () -> Unit, onNavigateToSetup: () -> Unit = {}) {
    val accent = introDonAccent()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("イントロドン", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg).verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            heroCard(accent)
            IntroDonActionButton(title = "ゲームをはじめる") { onNavigateToSetup() }
            previewNoticeCard()
        }
    }
}

@Composable
private fun heroCard(accent: androidx.compose.ui.graphics.Color) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(DS.surface).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                modifier = Modifier.size(64.dp).clip(RoundedCornerShape(16.dp)).background(accent.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Filled.MusicNote, null, tint = accent, modifier = Modifier.size(28.dp)) }
            Column {
                Text("INTRO DON", fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp, color = DS.ink3)
                Text("イントロドン", fontSize = 26.sp, fontWeight = FontWeight.Black, color = DS.ink)
            }
        }
        Text(
            "曲のイントロを聴いて\n曲名をいち早く当てよう",
            fontSize = 14.sp, color = DS.ink2, lineHeight = 20.sp
        )
    }
}

@Composable
private fun previewNoticeCard() {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.fill).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Filled.Info, null, tint = DS.ink2, modifier = Modifier.size(18.dp))
        Column {
            Text("プレビュー再生で出題します", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            Text(
                "各曲の30秒プレビューからイントロ部分を再生します。プレビューを持たない曲は出題対象外です。",
                fontSize = 12.sp, color = DS.ink3
            )
        }
    }
}
