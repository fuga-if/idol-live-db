package com.fugaif.imaslivedb.ui.theme

import com.fugaif.imaslivedb.data.model.PerformerRow
import uniffi.imas_core.PerformerDisplayName
import uniffi.imas_core.PerformerNameMode
import uniffi.imas_core.SetlistPerformerRecord
import uniffi.imas_core.performerDisplayName

/**
 * セトリの歌唱者をどの名前で出すか — 閲覧者の好み (iOS `PerformerNameSetting` と 1:1)。
 *
 * **規則は持たない。** どちらを主にしてどちらを併記するかは imas-core の
 * [performerDisplayName] が決めており、ここが持つのは保存の形と選択肢のラベルだけ。
 *
 * 保存値は [raw] の文字列で固定する。序数で保存すると、選択肢を並べ替えた瞬間に
 * 既存ユーザーの設定が別のものに化ける。
 */
enum class PerformerNameSetting(val raw: String, val label: String) {
    /** アイドル名だけ。既定 (これまでの表示と同じ)。 */
    IDOL("idol", "アイドル名"),

    /** 現任 CV 名だけ。 */
    CAST("cast", "CV名"),

    /** アイドル名 + CV 名。 */
    BOTH("both", "アイドル名 + CV名"),

    /** 公演に合わせる (キャラライブ = アイドル名 / 声優ライブ = CV 名)。 */
    SHOW("show", "公演に合わせる");

    /** コアの列挙への対応。 */
    val mode: PerformerNameMode
        get() = when (this) {
            IDOL -> PerformerNameMode.IDOL_ONLY
            CAST -> PerformerNameMode.CAST_ONLY
            BOTH -> PerformerNameMode.BOTH
            SHOW -> PerformerNameMode.FOLLOW_SHOW
        }

    companion object {
        /** 保存値から復元する。未知の値・未設定は既定 ([IDOL])。 */
        fun from(raw: String?): PerformerNameSetting =
            entries.firstOrNull { it.raw == raw } ?: IDOL
    }
}

/**
 * コアに渡す形。[PerformerRow.name] は SQL 側で現任 CV に解決済みの表示名。
 *
 * `idolId` が null なのはアイドル行に紐づかない演者 (ゲスト等)。その場合は
 * アイドル名も CV 名も同じ文字列になり、どのモードでも同じ名前が出る。
 */
private fun PerformerRow.toRecord(): SetlistPerformerRecord = SetlistPerformerRecord(
    idolId = idolId ?: id,
    displayName = name,
    idolName = idolName ?: name,
    idolColor = idolColor
)

/** 選んだモードでの表示名 (主と、必要なら副)。 */
fun PerformerRow.displayName(
    setting: PerformerNameSetting,
    isCharacterLive: Boolean
): PerformerDisplayName = performerDisplayName(toRecord(), setting.mode, isCharacterLive)

/**
 * 1 行に収めるときの表記。副があれば括弧で添える。
 *
 * 2 段に積める場所 (歌唱者チップ) では `primary` / `secondary` をそのまま出す。
 */
fun PerformerDisplayName.joined(): String =
    secondary?.let { "$primary($it)" } ?: primary
