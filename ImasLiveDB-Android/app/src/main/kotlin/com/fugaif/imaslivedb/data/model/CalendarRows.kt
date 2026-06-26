package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo

/** カレンダー用: 月内の公演 (イベント名・ブランド付き)。 */
data class CalShowRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "show_name") val showName: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "event_name") val eventName: String,
    @ColumnInfo(name = "brand_id") val brandId: String?
)

/** カレンダー用: 月内にリリースされた曲。 */
data class CalReleaseRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "release_date") val releaseDate: String,
    @ColumnInfo(name = "brand_id") val brandId: String?
)

/** カレンダー用: 月内に誕生日を迎えるアイドル。 */
data class CalBirthdayRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "brand_id") val brandId: String,
    @ColumnInfo(name = "birthday") val birthday: String
)
