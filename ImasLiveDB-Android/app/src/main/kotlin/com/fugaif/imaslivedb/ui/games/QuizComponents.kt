package com.fugaif.imaslivedb.ui.games

import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import uniffi.imas_core.IdolQuizIdolRef
import uniffi.imas_core.QuizGrade
import uniffi.imas_core.QuizSessionResult
import uniffi.imas_core.quizSessionLength

// =============================================================================
// 4 択クイズ系 (アイドル当て / ソロ曲) の共通 UI 部品。iOS QuizComponents.swift の移植。
// ヒント式の段階採点を中核に据える: 最初は最小の情報だけで出題し、ヒントを開くほど
// 分かりやすくなる代わりに獲得点が下がる。進捗ヘッダ・選択肢・ヒント・結果を集約。
//
// 採点・出題・グレード判定の規則は imas-core (`domain::quiz_generation`) にあり、
// ここに残すのは描画だけ。両 OS で規則が二重管理にならないよう、点数もグレードも
// 画面側で計算し直さずコアが返した値をそのまま表示する。
// =============================================================================

/**
 * 1 セッションの出題数。規則はコア定数なので FFI から読む
 * (両 OS が別々の値を持てないようにするため、Kotlin 側に定数を置かない)。
 * ネイティブ初期化を画面表示まで遅らせたいので lazy。
 */
val QUIZ_SESSION_LENGTH: Int by lazy { quizSessionLength().toInt() }

// ---------------------------------------------------------------------------
// アイドル当てクイズの射影 (出題設定の見積りとゲーム本体で共有)
// ---------------------------------------------------------------------------

/**
 * 現任 CV 名 (idol id → 名前)。iOS の `VoiceActorDirectory` に相当する取得口。
 *
 * 声優は `idol_voice_actors` の**期間つき履歴**が正で、「現任 = valid_to IS NULL」を
 * 選ぶ規則はコアの `idolCastNames` が持つ。画面につき 1 回だけ呼ぶ
 * (アイドル 1 人ずつ引くと N+1 の FFI になる)。
 *
 * スナップショットが未ロード/利用不可なら空マップを返し、呼び出し側は
 * `idols.voice_actors` へ落ちる。**現状 Android の実 DB には `idol_voice_actors` が
 * 無いので、ここは常に空になる** (Room のエンティティが無く、SeedImporter は
 * 「Room と seed の両方にあるテーブル」しか取り込まないため)。
 * データ経路が入れば、この関数を含め呼び出し側は一切変えずに値が流れ始める。
 */
suspend fun fetchIdolCastNames(snapshots: SnapshotStoreProvider): Map<String, String> =
    snapshots.query { store -> store.idolCastNames() } ?: emptyMap()

/**
 * `Idol` → アイドル当てクイズの射影 (iOS QuizComponents.swift の `idolQuizRefs` と同じ置き場所)。
 * 出題設定画面の見積り (`idolQuizPoolEstimate`) とゲーム本体 (`idolQuizSession`) が
 * 同じ母集団を見るよう、変換もこの 1 か所に置く。
 *
 * CV は [castNames] (= 現任の声優) を第一に見る。iOS が `VoiceActorDirectory` 経由で
 * 渡しているのと同じ値で、期間つき履歴が正だから。`idols.voice_actors` はカンマ列の
 * 先頭を現任と見なす旧表現で、CloudKit の Idol 同期でしか埋まらないため、
 * 履歴が引けない時のフォールバックとしてだけ残す。
 *
 * 誕生日は生の `--MM-DD` のまま渡す (「4月3日」への整形はコア側の規則)。
 */
fun idolQuizRefs(idols: List<Idol>, castNames: Map<String, String>): List<IdolQuizIdolRef> =
    idols.map { idol ->
        IdolQuizIdolRef(
            id = idol.id,
            brandId = idol.brandId,
            isExternal = idol.isExternal,
            color = idol.color,
            bloodType = idol.bloodType,
            constellation = idol.constellation,
            birthPlace = idol.birthPlace,
            height = idol.height,
            age = idol.age,
            hobbies = idol.hobbies,
            talents = idol.talents,
            birthday = idol.birthday,
            voiceActor = castNames[idol.id] ?: idol.currentVoiceActor
        )
    }

