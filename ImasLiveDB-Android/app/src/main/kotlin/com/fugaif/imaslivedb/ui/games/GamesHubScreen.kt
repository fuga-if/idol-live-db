package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Person
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.games.QuizSuspended
import com.fugaif.imaslivedb.data.games.SortMakerSession
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.data.games.emptyGameRecord
import com.fugaif.imaslivedb.data.games.hasPlayed
import com.fugaif.imaslivedb.data.games.totalPlays
import com.fugaif.imaslivedb.data.games.totalPoints
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasStageColorGridIcon
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePreviewCard
import com.fugaif.imaslivedb.ui.designsystem.ImasStageWordmark
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import uniffi.imas_core.GameRecord
import uniffi.imas_core.QuizGrade
import uniffi.imas_core.gameProgressBestRatePercent
import uniffi.imas_core.quizGradeForRate
import com.fugaif.imaslivedb.ui.theme.QS

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
    onNavigateToSortMakerSetup: (SortMakerSubject) -> Unit,
    onNavigateToTierListSetup: (SortMakerSubject) -> Unit,
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
    val sortMakerSessions by AppModule.from(context).sortMakerStore.sessions.collectAsStateWithLifecycle()
    val tierBoards by AppModule.from(context).tierListStore.boards.collectAsStateWithLifecycle()

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
            verticalArrangement = Arrangement.spacedBy(DS.sp6),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(DS.bg)
                .verticalScroll(rememberScrollState())
                .padding(DS.sp6)
        ) {
            StageTicket(
                records = records,
                displayStreak = displayStreak,
                resume = suspended.values.filter { s -> entries.any { it.kind == s.kind } }.maxByOrNull { it.savedAt },
                onResume = onResume
            )
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                ImasSectionHeader(title = "ゲーム", count = "${entries.size}")
                ImasCardList(style = ImasCardListStyle.PANEL) {
                    entries.forEachIndexed { i, entry ->
                        if (i > 0) ImasRowDivider(inset = HubRowDividerInset)
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
            SortMakerSection(sortMakerSessions, tierBoards, onNavigateToSortMakerSetup, onNavigateToTierListSetup)
        }
    }
}

/** ハブの行の記号幅 (40) に揃えた区切り線の左インセット (iOS `ImasRowDivider(inset: 68)` と同じ値)。 */
private val HubRowDividerInset = 68.dp

// MARK: - ソートメーカー・ティアー表

@Composable
private fun SortMakerSection(
    sessions: Map<SortMakerSubject, SortMakerSession>,
    tierBoards: List<TierListBoard>,
    onOpenSort: (SortMakerSubject) -> Unit,
    onOpenTier: (SortMakerSubject) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasSectionHeader(title = "ソートメーカー・ティアー表")
        ImasCardList(style = ImasCardListStyle.PANEL) {
            val subjects = SortMakerSubject.entries.toList()
            subjects.forEachIndexed { i, subject ->
                if (i > 0) ImasRowDivider(inset = HubRowDividerInset)
                SortMakerRow(subject, sessions[subject]) { onOpenSort(subject) }
            }
            subjects.forEach { subject ->
                ImasRowDivider(inset = HubRowDividerInset)
                TierListRow(subject, tierBoards.count { it.subject == subject }) { onOpenTier(subject) }
            }
        }
    }
}

@Composable
private fun TierListRow(subject: SortMakerSubject, savedCount: Int, onClick: () -> Unit) {
    ImasRow(
        title = subject.tierTitle,
        subtitle = if (savedCount > 0) "保存 ${savedCount}件" else "段に振り分けて1枚の画像に",
        titleLineLimit = 1,
        leading = ImasRowLeading.Icon(Icons.Filled.Layers, tone = ImasIconTileTone.SOLID),
        trailing = ImasRowTrailing.Chevron,
        modifier = Modifier.imasRowPress(onClick = onClick)
    )
}

@Composable
private fun SortMakerRow(subject: SortMakerSubject, saved: SortMakerSession?, onClick: () -> Unit) {
    ImasRow(
        title = subject.title,
        subtitle = sortMakerBlurb(subject, saved),
        titleLineLimit = 1,
        leading = ImasRowLeading.Icon(
            if (subject == SortMakerSubject.SONG) Icons.Filled.MusicNote else Icons.Filled.Person,
            tone = ImasIconTileTone.SOLID
        ),
        trailing = if (saved != null && !saved.isFinished) {
            ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                    Text("${saved.replay().progressPercent}%", style = ImasTextRole.SECTION_LABEL.style, color = DS.ink2)
                    ImasRowChevron()
                }
            }
        } else {
            ImasRowTrailing.Chevron
        },
        modifier = Modifier.imasRowPress(onClick = onClick)
    )
}

