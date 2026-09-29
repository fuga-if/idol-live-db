package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.games.QuizSuspended
import com.fugaif.imaslivedb.data.games.emptyGameRecord
import com.fugaif.imaslivedb.data.games.hasPlayed
import com.fugaif.imaslivedb.data.games.totalPlays
import com.fugaif.imaslivedb.data.games.totalPoints
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasListContainer
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.GameRecord
import uniffi.imas_core.QuizGrade
import uniffi.imas_core.gameProgressBestRatePercent
import uniffi.imas_core.quizGradeForRate

/**
 * クイズ・ゲームのハブ。プロデュース → 「ゲーム」から遷移。iOS GamesHubView の移植。
 * アイドル当て／ソロ曲／セトリ当て／イントロドン／メンバーカラー合わせを束ねる。
 *
 * 一覧そのものはアプリ本体と同じ画面のまま、上にだけ「QUIZ STAGE」のチケット
 * (ゲーム画面と同じ暗いステージ色) を置いて、ここから先が会場だと分かるようにする。
 */
private data class GameEntry(
    val kind: GameKind,
    val icon: ImageVector,
    val title: String,
    val blurb: String
)

/** 並びは iOS と同じ (Android に無い歌詞クイズを除く)。 */
private val entries = listOf(
    GameEntry(GameKind.idolQuiz, Icons.Filled.PersonSearch, "アイドル当て", "プロフィールから当てる"),
    GameEntry(GameKind.songSingerQuiz, Icons.Filled.Mic, "ソロ曲クイズ", "曲名から歌っているアイドルを"),
    GameEntry(GameKind.setlistQuiz, Icons.Filled.FormatListNumbered, "セトリ当て", "セトリの空欄に入る曲を当てる"),
    GameEntry(GameKind.introDon, Icons.AutoMirrored.Filled.QueueMusic, "イントロドン", "イントロを聴いて曲を当てる"),
    GameEntry(GameKind.colorMatch, Icons.Filled.PersonSearch, "メンバーカラー合わせ", "名前からイメージカラーを")
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GamesHubScreen(
    onBack: (() -> Unit)?,
    onNavigateToIntroDon: () -> Unit,
    onNavigateToColorMatch: () -> Unit,
    onNavigateToIdolQuizSetup: () -> Unit,
    onNavigateToSongQuizSetup: () -> Unit,
    onNavigateToSetlistQuizSetup: () -> Unit,
    /** 「つづきから」。途中でやめたゲームへ直接入る。 */
    onResume: (GameKind) -> Unit = {}
) {
    val context = LocalContext.current
    val store = AppModule.from(context).gameProgressStore
    val records by store.records.collectAsStateWithLifecycle()
    // 連続日数は streak を購読して引き直す (購読しないと結果を記録した後も古いまま)。
    val streakState by store.streak.collectAsStateWithLifecycle()
    val displayStreak = remember(streakState) { store.displayStreak }
    // 途中でやめたクイズ (1 問答えるたびに保存される)。
    val suspended by AppModule.from(context).quizResumeStore.sessions.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("クイズ・ゲーム", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    // サイドバーの根として開いたときは戻る先が無いので出さない。
                    onBack?.let { back ->
                        IconButton(onClick = back) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(DS.bg)
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
        ) {
            StageTicket(
                records = records,
                displayStreak = displayStreak,
                resume = suspended.values.filter { s -> entries.any { it.kind == s.kind } }.maxByOrNull { it.savedAt },
                onResume = onResume
            )
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ImasSectionHeader(title = "ゲーム", count = "${entries.size}")
                ImasListContainer {
                    entries.forEachIndexed { i, entry ->
                        if (i > 0) {
                            Box(Modifier.fillMaxWidth().background(DS.surface).padding(start = 68.dp)) {
                                Box(Modifier.fillMaxWidth().height(0.5.dp).background(DS.sep))
                            }
                        }
                        GameRow(entry, records[entry.kind] ?: emptyGameRecord(), suspended[entry.kind]) {
                            when (entry.kind) {
                                GameKind.introDon -> onNavigateToIntroDon()
                                // アイドル当て・ソロ曲・セトリ当てはブランド絞り込み設定画面を先に挟む。
                                GameKind.idolQuiz -> onNavigateToIdolQuizSetup()
                                GameKind.songSingerQuiz -> onNavigateToSongQuizSetup()
                                GameKind.colorMatch -> onNavigateToColorMatch()
                                GameKind.setlistQuiz -> onNavigateToSetlistQuizSetup()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - QUIZ STAGE チケット

/** 自己ベストの正答率をグレードにしたもの (未プレイは null)。閾値はコア。 */
private fun bestGrade(rec: GameRecord): QuizGrade? =
    gameProgressBestRatePercent(rec)?.let { quizGradeForRate(it.coerceAtLeast(0).toUInt()) }

@Composable
private fun StageTicket(
    records: Map<GameKind, GameRecord>,
    displayStreak: Int,
    resume: QuizSuspended?,
    onResume: (GameKind) -> Unit
) {
    // 全ゲームを通した最高グレード (自己ベストの正答率がいちばん高いもの)。
    val topGrade = entries.mapNotNull { e -> records[e.kind]?.let { gameProgressBestRatePercent(it) } }.maxOrNull()
        ?.let { quizGradeForRate(it.coerceAtLeast(0).toUInt()) }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(QS.bg)
    ) {
        // アプリアイコンの帯 (ペンライトの色)。
        Row(Modifier.fillMaxWidth().height(6.dp)) {
            QS.penlights.forEach { Box(Modifier.weight(1f).height(6.dp).background(it)) }
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(QS.ink),
                    contentAlignment = Alignment.Center
                ) { Text("@", style = QS.text(14, FontWeight.Black), color = QS.bg) }
                Text("QUIZ STAGE", style = QS.mono(11, 1.3f), color = QS.dim)
            }
            Row(verticalAlignment = Alignment.Bottom) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    modifier = Modifier.semantics { contentDescription = "累計ポイント ${records.totalPoints}" }
                ) {
                    Text("累計ポイント", style = QS.text(12, FontWeight.Bold), color = QS.dim)
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("%,d".format(records.totalPoints), style = QS.num(56), color = QS.ink)
                        Text("pt", style = QS.text(14, FontWeight.Bold), color = QS.dim, modifier = Modifier.padding(bottom = 8.dp))
                    }
                }
                Spacer(Modifier.weight(1f).width(8.dp))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("プレイ", style = QS.text(12), color = QS.dim)
                        Text("${records.totalPlays}", style = QS.text(12, FontWeight.Bold), color = QS.ink)
                        Text("回", style = QS.text(12), color = QS.dim)
                    }
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("最高グレード", style = QS.text(12), color = QS.dim, modifier = Modifier.padding(bottom = 2.dp))
                        Text(topGrade?.label ?: "—", style = QS.num(18), color = QS.ink)
                    }
                }
            }
        }
        // 切り取り線 (両端は一覧の背景色で欠ける)。
        QuizTicketNotch(cut = DS.bg, line = QS.line, inset = 6.dp)
        // 途中でやめたクイズがあれば「つづきから」、無ければ連続プレイ日数。
        if (resume != null) ResumeRow(resume, onResume) else StreakRow(displayStreak)
    }
}

