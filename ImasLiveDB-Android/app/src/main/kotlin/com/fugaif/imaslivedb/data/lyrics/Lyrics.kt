package com.fugaif.imaslivedb.data.lyrics

import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.LyricPartBreak
import uniffi.imas_core.LyricPartSegment
import uniffi.imas_core.lyricCallEchoesLine
import uniffi.imas_core.lyricPartSegments
import uniffi.imas_core.lyricPartUnion

// =============================================================================
// 歌詞モデル (メモリ専用)。iOS の Models/Lyrics.swift と 1:1。
//
// ⚠️ 許諾 (NexTone / JASRAC) の条件で「ユーザが一括ダウンロードできない形式での配信」が必須。
// 歌詞はプロセス内メモリ以外のどこにも保持してはならない:
//   - Room / SharedPreferences / DataStore / ファイル / バックアップ / 共有画像 / ウィジェット
// そのため、ここの型は Room の @Entity にも kotlinx.serialization の @Serializable にもしない
// (書き出し経路を型で塞ぐ)。**この 2 点は絶対に緩めないこと。**
// サーバへ送るものは LyricsApi が行 ID・位置・時刻だけを詰める (本文は送らない)。
// =============================================================================

/** 歌詞 1 行の種別。未知の値は本文 (`LYRIC`) として扱う。 */
enum class LyricLineKind(val raw: String) {
    LYRIC("lyric"), MARKER("marker"), BLANK("blank");

    companion object {
        fun of(raw: String?): LyricLineKind = entries.firstOrNull { it.raw == raw } ?: LYRIC
    }
}

/** 行頭の手拍子の指示。記号はコール表の慣習。 */
enum class LyricClap(val raw: String, val symbol: String, val label: String) {
    BACK_BEAT("back_beat", "★", "裏拍"),
    FOUR_ON_FLOOR("four_on_floor", "■", "4つ打ち"),
    PPPH("ppph", "♠", "PPPH"),
    NO_CALL("none", "♥", "コールなし");

    companion object {
        fun of(raw: String?): LyricClap? = entries.firstOrNull { it.raw == raw }
    }
}

/** コールの強調度。凡例に出すのは実際に使われているものだけ。 */
enum class CallEmphasis(val raw: String, val label: String) {
    NORMAL("normal", "通常"),
    OPTIONAL("optional", "おこのみで"),
    PERFORMER_REQUEST("performer_request", "演者要望");

    companion object {
        fun of(raw: String?): CallEmphasis = entries.firstOrNull { it.raw == raw } ?: NORMAL
    }
}

/** コールを出すタイミング。既定は追っかけ。 */
enum class CallTiming(val raw: String, val label: String) {
    OVER("over", "同時"), AFTER("after", "追っかけ");

    companion object {
        fun of(raw: String?): CallTiming = entries.firstOrNull { it.raw == raw } ?: AFTER
    }
}

/** 歌詞行の一部 (アンカー) に紐づくコール 1 件。位置は Unicode スカラー単位。 */
data class LyricCall(
    val id: String,
    val start: Int,
    val end: Int,
    val anchorText: String,
    val text: String,
    val emphasis: CallEmphasis,
    val timing: CallTiming,
    val stale: Boolean,
    /** コールを出す再生位置 (ms)。 */
    val startMs: Int?,
) {
    /** 歌詞の一部に掛かる (範囲を持つ) コールか。false は行末の追っかけ (幅ゼロ)。 */
    val hasAnchor: Boolean get() = end > start
    val isOverlapping: Boolean get() = timing == CallTiming.OVER && hasAnchor

    companion object {
        fun parse(o: JSONObject) = LyricCall(
            id = o.optString("id"),
            start = o.optInt("start", 0),
            end = o.optInt("end", 0),
            anchorText = o.optString("anchorText", ""),
            text = o.optString("text", ""),
            emphasis = CallEmphasis.of(o.optStringOrNull("emphasis")),
            timing = CallTiming.of(o.optStringOrNull("timing")),
            stale = o.optBoolean("stale", false),
            startMs = o.optIntOrNull("startMs"),
        )
    }
}

