package com.fugaif.imaslivedb.ui.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import uniffi.imas_core.IdolQuizIdolRef
import uniffi.imas_core.quizSessionLength

// =============================================================================
// 4 択クイズ系 (アイドル当て / ソロ曲) のコアへの受け渡しと、出題設定画面の共通ボタン。
// iOS QuizComponents.swift の移植。画面の部品 (ペンライト・チケット・正誤・結果) は QuizStage.kt にある。
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
 * 声優の履歴 (idol_voice_actors) は seed で入る。履歴が無いアイドルはマップに載らない (CV 無し)。
 */
suspend fun fetchIdolCastNames(snapshots: SnapshotStoreProvider): Map<String, String> =
    snapshots.query { store -> store.idolCastNames() }

/**
 * `Idol` → アイドル当てクイズの射影 (iOS QuizComponents.swift の `idolQuizRefs` と同じ置き場所)。
 * 出題設定画面の見積り (`idolQuizPoolEstimate`) とゲーム本体 (`idolQuizSession`) が
 * 同じ母集団を見るよう、変換もこの 1 か所に置く。
 *
 * CV は [castNames] (= 現任の声優) だけを見る。iOS が `VoiceActorDirectory` 経由で
 * 渡しているのと同じ値で、期間つき履歴が正だから (`idols.voice_actors` 列は使わない)。
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
            voiceActor = castNames[idol.id]
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

/** 出題設定画面の主ボタン (スタート / はじめる)。ゲーム中はステージの [QuizStagePrimaryButton] を使う。 */
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
