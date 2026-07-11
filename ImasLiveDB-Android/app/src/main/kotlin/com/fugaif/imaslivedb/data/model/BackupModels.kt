package com.fugaif.imaslivedb.data.model

/**
 * 引き継ぎコード/ファイルエクスポートでやり取りするバックアップ本体。
 * iOS BackupService と同一スキーマ (JSON key はすべてこの camelCase のまま)。
 */
data class BackupPayload(
    val schemaVersion: Int,
    val exportedAt: String,
    val platform: String,
    val appVersion: String,
    val deviceId: String,
    val userMarks: List<BackupUserMark>,
    val pollVotes: List<BackupPollVote>,
    val personalTags: List<BackupPersonalTag>
)

data class BackupUserMark(
    val entityType: String,
    val entityId: String,
    /** iOS 表記 (myPick/favorite/attended/note/collected/seat/owned) の canonical kind。 */
    val kind: String,
    val boolValue: Boolean,
    val textValue: String?,
    val updatedAt: String
)

data class BackupPollVote(
    val pollId: String,
    val entityIds: List<String>
)

/** 個人用タグ (端末ローカル専用、サーバーには送信しないがバックアップ/引き継ぎコードの対象にはなる)。 */
data class BackupPersonalTag(
    val entityType: String,
    val entityId: String,
    val tagName: String,
    val createdAt: String
)

/** Android 内部表記 (pick/memo 等) → iOS と共通の canonical kind。 */
fun UserMark.toCanonicalKind(): String = when (kind) {
    UserMark.PICK -> "myPick"
    UserMark.MEMO -> "note"
    else -> kind // favorite / attended は共通表記
}

/**
 * canonical kind → Android 内部表記。
 * Android がサポートしない kind (collected/seat/owned 等、iOS 専用) はそのまま (opaque な) 値として
 * 保存する。`user_marks.kind` は CHECK 制約の無い String 列で、既存クエリは PICK/FAVORITE/ATTENDED/MEMO
 * を明示的に指定してフィルタするため未知 kind の行が混ざっても無害。Android の UI では使われないが、
 * 次に iOS へ再エクスポートするときに [toCanonicalKind] でそのまま復元できる (静かなデータ消失を防ぐ)。
 */
fun canonicalKindToAndroid(canonical: String): String = when (canonical) {
    "myPick" -> UserMark.PICK
    "note" -> UserMark.MEMO
    else -> canonical // favorite/attended はそのまま一致。collected/seat/owned 等は opaque pass-through
}
