package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.games.QuizStagePlay
import com.fugaif.imaslivedb.data.games.longestStreak
import com.fugaif.imaslivedb.ui.share.ShareCardActionPane
import com.fugaif.imaslivedb.ui.share.ShareCardArtwork
import com.fugaif.imaslivedb.ui.share.ShareCardRatio
import com.fugaif.imaslivedb.ui.share.ShareCardSheet
import com.fugaif.imaslivedb.ui.share.ShareCardSize
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import uniffi.imas_core.QuizSessionResult
import uniffi.imas_core.shareQuizResultText

// =============================================================================
// ミニゲーム共通の結果シェア画像 (1080×1350)。iOS QuizShareCard.swift の移植。
// 結果画面と同じ「暗いステージ + 生成りのチケット」。
//
// 上から: ゲーム名 → セトリのペンライト (正解は答えの色で点灯) → グレードと点のチケット →
// 1 問ずつの答え (最大 10 行) → アプリ名。曲のゲームは遊んだ曲のジャケットを上に敷く。
//
// ⚠️ 歌詞は 1 文字も載せない (JASRAC の条件)。載せるのは曲名・名前・正誤・点だけ。
//
// NOTE: カードは ShareCardCanvas の論理単位 (540×675、1 単位 = 2px) で組むので、
// 寸法・文字サイズはどれも iOS (1080×1350pt) の半分。焼き込みは今画面に描かれているものを
// 録るだけなので、ジャケットは焼く前に ImageBitmap にしておく ([rememberQuizShareArtworks])。
// =============================================================================

/** シェア画像の 1 行 (1 問ぶん)。 */
data class QuizShareRow(
    val number: Int,
    val title: String,
    /** 答えの色 (アイドルのイメージカラー)。曲など色が無ければ null (ペンライトの色で代用)。 */
    val hex: String?,
    val isCorrect: Boolean
)

/** 各問の記録 → シェア画像の行。 */
val List<QuizStagePlay>.shareRows: List<QuizShareRow>
    get() = map { QuizShareRow(number = it.number, title = it.answerName, hex = it.answerHex, isCorrect = it.isCorrect) }

/** 他のクイズ共通のシェア文 (コアが作る)。歌詞は入らない。 */
fun quizShareText(gameName: String, result: QuizSessionResult): String = shareQuizResultText(
    gameDisplayName = gameName, points = result.points, maxPoints = result.maxPoints,
    grade = result.grade, correct = result.correct, questions = result.questions
)

private const val MAX_ROWS = 10
private const val MAX_BAND = 20

@Composable
fun QuizShareCard(
    title: String,
    result: QuizSessionResult,
    rows: List<QuizShareRow>,
    longestStreak: Int,
    isNewBest: Boolean,
    size: ShareCardSize,
    /** モードや難易度 (「4択 · ふつう」など)。 */
    subtitle: String? = null,
    /** 上に敷くジャケット (曲のゲーム)。空なら敷かない。 */
    artworks: List<ImageBitmap> = emptyList()
) {
    Box(
        Modifier
            .requiredSize(size.widthUnits.dp, size.heightUnits.dp)
            .background(QS.bg)
    ) {
        ShareBackdrop(artworks)
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = 32.dp, end = 32.dp, top = 30.dp, bottom = 26.dp)
        ) {
            // 本文はフッターの上の残りを使い切る (フッターは常に下端)。
            Column(Modifier.weight(1f).fillMaxWidth()) {
                ShareHeader(title, subtitle)
                if (rows.isNotEmpty() && rows.size <= MAX_BAND) {
                    SharePenlightBand(rows, Modifier.padding(top = 15.dp))
                }
                ShareTicket(result, longestStreak, isNewBest, Modifier.padding(top = 13.dp))
                if (rows.isNotEmpty()) {
                    // 端末の書体で背が伸びても、フッターを押し出さずに一覧の下が切れるだけにする。
                    ShareAnswerList(rows, Modifier.padding(top = 11.dp).weight(1f, fill = false))
                }
            }
            ShareFooter()
        }
    }
}

// MARK: - 背景

