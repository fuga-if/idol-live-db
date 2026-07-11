package com.fugaif.imaslivedb.data.backup

import android.content.Context
import android.content.pm.PackageManager
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.model.BackupPollVote
import com.fugaif.imaslivedb.data.model.BackupUserMark
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.model.canonicalKindToAndroid
import com.fugaif.imaslivedb.data.model.toCanonicalKind
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.time.Instant

/** バックアップ (引き継ぎコード/ファイルエクスポート) で壊れた・改ざんされたデータを検出したときに投げる。 */
class BackupFormatException(message: String) : Exception(message)

data class BackupImportResult(
    val addedMarks: Int,
    val addedVotes: Int,
    val addedPersonalTags: Int,
    val deviceIdRestored: Boolean,
    val skippedMarks: Int
)

/**
 * お気に入り/担当/投票履歴を JSON envelope にまとめてエクスポート/インポートする。
 * envelope 形式は iOS BackupService と共通 (checksum で改ざん検知、payload はネストした JSON 文字列)。
 * インポートは常に非破壊マージ (ローカルの既存データを上書き・削除しない)。
 */
object BackupExportImportService {
    const val CURRENT_SCHEMA_VERSION = 1
    private const val ENVELOPE_VERSION = 1

    suspend fun buildEnvelopeJson(
        context: Context,
        userMarkRepository: UserMarkRepository,
        pollVoteLog: LocalPollVoteLog,
        personalTagRepository: PersonalTagRepository
    ): String {
        val marks = userMarkRepository.getAll()
        val marksJson = JSONArray()
        marks.forEach { mark ->
            val o = JSONObject()
                .put("entityType", mark.entityType)
                .put("entityId", mark.entityId)
                .put("kind", mark.toCanonicalKind())
                .put("boolValue", mark.boolValue)
                .put("updatedAt", mark.updatedAt)
            mark.textValue?.let { o.put("textValue", it) }
            marksJson.put(o)
        }

        val votesJson = JSONArray()
        pollVoteLog.allEntries().forEach { (pollId, entityIds) ->
            votesJson.put(
                JSONObject()
                    .put("pollId", pollId)
                    .put("entityIds", JSONArray(entityIds.sorted()))
            )
        }

        val personalTagsJson = JSONArray()
        personalTagRepository.getAll().forEach { tag ->
            personalTagsJson.put(
                JSONObject()
                    .put("entityType", tag.entityType)
                    .put("entityId", tag.entityId)
                    .put("tagName", tag.tagName)
                    .put("createdAt", tag.createdAt)
            )
        }

        val payload = JSONObject()
            .put("schemaVersion", CURRENT_SCHEMA_VERSION)
            .put("exportedAt", Instant.now().toString())
            .put("platform", "android")
            .put("appVersion", appVersion(context))
            .put("deviceId", DeviceIdentity.get(context))
            .put("userMarks", marksJson)
            .put("pollVotes", votesJson)
            .put("personalTags", personalTagsJson)

        val payloadString = payload.toString()
        val envelope = JSONObject()
            .put("envelopeVersion", ENVELOPE_VERSION)
            .put("checksum", "sha256:${sha256Hex(payloadString)}")
            .put("payload", payloadString)
        return envelope.toString()
    }

    suspend fun importEnvelopeJson(
        context: Context,
        json: String,
        userMarkRepository: UserMarkRepository,
        pollVoteLog: LocalPollVoteLog,
        personalTagRepository: PersonalTagRepository,
        restoreDeviceId: Boolean
    ): BackupImportResult {
        val envelope = try {
            JSONObject(json)
        } catch (e: Exception) {
            throw BackupFormatException("壊れたファイルです")
        }

        val payloadString = envelope.optString("payload", "")
        val checksum = envelope.optString("checksum", "")
        if (payloadString.isEmpty() || checksum.isEmpty()) {
            throw BackupFormatException("壊れたファイルです")
        }
        val expectedChecksum = "sha256:${sha256Hex(payloadString)}"
        if (checksum != expectedChecksum) {
            throw BackupFormatException("データが破損しているか改ざんされている可能性があります")
        }

        val payload = try {
            JSONObject(payloadString)
        } catch (e: Exception) {
            throw BackupFormatException("壊れたファイルです")
        }

        val schemaVersion = try {
            payload.getInt("schemaVersion")
        } catch (e: Exception) {
            throw BackupFormatException("壊れたファイルです")
        }
        if (schemaVersion > CURRENT_SCHEMA_VERSION) {
            throw BackupFormatException("新しいバージョンのアプリで作成されたファイルです")
        }

        var skippedMarks = 0
        val marksArr = payload.optJSONArray("userMarks") ?: JSONArray()
        val marks = (0 until marksArr.length()).mapNotNull { i ->
            try {
                val o = marksArr.getJSONObject(i)
                val entityType = o.getString("entityType")
                val entityId = o.getString("entityId")
                val androidKind = canonicalKindToAndroid(o.getString("kind"))
                val boolValue = o.getBoolean("boolValue")
                val textValue = if (o.has("textValue") && !o.isNull("textValue")) o.getString("textValue") else null
                val updatedAt = o.getString("updatedAt")
                UserMark(entityType, entityId, androidKind, boolValue, textValue, updatedAt)
            } catch (e: Exception) {
                skippedMarks++
                null
            }
        }
        val addedMarks = userMarkRepository.restoreIfAbsent(marks)

        val votesArr = payload.optJSONArray("pollVotes") ?: JSONArray()
        val voteEntries = mutableMapOf<String, Set<String>>()
        (0 until votesArr.length()).forEach { i ->
            try {
                val o = votesArr.getJSONObject(i)
                val pollId = o.getString("pollId")
                val idsArr = o.getJSONArray("entityIds")
                val entityIds = (0 until idsArr.length()).map { idsArr.getString(it) }.toSet()
                voteEntries[pollId] = (voteEntries[pollId] ?: emptySet()) + entityIds
            } catch (e: Exception) {
                // 壊れたエントリはスキップ (全体は中断しない)
            }
        }
        val addedVotes = pollVoteLog.mergeIfAbsent(voteEntries)

        val personalTagsArr = payload.optJSONArray("personalTags") ?: JSONArray()
        val personalTags = (0 until personalTagsArr.length()).mapNotNull { i ->
            try {
                val o = personalTagsArr.getJSONObject(i)
                PersonalTag(
                    entityType = o.getString("entityType"),
                    entityId = o.getString("entityId"),
                    tagName = o.getString("tagName"),
                    createdAt = o.getString("createdAt")
                )
            } catch (e: Exception) {
                null
            }
        }
        val addedPersonalTags = personalTagRepository.restoreIfAbsent(personalTags)

        var deviceIdRestored = false
        if (restoreDeviceId) {
            val deviceId = payload.optString("deviceId", "")
            if (deviceId.isNotEmpty()) {
                DeviceIdentity.restore(context, deviceId)
                deviceIdRestored = true
            }
        }

        return BackupImportResult(
            addedMarks = addedMarks,
            addedVotes = addedVotes,
            addedPersonalTags = addedPersonalTags,
            deviceIdRestored = deviceIdRestored,
            skippedMarks = skippedMarks
        )
    }

    private fun appVersion(context: Context): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "unknown"
    } catch (e: PackageManager.NameNotFoundException) {
        "unknown"
    }

    private fun sha256Hex(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
