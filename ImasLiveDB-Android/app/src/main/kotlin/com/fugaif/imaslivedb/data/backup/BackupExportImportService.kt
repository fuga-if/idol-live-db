package com.fugaif.imaslivedb.data.backup

import android.content.Context
import android.content.pm.PackageManager
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import uniffi.imas_core.BackupExportInput
import uniffi.imas_core.BackupImportException
import uniffi.imas_core.BackupKindDialect
import uniffi.imas_core.BackupLocalState
import uniffi.imas_core.BackupMarkKey
import uniffi.imas_core.BackupPersonalTagRecord
import uniffi.imas_core.BackupPollVoteRecord
import uniffi.imas_core.BackupTagKey
import uniffi.imas_core.BackupUserMarkRecord
import uniffi.imas_core.backupCurrentSchemaVersion
import uniffi.imas_core.buildBackupEnvelope
import uniffi.imas_core.planBackupImport
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
 *
 * envelope の**組み立て規則と整合判定**は共有コア (`domain::backup_summary`) が持つ。
 * payload のシリアライズと checksum を同じ関数の中で作るので、「どうシリアライズしたか」と
 * 「何をハッシュしたか」がズレて自分の書いたファイルを自分で読めなくなる事故が起きない。
 * ここに残るのはファイル/サーバとの授受・SharedPreferences・SQLite への書き込みだけ。
 *
 * `kind` の表記ゆれ (iOS の myPick/note ↔ Android の pick/memo) も
 * [BackupKindDialect.ANDROID] を渡してコア側で閉じる。読み替えを呼び出し側でやると
 * 「ローカル既存キーの kind」と「バックアップの kind」が食い違って重複判定が静かに壊れる
 * (担当が二重に入る/入らない) ため。
 *
 * インポートは常に非破壊マージ (ローカルの既存データを上書き・削除しない)。
 */
object BackupExportImportService {
    /** コアが書き出す payload の schemaVersion (両 OS 共通)。 */
    val CURRENT_SCHEMA_VERSION: Int get() = backupCurrentSchemaVersion().toInt()

    suspend fun buildEnvelopeJson(
        context: Context,
        userMarkRepository: UserMarkRepository,
        pollVoteLog: LocalPollVoteLog,
        personalTagRepository: PersonalTagRepository
    ): String {
        val input = BackupExportInput(
            // OS 時刻・端末 ID・アプリ版はコアが取らない規約なのでここで渡す。
            exportedAt = Instant.now().toString(),
            platform = "android",
            appVersion = appVersion(context),
            deviceId = DeviceIdentity.get(context),
            // kind は DB 表記のまま渡す (canonical への読み替えはコアの仕事)。
            userMarks = userMarkRepository.getAll().map {
                BackupUserMarkRecord(it.entityType, it.entityId, it.kind, it.boolValue, it.textValue, it.updatedAt)
            },
            pollVotes = pollVoteLog.allEntries().map { (pollId, entityIds) ->
                BackupPollVoteRecord(pollId, entityIds.toList())
            },
            personalTags = personalTagRepository.getAll().map {
                BackupPersonalTagRecord(it.entityType, it.entityId, it.tagName, it.createdAt)
            }
        )
        return buildBackupEnvelope(input, BackupKindDialect.ANDROID).envelopeJson
    }

    suspend fun importEnvelopeJson(
        context: Context,
        json: String,
        userMarkRepository: UserMarkRepository,
        pollVoteLog: LocalPollVoteLog,
        personalTagRepository: PersonalTagRepository,
        restoreDeviceId: Boolean
    ): BackupImportResult {
        val local = BackupLocalState(
            markKeys = userMarkRepository.getAll().map {
                BackupMarkKey(it.entityType, it.entityId, it.kind)
            },
            tagKeys = personalTagRepository.getAll().map {
                BackupTagKey(it.entityType, it.entityId, it.tagName)
            },
            pollVotes = pollVoteLog.allEntries().map { (pollId, entityIds) ->
                BackupPollVoteRecord(pollId, entityIds.toList())
            }
        )

        val plan = try {
            planBackupImport(json, local, restoreDeviceId, BackupKindDialect.ANDROID)
        } catch (e: BackupImportException) {
            // コアの例外は列挙値だけを運ぶので、ユーザーに出す文面はここで当てる
            // (SettingsScreen が e.message をそのまま表示する)。
            throw BackupFormatException(userMessage(e))
        }

        // 追加すべき行はコアが絞り込み済み。repository 側の restoreIfAbsent は
        // 既存キーとの突き合わせをもう一度行うだけで結果は変わらない (非破壊・冪等)。
        userMarkRepository.restoreIfAbsent(
            plan.marksToInsert.map {
                UserMark(it.entityType, it.entityId, it.kind, it.boolValue, it.textValue, it.updatedAt)
            }
        )
        pollVoteLog.mergeIfAbsent(plan.pollVotesToAdd.associate { it.pollId to it.entityIds.toSet() })
        personalTagRepository.restoreIfAbsent(
            plan.personalTagsToInsert.map {
                PersonalTag(it.entityType, it.entityId, it.tagName, it.createdAt)
            }
        )
        if (plan.restoreDeviceId) DeviceIdentity.restore(context, plan.info.deviceId)

        return BackupImportResult(
            addedMarks = plan.addedMarks.toInt(),
            addedVotes = plan.addedVotes.toInt(),
            addedPersonalTags = plan.addedPersonalTags.toInt(),
            deviceIdRestored = plan.restoreDeviceId,
            // コアは marks 以外 (投票・マイタグ) の壊れた要素も数える。旧実装は marks だけ
            // 数えていたので、壊れたファイルでの表示件数がその分だけ増えることがある。
            skippedMarks = plan.info.skippedEntries.toInt()
        )
    }

    private fun userMessage(e: BackupImportException): String = when (e) {
        is BackupImportException.MalformedFile -> "壊れたファイルです"
        is BackupImportException.ChecksumMismatch -> "データが破損しているか改ざんされている可能性があります"
        is BackupImportException.UnsupportedSchemaVersion -> "新しいバージョンのアプリで作成されたファイルです"
    }

    private fun appVersion(context: Context): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "unknown"
    } catch (e: PackageManager.NameNotFoundException) {
        "unknown"
    }
}
