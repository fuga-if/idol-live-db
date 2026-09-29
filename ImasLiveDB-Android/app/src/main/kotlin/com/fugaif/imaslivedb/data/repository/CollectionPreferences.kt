package com.fugaif.imaslivedb.data.repository

/**
 * 回収に配信参加も含めるか (既定 = 現地参加のみ)。設定「配信参加も回収に含める」の現在値。
 *
 * 保存先 ([com.fugaif.imaslivedb.ui.theme.AppPreferences]) は Context を要るため、
 * リポジトリ層からは読みに行かず ui 側が起動時・変更時に**押し込む** (data → ui の
 * 逆向き依存を作らずに済ませるための向き)。[UserMarkRepository] だけでなく
 * [SongRepository] / [EventRepository] も回収の判定 (`CollectionAttendance`) で
 * この値を使うため、特定リポジトリのインスタンスに閉じ込めず共有の置き場にした。
 */
object CollectionPreferences {
    @Volatile
    var includeStream: Boolean = false
}
