package com.fugaif.imaslivedb.data.sync

/**
 * CloudKit Web Services の1レコードを表す軽量モデル。
 * fields は CloudKit の {"value": X, "type": ...} を value だけに平坦化した map。
 */
data class CkRecord(
    val recordName: String,
    val fields: Map<String, Any?>
) {
    fun str(key: String): String? = (fields[key] as? String)?.takeIf { it.isNotEmpty() }
    fun int(key: String): Int = (fields[key] as? Number)?.toInt() ?: 0
    fun intOrNull(key: String): Int? = (fields[key] as? Number)?.toInt()
    fun double(key: String): Double? = (fields[key] as? Number)?.toDouble()
    fun bool(key: String, default: Boolean = false): Boolean = when (val v = fields[key]) {
        is Boolean -> v
        is Number -> v.toLong() != 0L
        else -> default
    }

    /** soft delete マーカー (TIMESTAMP)。存在すれば削除レコード。 */
    val isDeleted: Boolean get() = fields["deletedAt"] != null
}