@Composable
private fun ShareBackdrop(artworks: List<ImageBitmap>) {
    if (artworks.isEmpty()) {
        // ペンライトの色をうっすら 2 灯。
        Box(
            Modifier.fillMaxSize().drawBehind {
                drawRect(
                    Brush.radialGradient(
                        listOf(QS.penlight(0).copy(alpha = 0.22f), Color.Transparent),
                        center = Offset.Zero, radius = 380.dp.toPx()
                    )
                )
                drawRect(
                    Brush.radialGradient(
                        listOf(QS.penlight(4).copy(alpha = 0.18f), Color.Transparent),
                        center = Offset(size.width, 0f), radius = 350.dp.toPx()
                    )
                )
            }
        )
    } else {
        // 遊んだ曲のジャケットを斜めのモザイクで上に敷き、下へ向かって消す。
        Box(
            Modifier
                .fillMaxWidth()
                .height(320.dp)
                .graphicsLayer { alpha = 0.7f; compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.9f), Color.Black.copy(alpha = 0.5f), Color.Transparent)
                        ),
                        blendMode = BlendMode.DstIn
                    )
                }
        ) {
            QuizShareMosaic(artworks)
        }
    }
}

/** ジャケットの斜めモザイク (iOS `LyricsQuizMosaicBackground`)。 */
@Composable
private fun QuizShareMosaic(images: List<ImageBitmap>) {
    val tile = 125
    val gap = 7
    val columns = 8
    val rowCount = 9
    val gridWidth = columns * tile + (columns - 1) * gap + (tile + gap) / 2
    val gridHeight = rowCount * tile + (rowCount - 1) * gap
    val shape = RoundedCornerShape(10.dp)
    Box(
        Modifier.fillMaxSize().clipToBounds().background(Color.Black),
        contentAlignment = Alignment.Center
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(gap.dp),
            modifier = Modifier
                // 親より大きく組み、はみ出した分は親で切る。
                .requiredSize(gridWidth.dp, gridHeight.dp)
                .rotate(-14f)
                .alpha(0.95f)
        ) {
            repeat(rowCount) { r ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(gap.dp),
                    // 段ごとに半タイルずらして、同じジャケットが縦に揃わないようにする。
                    modifier = Modifier.offset(x = if (r % 2 == 0) 0.dp else ((tile + gap) / 2).dp)
                ) {
                    repeat(columns) { c ->
                        val index = r * columns + c + r * 3
                        Image(
                            bitmap = images[index % images.size],
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(tile.dp).clip(shape)
                        )
                    }
                }
            }
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = 0.35f),
                    0.18f to Color.Black.copy(alpha = 0.15f),
                    0.42f to Color.Black.copy(alpha = 0.62f),
                    0.7f to Color.Black.copy(alpha = 0.9f),
                    1f to Color.Black.copy(alpha = 0.96f)
                )
            )
        )
    }
}

// MARK: - 見出し

@Composable
private fun ShareHeader(title: String, subtitle: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            "QUIZ STAGE",
            style = QS.mono(11, tracking = 4f),
            color = QS.ink,
            modifier = Modifier
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.4f))
                .border(0.75.dp, QS.ink.copy(alpha = 0.3f), CircleShape)
                .padding(horizontal = 9.dp, vertical = 5.dp)
        )
        QSFitText(
            title, QS.text(33, FontWeight.Black), QS.ink,
            modifier = Modifier.padding(top = 2.dp), minScale = 0.6f
        )
        if (subtitle != null) {
            Text(subtitle, style = QS.text(14, FontWeight.Bold), color = QS.dim, maxLines = 1)
        }
    }
}

// MARK: - セトリのペンライト

@Composable
private fun SharePenlightBand(rows: List<QuizShareRow>, modifier: Modifier = Modifier) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = modifier) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.fillMaxWidth()) {
            rows.forEachIndexed { i, row ->
                val fill = if (row.isCorrect) shareColor(row, i) else QS.missFill
                // 1 本の太さは 20 まで。本数が少ないときは iOS と同じく左に寄る。
                Box(
                    Modifier
                        .weight(1f, fill = false)
                        .widthIn(max = 20.dp)
                        .fillMaxWidth()
                        .height(48.dp)
                        .then(if (row.isCorrect) Modifier.penlightGlow(fill) else Modifier)
                        .clip(CircleShape)
                        .background(fill)
                        .then(if (row.isCorrect) Modifier else Modifier.border(1.dp, QS.line, CircleShape))
                )
            }
        }
        Text(
            "今回のセトリ ${rows.count { it.isCorrect }} 本点灯",
            style = QS.text(11, FontWeight.Bold), color = QS.dim
        )
    }
}

