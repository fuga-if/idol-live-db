package com.fugaif.imaslivedb.ui.introdon

import com.fugaif.imaslivedb.data.model.Song
import kotlin.random.Random
import uniffi.imas_core.IntroQuizSongRef
import uniffi.imas_core.introQuizChoicesBatch

/**
 * イントロドンのゲームモード。iOS IntroGameMode の移植。
 * Android には音声判定 (SpeechRecognizer 基盤なし) が無いため回答方式は常に 4択。
 */
enum class IntroDonMode(val label: String, val icon: String) {
    NORMAL("ノーマル", "決めた問題数で挑戦"),
    RUSH("ラッシュ", "制限時間内に何問正解できるか"),
    ALL_SONGS("全曲チャレンジ", "全曲出し切るまで・タイムと正答率を競う"),
    PARTY("パーティ対戦", "1台2人・分割画面で早押し")
}

/** 高速形式 (押すまで流す・選択肢常時・即次へ)。Rush と 全曲チャレンジ。 */
val IntroDonMode.isFast: Boolean get() = this == IntroDonMode.RUSH || this == IntroDonMode.ALL_SONGS

data class IntroDonSettings(
    val mode: IntroDonMode = IntroDonMode.NORMAL,
    val questionCount: Int = 10,
    val introDurationMs: Long = 5_000L,
    val rushTimeLimitSec: Int = 60,
    val selectedBrandIds: Set<String> = emptySet()
)

data class IntroDonQuestion(
    val id: String,
    val title: String,
    val brandId: String?,
    val previewUrl: String?,
    val artworkUrl: String?,
    val choices: List<String>
)

data class IntroDonAnswerRecord(
    val id: String,
    val title: String,
    val selectedTitle: String?,
    val correct: Boolean
)

enum class IntroDonPhase { LOADING, PLAYING, ANSWERING, REVEALED, FINISHED }

/** イントロドン出題に使える曲だけに絞る (preview_url あり・親曲でない)。リポジトリ側で既に絞っているが二重防御。 */
fun introDonPlayable(songs: List<Song>): List<Song> =
    songs.filter { !it.previewUrl.isNullOrEmpty() && it.parentSongId == null }

/**
 * 出題曲それぞれの選択肢 (正解 1 + 不正解 [wrongCount]) をまとめて生成する。
 * 戻り値は [answers] と同順・同数。候補が足りない設問はその分だけ少ない選択肢になる
 * (正解は必ず含む)。
 *
 * 規則本体は imas-core (Rust) の `domain/intro_quiz_choices.rs` にあり、iOS の
 * `IntroQuizChoices` と同じ実装を共有する。なぜタイトルでユニーク化するか (同名異曲対策)
 * 等の設計意図もそちらに記載。ここが担うのは「シードの調達」と「[Song] → (id, title) 射影」
 * だけ。出題ごとにループで FFI を呼ばないよう、1 ゲームぶんを 1 呼び出しで生成する
 * (バッチのみを公開し、設問単位の呼び口は置かない)。
 *
 * @param random シード調達源。テストから固定乱数を差せるようにするための注入点。
 */
fun introDonChoicesAll(
    answers: List<Song>,
    pool: List<Song>,
    wrongCount: Int = 3,
    random: Random = Random.Default
): List<List<String>> = introQuizChoicesBatch(
    answers = answers.map { IntroQuizSongRef(id = it.id, title = it.title) },
    pool = pool.map { IntroQuizSongRef(id = it.id, title = it.title) },
    // 負の wrongCount は 0 (正解のみ) に丸める。境界の型合わせのみで判定はしない。
    wrongCount = wrongCount.coerceAtLeast(0).toUInt(),
    seed = random.nextLong().toULong(),
)

/** プール曲から出題数分をランダム抽出し、選択肢付きの出題リストを組む。 */
fun buildIntroDonQuestions(pool: List<Song>, count: Int): List<IntroDonQuestion> {
    val picked = pool.shuffled().take(count)
    // 選択肢は 1 ゲームぶんまとめて 1 回の FFI 呼び出しで生成する (出題ごとのループ呼び出しにしない)。
    return picked.zip(introDonChoicesAll(picked, pool)).map { (song, choices) ->
        IntroDonQuestion(
            id = song.id,
            title = song.title,
            brandId = song.brandId,
            previewUrl = song.previewUrl,
            artworkUrl = song.artworkUrl,
            choices = choices
        )
    }
}

/** 曲一覧のブランド絞り込みをルート引数の1文字列にエンコード/デコードする ("all" = 未選択=全ブランド)。 */
fun encodeIntroDonBrandIds(brandIds: Set<String>): String =
    if (brandIds.isEmpty()) "all" else brandIds.sorted().joinToString(",")

fun decodeIntroDonBrandIds(raw: String?): Set<String> =
    if (raw.isNullOrEmpty() || raw == "all") emptySet() else raw.split(",").filter { it.isNotEmpty() }.toSet()