/**
 * CV 枠を画面に出してよいか。母集団**全体**で 1 回だけ判定する。
 *
 * コアは CV を値の有無によらず常に事実へ積む。枠の有無で「この子は声優未発表だ」と
 * 無料でバレるのを防ぐためで、それは「CV 名を持つアイドルが居る」ことが前提になっている。
 * ところが Android は現任 CV の取得経路が実データに届いておらず ([fetchIdolCastNames] 参照)、
 * 母集団の**全員**が値なしになり得る。その状態で枠を出すと、最も開封コストの高い
 * ヒントが必ず「声優未発表」になって無価値になるうえ、解答後の一覧が全員を
 * 未発表だと偽って表示してしまう。
 *
 * アイドルごとに出し分けないのは、それこそがコアの避けている情報漏れだから
 * (枠が無い = 未発表、と無料で分かってしまう)。1 人でも CV を持っていれば通常どおり出す。
 */
fun hasVoiceActorData(refs: List<IdolQuizIdolRef>): Boolean =
    refs.any { !it.voiceActor.isNullOrEmpty() }

/** 進捗バー + 累計ポイント。第 current/total 問と現在の獲得ポイントを表示。 */
@Composable
fun QuizProgressHeader(current: Int, total: Int, points: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("第 $current / $total 問", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
            Box(Modifier.weight(1f))
            Icon(Icons.Filled.Star, null, tint = DS.favorite, modifier = Modifier.size(14.dp))
            Text("$points pt", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink, modifier = Modifier.padding(start = 4.dp))
        }
        val progress = if (total > 0) ((current - 1).toFloat() / total).coerceIn(0f, 1f) else 0f
        Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(DS.fill)) {
            Box(
                Modifier.fillMaxWidth(progress).height(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(ImasTheme.derive(null, null, dark = true).accent)
            )
        }
    }
}

/** 正解で獲得できるポイントを示すバッジ。加点表現に統一 (減点語は使わない)。 */
@Composable
fun QuizValueBadge(points: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.clip(CircleShape).background(DS.success.copy(alpha = 0.14f)).padding(horizontal = 11.dp, vertical = 6.dp)
    ) {
        Icon(Icons.Filled.AddCircle, null, tint = DS.success, modifier = Modifier.size(11.dp))
        Text("正解で +${points}pt", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.success)
    }
}

/** 段階ヒントを開くボタン。開くと「以降の上限点が下がる」ことを副題で明示する。 */
@Composable
fun QuizHintButton(icon: ImageVector, title: String, nextValue: Int, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .border(1.5.dp, DS.warning.copy(alpha = 0.35f), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(DS.warning.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, tint = DS.warning, modifier = Modifier.size(16.dp)) }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            Text("開いた後は正解で +${nextValue}pt", fontSize = 12.sp, color = DS.ink3)
        }
        Icon(Icons.Filled.ExpandMore, null, tint = DS.ink3, modifier = Modifier.size(13.dp))
    }
}

/** クイズ共通の主ボタン (次の問題 / 結果を見る)。 */
@Composable
fun QuizPrimaryButton(title: String, onClick: () -> Unit) {
    val t = ImasTheme.derive(null, null, dark = true)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(t.accent)
            .clickable(onClick = onClick)
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = t.onAccent)
    }
}

/** 解答後に出す「次の問題 / 結果を見る」ボタン。最終問なら結果へ、それ以外は次問へ進む。 */
@Composable
fun QuizNextButton(isLastQuestion: Boolean, onNext: () -> Unit, onFinish: () -> Unit) {
    QuizPrimaryButton(title = if (isLastQuestion) "結果を見る" else "次の問題") {
        if (isLastQuestion) onFinish() else onNext()
    }
}