/** 歌詞 1 行。 */
data class LyricLine(
    val id: String,
    val ord: Int,
    val kind: LyricLineKind,
    val text: String,
    val section: String?,
    /** 再生位置 (ms)。タイミング編集で記録する。 */
    val startMs: Int?,
    val clap: LyricClap?,
    /** 配列順が表示順。並べ替えないこと。 */
    val calls: List<LyricCall>,
    /** みんなの「ここ好き」の人数。 */
    val likeCount: Int,
    /** 被せの指定 ("overlay" / "main")。null なら括弧で決める (コアの lyricIsOverlayLine)。 */
    val layer: String?,
    /** パート分け: この行を歌うアイドルの id。空ならまだ分けていない。 */
    val singers: List<String> = emptyList(),
    /** 行の途中で歌う人が変わるところ (`at` から後ろを `singers` が歌う。昇順)。 */
    val partBreaks: List<LyricLinePartBreak> = emptyList(),
) {
    /** 被せの行か (歌詞プレイヤーで 2 段目に出す行)。判定はコア。 */
    val isOverlay: Boolean
        get() = kind != LyricLineKind.BLANK && uniffi.imas_core.lyricIsOverlayLine(text, layer)

    /** 行を歌う人をぜんぶ (出てくる順)。脇の色の帯・ロック画面に使う。規則はコア。 */
    val allSingers: List<String>
        get() = if (partBreaks.isEmpty()) singers else lyricPartUnion(singers, partBreaks.map { it.core })

    /** 行を歌う人ごとのひと続き (区切りが無ければ行まるごと 1 つ)。規則はコア。 */
    val partSegments: List<LyricPartSegment>
        get() = lyricPartSegments(text.codePointCount(0, text.length).toUInt(), singers, partBreaks.map { it.core })

    /** この行のコールが、掛かっている歌詞と同じ文字か (同時、または歌詞の被せの括弧の中に掛かっている)。
     * 閲覧では行に並べず、歌詞のその部分に印を付ける (同じ文字を 2 回出さない)。判定はコア。 */
    fun echoes(call: LyricCall): Boolean =
        call.hasAnchor && lyricCallEchoesLine(text, call.start.toUInt(), call.end.toUInt(), call.text, call.timing.raw)

    companion object {
        fun parse(o: JSONObject) = LyricLine(
            id = o.optString("id"),
            ord = o.optInt("ord", 0),
            kind = LyricLineKind.of(o.optStringOrNull("kind")),
            text = o.optString("text", ""),
            section = o.optStringOrNull("section"),
            startMs = o.optIntOrNull("startMs"),
            clap = LyricClap.of(o.optStringOrNull("clap")),
            calls = o.optJSONArray("calls").objects().map(LyricCall::parse),
            likeCount = o.optInt("likeCount", 0),
            layer = o.optStringOrNull("layer"),
            singers = o.optJSONArray("singers").objectsAsStrings(),
            partBreaks = o.optJSONArray("partBreaks").objects().map(LyricLinePartBreak::parse),
        )
    }
}

/** 行の途中で歌う人が変わるところ 1 つ (`at` は本文のコードポイント位置)。 */
data class LyricLinePartBreak(val at: Int, val singers: List<String>) {
    val core: LyricPartBreak get() = LyricPartBreak(at.toUInt(), singers)

    companion object {
        fun of(core: LyricPartBreak) = LyricLinePartBreak(core.at.toInt(), core.singers)
        fun parse(o: JSONObject) = LyricLinePartBreak(o.optInt("at", 0), o.optJSONArray("singers").objectsAsStrings())
    }
}

/** 歌詞の奥付 (`submittedBy`)。names は載せてよい人の表示名、total は投稿で公開した人の数。 */
data class LyricsCredit(val names: List<String>, val total: Int)

/** 1 曲分の歌詞。 */
data class Lyrics(
    val songId: String,
    /** 出典表記。 */
    val source: String?,
    val updatedAt: Long?,
    val lines: List<LyricLine>,
    val status: String?,
    /** 歌詞の奥付 (投稿で公開した人。名前は本人が載せると選んだ人だけ)。旧サーバは返さない。 */
    val submittedBy: LyricsCredit? = null,
) {
    val isDraft: Boolean get() = status == "draft"
    val hasContent: Boolean get() = lines.any { it.kind == LyricLineKind.LYRIC && it.text.isNotEmpty() }
    val hasCalls: Boolean get() = lines.any { it.calls.isNotEmpty() }

    /** 実際に使われている強調度 (通常を除く)。凡例はここからだけ作る。 */
    val usedEmphases: List<CallEmphasis>
        get() {
            val used = lines.flatMap { it.calls }.map { it.emphasis }.toSet()
            return CallEmphasis.entries.filter { it != CallEmphasis.NORMAL && it in used }
        }
    val usesOverTiming: Boolean get() = lines.any { l -> l.calls.any { it.isOverlapping } }
    val usedClaps: List<LyricClap>
        get() {
            val used = lines.mapNotNull { it.clap }.toSet()
            return LyricClap.entries.filter { it in used }
        }

    /** 表示順の各行の開始 ms (コアに渡す形)。 */
    val startsForCore: List<Long?> get() = lines.map { it.startMs?.toLong() }

    companion object {
        fun parse(o: JSONObject, fallbackSongId: String) = Lyrics(
            songId = o.optStringOrNull("songId")?.takeIf { it.isNotEmpty() } ?: fallbackSongId,
            source = o.optStringOrNull("source"),
            updatedAt = if (o.isNull("updatedAt")) null else o.optLong("updatedAt"),
            lines = o.optJSONArray("lines").objects().map(LyricLine::parse),
            status = o.optStringOrNull("status"),
            submittedBy = o.optJSONObject("submittedBy")?.let { c ->
                LyricsCredit(
                    names = c.optJSONArray("names")?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList(),
                    total = c.optInt("total")
                )
            },
        )
    }
}

private fun JSONObject.optStringOrNull(key: String): String? =
    if (!has(key) || isNull(key)) null else optString(key)

private fun JSONObject.optIntOrNull(key: String): Int? =
    if (!has(key) || isNull(key)) null else optInt(key)

private fun JSONArray?.objects(): List<JSONObject> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

private fun JSONArray?.objectsAsStrings(): List<String> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optString(it, null) }