/** チケットの下半分 (いちばん最近中断したクイズの「つづきから」)。 */
@Composable
private fun ResumeRow(s: QuizSuspended, onResume: (GameKind) -> Unit) {
    val title = entries.firstOrNull { it.kind == s.kind }?.title.orEmpty()
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 68.dp).padding(start = 20.dp, end = 12.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
            Text("つづきから", style = QS.text(11), color = QS.dim)
            QSFitText(
                "$title · " + "Q.%02d / %d".format(s.currentNumber, s.total),
                QS.text(15, FontWeight.Bold), QS.ink, minScale = 0.8f
            )
        }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .height(44.dp)
                .clip(CircleShape)
                .background(QS.ink)
                .quizPress { onResume(s.kind) }
                .padding(horizontal = 20.dp)
                .semantics { contentDescription = "$title を再開" }
        ) {
            Text("再開", style = QS.text(15, FontWeight.Bold), color = QS.bg)
        }
    }
}

/** チケットの下半分 (連続プレイ日数)。 */
@Composable
private fun StreakRow(displayStreak: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 68.dp).padding(start = 20.dp, end = 12.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("連続プレイ", style = QS.text(11), color = QS.dim)
            QSFitText(
                if (displayStreak > 0) "$displayStreak 日つづけて遊んでいます" else "今日の 1 ゲームで連続記録が始まります",
                QS.text(15, FontWeight.Bold), QS.ink, minScale = 0.8f
            )
        }
    }
}

// MARK: - ゲーム一覧

@Composable
private fun GameRow(entry: GameEntry, rec: GameRecord, suspended: QuizSuspended?, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        GameIcon(entry)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
            Text(entry.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(entry.blurb, fontSize = 13.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            val grade = if (rec.hasPlayed) bestGrade(rec) else null
            if (suspended != null) {
                Text("プレイ中", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                Text("Q.%02d".format(suspended.currentNumber), fontSize = 11.sp, color = DS.ink3)
            } else if (grade != null) {
                Text(grade.label, style = QS.num(22), color = DS.ink)
                Text(bestLabel(entry.kind, rec), fontSize = 11.sp, color = DS.ink3)
            } else {
                Text("未プレイ", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(20.dp))
    }
}

/** 暗いステージ色のアイコン。メンバーカラーだけ色の 2×2 にする。 */
@Composable
private fun GameIcon(entry: GameEntry) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(QS.bg)
    ) {
        if (entry.kind == GameKind.colorMatch) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(9.dp)) {
                listOf(listOf(0, 4), listOf(2, 3)).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        row.forEach { i ->
                            Box(Modifier.weight(1f).height(9.dp).clip(RoundedCornerShape(4.dp)).background(QS.penlight(i)))
                        }
                    }
                }
            }
        } else {
            Icon(entry.icon, contentDescription = null, tint = QS.ink, modifier = Modifier.size(22.dp))
        }
    }
}

/**
 * 最高記録の表示文字列。色合わせは正答率%、クイズ系は獲得ポイント。
 * 正答率の算出 (と「まだ記録が無い」の判定) はコアが持つので、ここでは文言に落とすだけ。
 */
private fun bestLabel(kind: GameKind, rec: GameRecord): String {
    if (kind.scoreIsPercent) {
        val pct = gameProgressBestRatePercent(rec) ?: return "—"
        return "最高 $pct%"
    }
    if (rec.bestOutOf <= 0) return "—"
    return "最高 ${rec.bestScore} pt"
}