/**
 * 点灯したペンライトの光。影 (elevation) は焼き込みの経路や端末で出方が変わるので、
 * 少しずつ広げた半透明の角丸を重ねて描く (iOS の `shadow(radius: 14)` 相当)。
 */
private fun Modifier.penlightGlow(color: Color): Modifier = drawBehind {
    val steps = 7
    for (i in steps downTo 1) {
        val spread = i * 1.2.dp.toPx()
        drawRoundRect(
            color = color.copy(alpha = 0.075f),
            topLeft = Offset(-spread, -spread),
            size = androidx.compose.ui.geometry.Size(size.width + spread * 2, size.height + spread * 2),
            cornerRadius = CornerRadius(size.width / 2 + spread)
        )
    }
}

// MARK: - チケット

@Composable
private fun ShareTicket(result: QuizSessionResult, longestStreak: Int, isNewBest: Boolean, modifier: Modifier = Modifier) {
    var summary = "${result.correct} / ${result.questions} 正解"
    if (longestStreak >= 2) summary += " · 最大 $longestStreak 連続"
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(QS.paper)
            .padding(horizontal = 18.dp, vertical = 14.dp)
    ) {
        Column {
            Text("GRADE", style = QS.mono(10, tracking = 1.5f), color = QS.paperSub)
            Text(
                result.grade.label,
                style = QS.num(105, FontWeight.Black).copy(lineHeight = 80.sp, lineHeightStyle = TightLine),
                color = QS.paperInk, maxLines = 1,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("SCORE", style = QS.mono(10, tracking = 1.5f), color = QS.paperSub)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "${result.points}",
                    style = QS.num(52, FontWeight.Black).copy(lineHeight = 44.sp, lineHeightStyle = TightLine),
                    color = QS.paperInk
                )
                Text(
                    "/ ${result.maxPoints} pt", style = QS.text(13, FontWeight.Bold), color = QS.paperSub,
                    modifier = Modifier.padding(bottom = 5.dp)
                )
            }
            Text(summary, style = QS.text(13, FontWeight.Bold), color = QS.paperInk, maxLines = 1)
            if (isNewBest) {
                Text(
                    "自己ベスト更新",
                    style = QS.text(14, FontWeight.Black),
                    color = QS.stamp,
                    modifier = Modifier
                        .padding(top = 3.dp)
                        .rotate(-5f)
                        .border(1.75.dp, QS.stamp, RoundedCornerShape(5.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                )
            }
        }
    }
}

/** 大きな数字の上下の余白を詰める (チケットの高さを iOS に合わせるため)。 */
private val TightLine = LineHeightStyle(alignment = LineHeightStyle.Alignment.Center, trim = LineHeightStyle.Trim.Both)

// MARK: - 答えの一覧

@Composable
private fun ShareAnswerList(rows: List<QuizShareRow>, modifier: Modifier = Modifier) {
    val shown = rows.take(MAX_ROWS)
    val extra = rows.size - shown.size
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(QS.panel.copy(alpha = 0.92f))
            .border(0.75.dp, QS.line, shape)
            .padding(horizontal = 14.dp, vertical = 7.dp)
    ) {
        shown.forEachIndexed { i, row ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp),
                modifier = Modifier.fillMaxWidth().height(22.dp)
            ) {
                Text("Q.${twoDigits(row.number)}", style = QS.mono(10), color = QS.faint, modifier = Modifier.width(39.dp))
                Box(
                    Modifier
                        .size(9.dp)
                        .alpha(if (row.isCorrect) 1f else 0.35f)
                        .clip(CircleShape)
                        .background(shareColor(row, i))
                )
                Text(
                    row.title,
                    style = QS.text(14, FontWeight.Bold),
                    color = if (row.isCorrect) QS.ink else QS.dim,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    if (row.isCorrect) Icons.Filled.Check else Icons.Filled.Close,
                    contentDescription = if (row.isCorrect) "正解" else "不正解",
                    tint = if (row.isCorrect) QS.ink else QS.faint,
                    modifier = Modifier.size(14.dp)
                )
            }
            if (i < shown.size - 1) {
                Box(Modifier.fillMaxWidth().height(0.5.dp).background(QS.rowLine))
            }
        }
        if (extra > 0) {
            Text(
                "ほか $extra 問", style = QS.text(11, FontWeight.Bold), color = QS.dim,
                modifier = Modifier.padding(top = 5.dp)
            )
        }
    }
}

