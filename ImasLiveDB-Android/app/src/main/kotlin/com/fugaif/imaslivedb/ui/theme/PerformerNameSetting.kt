package com.fugaif.imaslivedb.ui.theme

import com.fugaif.imaslivedb.data.model.PerformerRow
import uniffi.imas_core.PerformerDisplayName
import uniffi.imas_core.PerformerNameMode
import uniffi.imas_core.PerformerNameOption
import uniffi.imas_core.SetlistPerformerRecord
import uniffi.imas_core.performerDisplayName
import uniffi.imas_core.performerDisplayNameJoined
import uniffi.imas_core.performerNameModeFromRaw
import uniffi.imas_core.performerNameOptions

/**
 * セトリの歌唱者をどの名前で出すか — 閲覧者の好み (iOS `PerformerNamePref` と 1:1)。
 *
 * **モードの列挙もラベルも保存値もここに無い。** 順・raw・文言はすべて imas-core の
 * [performerNameOptions] が持ち、主/副の決め方は [performerDisplayName] が持つ。
 * ここにあるのは保存先の鍵と、[PerformerRow] をコアの Record へ移す配管だけ。
 *
 * 4 モードを Kotlin の enum に書き写していた頃は、同じラベルが
 * Swift / Kotlin / TS に 3 本あった (文言を直すと 1 面だけ古いまま残る)。
 */
object PerformerNamePref {
    /** SharedPreferences の鍵。iOS / Android / Web で同じ文字列を使う。 */
    const val STORAGE_KEY = "performer_name_mode"

    /** 設定画面に並べる選択肢 (順・保存値・文言)。 */
    val options: List<PerformerNameOption> by lazy { performerNameOptions() }

    /** 未設定のときの保存値。コアの既定モードに対応する raw。 */
    val defaultRaw: String by lazy {
        val fallback = performerNameModeFromRaw(null)
        options.firstOrNull { it.mode == fallback }?.raw.orEmpty()
    }

    /** 保存値からモードへ。未知の値・未設定は既定 (アイドル名)。 */
    fun mode(raw: String?): PerformerNameMode = performerNameModeFromRaw(raw)
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
    mode: PerformerNameMode,
    isCharacterLive: Boolean
): PerformerDisplayName = performerDisplayName(toRecord(), mode, isCharacterLive)

/**
 * 2 段に積めない場所 (簡易表示・共有文) 向けの 1 行表記。
 * 括弧の書き方はコアが決める (端末ごとに違う見た目にしない)。
 */
fun PerformerDisplayName.joined(): String = performerDisplayNameJoined(this)
