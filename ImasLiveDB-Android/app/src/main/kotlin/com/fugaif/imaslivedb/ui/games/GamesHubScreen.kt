package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.games.GameRecord
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * クイズ・ゲームのハブ。プロデュース → 「ゲーム」から遷移。
 * イントロドン／アイドル当て／ソロ曲／メンバーカラー合わせを束ねる。iOS GamesHubView の移植。
 */
private data class GameEntry(
    val kind: GameKind,
    val icon: ImageVector,
    val title: String,
    val blurb: String
)

private val entries = listOf(
    GameEntry(GameKind.introDon, Icons.Filled.MusicNote, "イントロドン", "イントロを聴いて曲名を当てる"),
    GameEntry(GameKind.idolQuiz, Icons.Filled.PersonSearch, "アイドル当てクイズ", "プロフィールから4択で誰かを当てる"),
    GameEntry(GameKind.songSingerQuiz, Icons.Filled.MusicNote, "ソロ曲クイズ", "ソロ曲を歌うアイドルを4択で当てる"),
    GameEntry(GameKind.colorMatch, Icons.Filled.Palette, "メンバーカラー合わせ", "似た色のメンバーを正しいカラーに紐づける")
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GamesHubScreen(
    onBack: () -> Unit,
    onNavigateToIntroDon: () -> Unit,
    onNavigateToColorMatch: () -> Unit,
    onNavigateToIdolQuizSetup: () -> Unit,
    onNavigateToSongQuizSetup: () -> Unit
) {
    val context = LocalContext.current
    val store = AppModule.from(context).gameProgressStore
    val records by store.records.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("クイズ・ゲーム", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text("ゲーム", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Text(
                    "${entries.size}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3,
                    modifier = Modifier.padding(start = 8.dp)
                )
            }
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(entries, key = { it.kind.name }) { entry ->
                    GameCard(
                        entry = entry,
                        record = records[entry.kind] ?: GameRecord()
                    ) {
                        when (entry.kind) {
                            GameKind.introDon -> onNavigateToIntroDon()
                            GameKind.idolQuiz -> onNavigateToIdolQuizSetup()
                            GameKind.songSingerQuiz -> onNavigateToSongQuizSetup()
                            GameKind.colorMatch -> onNavigateToColorMatch()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GameCard(entry: GameEntry, record: GameRecord, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .heightIn(min = 150.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(DS.fill),
            contentAlignment = Alignment.Center
        ) { Icon(entry.icon, null, tint = DS.ink, modifier = Modifier.size(22.dp)) }
        Column {
            Text(
                entry.title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(entry.blurb, fontSize = 12.sp, color = DS.ink3, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.weight(1f))
        ScoreLine(entry.kind, record)
    }
}

@Composable
private fun ScoreLine(kind: GameKind, rec: GameRecord) {
    if (rec.hasPlayed) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Star, null, tint = DS.favorite, modifier = Modifier.size(10.dp))
            Text(
                bestLabel(kind, rec), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                modifier = Modifier.padding(start = 5.dp).weight(1f)
            )
            Text("${rec.playCount}回", fontSize = 12.sp, color = DS.ink3)
        }
    } else {
        Text("未プレイ", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
    }
}

/** 最高記録の表示文字列。色合わせは正答率%、クイズ系は獲得ポイント。 */
private fun bestLabel(kind: GameKind, rec: GameRecord): String {
    if (rec.bestOutOf <= 0) return "—"
    if (kind.scoreIsPercent) {
        val pct = Math.round((rec.bestScore.toDouble() / rec.bestOutOf) * 100)
        return "最高 ${pct}%"
    }
    return "最高 ${rec.bestScore}pt"
}