/** 4 択ボタン。未解答 = ニュートラル / 解答後は正解=緑・誤答=赤で明示。 */
@Composable
private fun QuizChoiceButton(
    name: String,
    answered: Boolean,
    isAnswer: Boolean,
    isPicked: Boolean,
    avatar: (@Composable () -> Unit)?,
    onClick: () -> Unit
) {
    val bg = when {
        !answered -> DS.surface
        isAnswer -> DS.success.copy(alpha = 0.18f)
        isPicked -> DS.danger.copy(alpha = 0.18f)
        else -> DS.surface
    }
    val border = if (answered && (isAnswer || isPicked)) (if (isAnswer) DS.success else DS.danger) else Color.Transparent
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(1.5.dp, border, RoundedCornerShape(14.dp))
            .clickable(enabled = !answered, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (answered && avatar != null) avatar()
        Text(
            name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
        )
        if (answered && isAnswer) {
            Icon(Icons.Filled.CheckCircle, null, tint = DS.success, modifier = Modifier.size(18.dp))
        } else if (answered && isPicked) {
            Icon(Icons.Filled.Cancel, null, tint = DS.danger, modifier = Modifier.size(18.dp))
        }
    }
}

/** アイドル 4 択グリッド。アイドル当て / ソロ曲クイズで共通。解答後は本人アバターを添えて正誤を色で示す。 */
@Composable
fun IdolChoiceGrid(choices: List<Idol>, answer: Idol, selectedId: String?, onPick: (Idol, Boolean) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.height(((choices.size + 1) / 2 * 60).dp)
    ) {
        items(choices, key = { it.id }) { idol ->
            val answered = selectedId != null
            val isAnswer = idol.id == answer.id
            QuizChoiceButton(
                name = idol.name, answered = answered, isAnswer = isAnswer, isPicked = idol.id == selectedId,
                avatar = { ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 30.dp) }
            ) {
                if (selectedId == null) onPick(idol, isAnswer)
            }
        }
    }
}

/** セッション内の1問分の振り返り。リザルト画面の「何が出て何を間違えたか」一覧に使う。 */
data class QuizHistoryItem(
    val id: String,
    val index: Int,
    val subjectTitle: String,
    val subjectSubtitle: String?,
    val answer: Idol,
    val picked: Idol?,
    val earnedPoints: Int,
    val revealedHints: Int
) {
    val isCorrect: Boolean get() = picked?.id == answer.id
}

/** グレードの表示色。グレードそのもの (正答率からの判定) はコアが返す。 */
@Composable
private fun QuizGrade.color(): Color = when (this) {
    QuizGrade.S -> DS.favorite
    QuizGrade.A -> DS.success
    QuizGrade.B -> ImasTheme.derive(null, null, dark = true).accent
    QuizGrade.C -> DS.warning
    QuizGrade.D -> DS.ink3
}

/**
 * セッション終了時の結果画面。グレード・自己ベスト・新記録・出題履歴・シェアまで載せる。
 *
 * 点・率・グレードはコアの [QuizSessionResult] をそのまま出す。`isNewBest` と
 * [bestRate] は**記録を保存した後**の値を呼び出し側 (ViewModel) が渡す:
 * 自己ベストの更新規則はコアの `game_progress` 側にしか無く、ここで引き直すと
 * 保存の前後どちらの値を見ているのかが画面ごとにぶれる。
 */
