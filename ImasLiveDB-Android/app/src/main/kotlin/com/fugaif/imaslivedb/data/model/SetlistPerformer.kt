package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "setlist_performers",
    primaryKeys = ["setlist_item_id", "idol_id"],
    indices = [
        Index(name = "idx_setlist_performers_item", value = ["setlist_item_id"]),
        Index(name = "idx_setlist_performers_idol", value = ["idol_id"])
    ]
)
data class SetlistPerformer(
    @ColumnInfo(name = "setlist_item_id")
    val setlistItemId: String,

    @ColumnInfo(name = "idol_id")
    val idolId: String
)