private fun sortMakerBlurb(subject: SortMakerSubject, saved: SortMakerSession?): String {
    if (saved != null) {
        if (saved.isFinished) saved.topNames.firstOrNull()?.let { return "前回の1位: $it" }
        if (!saved.isFinished) return "つづきから"
    }
    return if (subject == SortMakerSubject.SONG) "2曲ずつ選んで好きな曲の順位を決める" else "2人ずつ選んで好きなアイドルの順位を決める"
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
    ImasStagePreviewCard {
        // アプリアイコンの帯 (ペンライトの色)。
        Row(Modifier.fillMaxWidth().height(6.dp)) {
            QS.penlights.forEach { Box(Modifier.weight(1f).height(6.dp).background(it)) }
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
            modifier = Modifier.fillMaxWidth().padding(horizontal = DS.sp6, vertical = DS.Space.card)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasStageWordmark(text = "@")
                Text("QUIZ STAGE", style = QS.mono(11, 1.3f), color = QS.dim)
            }
            Row(verticalAlignment = Alignment.Bottom) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(DS.sp1),
                    modifier = Modifier.semantics { contentDescription = "累計ポイント ${records.totalPoints}" }
                ) {
                    Text("累計ポイント", style = QS.text(12, FontWeight.Bold), color = QS.dim)
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(DS.Space.note)) {
                        QSFitText("%,d".format(records.totalPoints), QS.num(56), QS.ink)
                        Text("pt", style = QS.text(14, FontWeight.Bold), color = QS.dim, modifier = Modifier.padding(bottom = DS.Space.gap))
                    }
                }
                Spacer(Modifier.weight(1f).width(DS.Space.gap))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text("プレイ", style = QS.text(12), color = QS.dim)
                        Text("${records.totalPlays}", style = QS.text(12, FontWeight.Bold), color = QS.ink)
                        Text("回", style = QS.text(12), color = QS.dim)
                    }
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text("最高グレード", style = QS.text(12), color = QS.dim, modifier = Modifier.padding(bottom = DS.sp1))
                        Text(topGrade?.label ?: "—", style = QS.num(18), color = QS.ink)
                    }
                }
            }
        }
        // 切り取り線 (両端は一覧の背景色で欠ける)。
        QuizTicketNotch(cut = DS.bg, line = QS.line, inset = DS.Space.note)
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
        horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
        modifier = Modifier.fillMaxWidth().heightIn(min = 68.dp).padding(start = DS.sp6, end = DS.Space.rowGap)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp1), modifier = Modifier.weight(1f)) {
            Text("つづきから", style = QS.text(11), color = QS.dim)
            QSFitText(
                "$title · " + "Q.%02d / %d".format(s.currentNumber, s.total),
                QS.text(15, FontWeight.Bold), QS.ink, minScale = 0.8f
            )
        }
        // 「再開」ボタン: ステージ固定色の小さい版 (iOS `QuizStagePrimaryButton(compact: true)` と同じ部品)。
        QuizStagePrimaryButton(
            title = "再開",
            compact = true,
            accessibilityLabel = "$title を再開",
            onClick = { onResume(s.kind) }
        )
    }
}

/** チケットの下半分 (連続プレイ日数)。 */
@Composable
private fun StreakRow(displayStreak: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 68.dp).padding(start = DS.sp6, end = DS.Space.rowGap)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
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
    val grade = if (rec.hasPlayed) bestGrade(rec) else null
    ImasRow(
        title = entry.title,
        subtitle = entry.blurb,
        titleLineLimit = 1,
        // メンバーカラー合わせだけ既存の色の 2×2 格子 (ImasStageColorGridIcon)。他は墨の記号 (地なし)。
        leading = if (entry.kind == GameKind.colorMatch) {
            ImasRowLeading.Custom(width = 40.dp) { ImasStageColorGridIcon() }
        } else {
            ImasRowLeading.Icon(entry.icon, tone = ImasIconTileTone.SOLID)
        },
        trailing = ImasRowTrailing.Custom {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                GameRowStatus(suspended, grade, entry, rec)
                ImasRowChevron()
            }
        },
        modifier = Modifier.imasRowPress(onClick = onClick)
    )
}

/** 行の末尾の状態 (プレイ中・自己ベスト・未プレイ)。1〜2 行、色は灰。 */
@Composable
private fun GameRowStatus(suspended: QuizSuspended?, grade: QuizGrade?, entry: GameEntry, rec: GameRecord) {
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
        if (suspended != null) {
            Text("プレイ中", style = ImasTextRole.SECTION_LABEL.style, color = DS.ink2)
            Text("Q.%02d".format(suspended.currentNumber), style = ImasTextRole.BADGE.style, color = DS.ink3)
        } else if (grade != null) {
            Text(grade.label, style = QS.num(22), color = DS.ink)
            Text(bestLabel(entry.kind, rec), style = ImasTextRole.BADGE.style, color = DS.ink3)
        } else {
            Text("未プレイ", style = ImasTextRole.SECTION_LABEL.style, color = DS.ink3)
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
