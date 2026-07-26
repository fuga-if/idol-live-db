package com.fugaif.imaslivedb.ui.introdon

import com.fugaif.imaslivedb.data.model.Song
import kotlin.random.Random

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
 * 不正解の候補。正解自身・正解と同じタイトル・既出タイトルを除く。
 * 順序は `pool` のまま (シャッフルしない) ので、規則だけを単体で検証できる。
 *
 * 同名異曲 (別バージョン・リミックス等) が pool に複数あると、不正解として同じタイトルが
 * 2 つ並びうる。**タイトル**で重複を落とす (曲 ID ではなく)。iOS の `IntroQuizChoices` と 1:1。
 */
fun introDonWrongCandidates(song: Song, pool: List<Song>): List<Song> {
    val seenTitles = mutableSetOf(song.title)
    return pool.filter { it.id != song.id && seenTitles.add(it.title) }
}

/**
 * 出題する選択肢。正解 1 つ + 不正解 [wrongCount] 個を混ぜて返す。
 * 候補が足りなければその分だけ少ない選択肢になる (正解は必ず含む)。
 *
 * @param random テストから固定乱数を差せるようにするための乱数源。
 */
fun introDonChoices(
    song: Song,
    pool: List<Song>,
    wrongCount: Int = 3,
    random: Random = Random.Default
): List<String> {
    val wrongs = introDonWrongCandidates(song, pool).shuffled(random).take(wrongCount).map { it.title }
    return (wrongs + song.title).shuffled(random)
}

/** プール曲から出題数分をランダム抽出し、選択肢付きの出題リストを組む。 */
fun buildIntroDonQuestions(pool: List<Song>, count: Int): List<IntroDonQuestion> {
    val picked = pool.shuffled().take(count)
    return picked.map { song ->
        IntroDonQuestion(
            id = song.id,
            title = song.title,
            brandId = song.brandId,
            previewUrl = song.previewUrl,
            artworkUrl = song.artworkUrl,
            choices = introDonChoices(song, pool)
        )
    }
}

/** 曲一覧のブランド絞り込みをルート引数の1文字列にエンコード/デコードする ("all" = 未選択=全ブランド)。 */
fun encodeIntroDonBrandIds(brandIds: Set<String>): String =
    if (brandIds.isEmpty()) "all" else brandIds.sorted().joinToString(",")

fun decodeIntroDonBrandIds(raw: String?): Set<String> =
    if (raw.isNullOrEmpty() || raw == "all") emptySet() else raw.split(",").filter { it.isNotEmpty() }.toSet()