// MARK: - フッター

@Composable
private fun ShareFooter() {
    Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.fillMaxWidth()) {
        Text("アイドルライブDB", style = QS.text(17, FontWeight.Black), color = QS.ink)
        Spacer(Modifier.weight(1f))
        // ストア名は iOS の「App Store」をそのまま使わない (Android から辿り着けない案内になる)。
        Text(
            "Google Play で配信中", style = QS.text(11, FontWeight.Bold), color = QS.dim,
            modifier = Modifier.padding(bottom = 2.dp)
        )
    }
}

private fun shareColor(row: QuizShareRow, index: Int): Color = qsColor(row.hex, QS.penlight(index))

// MARK: - シェアの入口

/** シェア画像に焼くジャケットの読み込み状態。 */
class QuizShareArtworks(val images: List<ImageBitmap>, val isFinished: Boolean)

/**
 * シェア画像に焼くジャケットの事前ロード。結果画面が出た時点で始めておき、
 * 取れた分だけで焼く (4 秒で打ち切る。iOS `LyricsQuizShareArtwork.load` と同じ)。
 */
@Composable
fun rememberQuizShareArtworks(urls: List<String>): QuizShareArtworks {
    val context = LocalContext.current
    val distinct = remember(urls) { urls.filter { it.isNotBlank() }.distinct() }
    var state by remember(distinct) { mutableStateOf(QuizShareArtworks(emptyList(), isFinished = distinct.isEmpty())) }
    LaunchedEffect(distinct) {
        if (distinct.isEmpty()) return@LaunchedEffect
        val loaded = mutableMapOf<String, ImageBitmap>()
        withTimeoutOrNull(4_000) {
            coroutineScope {
                distinct.map { url ->
                    async { ShareCardArtwork.load(context, url)?.let { synchronized(loaded) { loaded[url] = it } } }
                }.awaitAll()
            }
        }
        val images = synchronized(loaded) { distinct.mapNotNull { loaded[it] } }
        state = QuizShareArtworks(images, isFinished = true)
    }
    return state
}

/**
 * 結果画面の右上に置く「結果を画像でシェア」ボタンと、そのプレビューシート。
 * 押すとカードのプレビューを出し、シェア (画像 + 文面) / 保存を選べる。
 *
 * @param cardTitle 画像の見出し (「アイドル当て」)。
 * @param shareName シェア文のゲーム名 (「アイドル当てクイズ」)。文面はコアが作る。
 * @param artworkUrls 背景に敷くジャケット (曲のゲームだけ)。結果が出た時点で読み込み始める。
 */
@Composable
fun QuizStageShareButton(
    cardTitle: String,
    shareName: String,
    result: QuizSessionResult,
    plays: List<QuizStagePlay>,
    isNewBest: Boolean,
    fileNamePrefix: String,
    subtitle: String? = null,
    artworkUrls: List<String> = emptyList()
) {
    val artworks = rememberQuizShareArtworks(artworkUrls)
    var showing by remember { mutableStateOf(false) }
    QuizStageRoundButton(Icons.Filled.Share, "結果を画像でシェア") { showing = true }
    if (showing) {
        val rows = remember(plays) { plays.shareRows }
        ShareCardSheet(title = "結果をシェア", onDismiss = { showing = false }) {
            ShareCardActionPane(
                // レイアウトは 4:5 前提なので比率は切り替えない。
                ratios = listOf(ShareCardRatio.PORTRAIT),
                isPreparingCard = !artworks.isFinished,
                shareText = quizShareText(shareName, result),
                fileNamePrefix = fileNamePrefix
            ) { size ->
                QuizShareCard(
                    title = cardTitle, subtitle = subtitle, result = result, rows = rows,
                    longestStreak = plays.longestStreak, isNewBest = isNewBest,
                    size = size, artworks = artworks.images
                )
            }
        }
    }
}