@Composable
fun QuizResultView(
    result: QuizSessionResult,
    kind: GameKind,
    isNewBest: Boolean,
    bestRate: Int,
    history: List<QuizHistoryItem>,
    onReplay: () -> Unit
) {
    val context = LocalContext.current
    val points = result.points.toInt()
    val maxPoints = result.maxPoints.toInt()
    val correct = result.correct.toInt()
    val questions = result.questions.toInt()
    val rate = result.ratePercent.toInt()
    val grade = result.grade
    val gradeColor = grade.color()

    val comment = when {
        rate >= 95 -> "お見事！担当への愛が伝わる"
        rate >= 80 -> "高得点！プロデューサーの貫禄"
        rate >= 50 -> "いい線いってる！次はもっと高みへ"
        else -> "これから一緒に覚えていこう"
    }

    var appeared by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (appeared) 1f else 0.6f,
        animationSpec = spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMediumLow),
        label = "gradeScale"
    )
    androidx.compose.runtime.LaunchedEffect(Unit) { appeared = true }

    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(116.dp).clip(CircleShape).background(gradeColor.copy(alpha = 0.14f))
            .border(4.dp, gradeColor, CircleShape).graphicsLayer(scaleX = scale, scaleY = scale)) {
            Text(grade.name, fontSize = 56.sp, fontWeight = FontWeight.Bold, color = gradeColor)
        }

        AnimatedVisibility(visible = isNewBest, enter = scaleIn() + fadeIn()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.clip(CircleShape).background(DS.favorite.copy(alpha = 0.16f)).padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Icon(Icons.Filled.WorkspacePremium, null, tint = DS.favorite, modifier = Modifier.size(12.dp))
                Text("自己ベスト更新！", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.favorite)
            }
        }

        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("$points", fontSize = 40.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Text("/ $maxPoints pt", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            ResultStat(value = "$correct/$questions", label = "正解", modifier = Modifier.weight(1f))
            ResultStat(value = "$rate%", label = "正答率", modifier = Modifier.weight(1f))
            ResultStat(value = "$bestRate%", label = "自己ベスト", modifier = Modifier.weight(1f))
        }

        Text(comment, fontSize = 13.sp, color = DS.ink3, modifier = Modifier.padding(top = 2.dp))

        if (history.isNotEmpty()) {
            QuizHistoryList(items = history)
        }

        Column(modifier = Modifier.fillMaxWidth().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            QuizPrimaryButton(title = "もう一度", onClick = onReplay)
            val shareText = "${kind.displayName}で $points/$maxPoints pt・グレード${grade.name}（正解 $correct/$questions）でした！ #アイドルライブDB"
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(ImasTheme.derive(null, null, dark = true).accent.copy(alpha = 0.12f))
                    .clickable {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, shareText)
                        }
                        context.startActivity(Intent.createChooser(intent, null))
                    }
                    .padding(vertical = 12.dp)
            ) {
                Icon(Icons.Filled.Share, null, tint = ImasTheme.derive(null, null, dark = true).accent, modifier = Modifier.size(14.dp))
                Text(
                    "結果をシェア", fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    color = ImasTheme.derive(null, null, dark = true).accent, modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
    }
}

@Composable
private fun ResultStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.clip(RoundedCornerShape(14.dp)).background(DS.surface).padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text(label, fontSize = 12.sp, color = DS.ink2)
    }
}

// MARK: - 出題履歴 (リザルトの「何が出て何を間違えたか」一覧)

@Composable
private fun QuizHistoryList(items: List<QuizHistoryItem>) {
    Column(modifier = Modifier.fillMaxWidth().padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.AutoMirrored.Filled.ViewList, null, tint = DS.ink2, modifier = Modifier.size(13.dp))
            Text("出題の振り返り", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        }
        items.forEach { QuizHistoryRow(it) }
    }
}

@Composable
private fun QuizHistoryRow(item: QuizHistoryItem) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.surface).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(36.dp)) {
            Text("Q${item.index}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
            Icon(
                if (item.isCorrect) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
                tint = if (item.isCorrect) DS.success else DS.danger, modifier = Modifier.size(16.dp)
            )
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(item.subjectTitle, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            item.subjectSubtitle?.takeIf { it.isNotEmpty() }?.let {
                Text(it, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AnswerChip(label = "正解", idol = item.answer, tone = DS.success)
                if (!item.isCorrect) {
                    item.picked?.let { AnswerChip(label = "選択", idol = it, tone = DS.danger) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icon(
                        Icons.Filled.AddCircle, null, modifier = Modifier.size(11.dp),
                        tint = if (item.earnedPoints > 0) DS.success else DS.ink3
                    )
                    Text("${item.earnedPoints}pt", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (item.earnedPoints > 0) DS.success else DS.ink3)
                }
                if (item.revealedHints > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Icon(Icons.Filled.Lightbulb, null, tint = DS.warning, modifier = Modifier.size(11.dp))
                        Text("ヒント${item.revealedHints}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.warning)
                    }
                }
            }
        }
    }
}

@Composable
private fun AnswerChip(label: String, idol: Idol, tone: Color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.clip(CircleShape).background(tone.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 20.dp)
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = tone)
        Text(idol.name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
