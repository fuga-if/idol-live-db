package com.fugaif.imaslivedb.data.backup

import com.fugaif.imaslivedb.data.model.ReceivedCardMeeting
import uniffi.imas_core.BackupCardMeetingRecord
import android.content.Context
import android.content.pm.PackageManager
import androidx.room.withTransaction
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.Playlist
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.ExpenseRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.PlaylistRepository
import com.fugaif.imaslivedb.data.repository.ProducerCardRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import uniffi.imas_core.BackupExpenseRecord
import uniffi.imas_core.BackupExportInput
import uniffi.imas_core.BackupImportException
import uniffi.imas_core.BackupKindDialect
import uniffi.imas_core.BackupLocalState
import uniffi.imas_core.BackupMarkKey
import uniffi.imas_core.BackupMyProducerCardRecord
import uniffi.imas_core.BackupPersonalTagRecord
import uniffi.imas_core.BackupPlaylistRecord
import uniffi.imas_core.BackupPollVoteRecord
import uniffi.imas_core.BackupProducerCardRecord
import uniffi.imas_core.BackupTagKey
import uniffi.imas_core.BackupUserMarkRecord
import uniffi.imas_core.backupCurrentSchemaVersion
import uniffi.imas_core.buildBackupEnvelope
import uniffi.imas_core.planBackupImport
import java.time.Instant
import com.fugaif.imaslivedb.data.local.BrandRoleStore

/** バックアップ (引き継ぎコード/ファイルエクスポート) で壊れた・改ざんされたデータを検出したときに投げる。 */
class BackupFormatException(message: String) : Exception(message)

data class BackupImportResult(
    val addedMarks: Int,
    val addedVotes: Int,
    val addedPersonalTags: Int,
    val addedExpenses: Int,
    val addedPlaylists: Int,
    val addedProducerCards: Int = 0,
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
        personalTagRepository: PersonalTagRepository,
        expenseRepository: ExpenseRepository,
        playlistRepository: PlaylistRepository,
        producerCardRepository: ProducerCardRepository
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
            },
            // 収支も端末にしか無いデータなので、機種変で置いていかない。
            expenses = expenseRepository.getAll().map {
                BackupExpenseRecord(it.id, it.date, it.category, it.amount, it.showId, it.eventId, it.note, it.ticketKind, it.updatedAt)
            },
            // プレイリストも端末ローカル唯一データ。
            playlists = playlistRepository.allForBackup().map { (playlist, songIds) ->
                BackupPlaylistRecord(playlist.id, playlist.name, playlist.createdAt, playlist.updatedAt, songIds)
            },
            // P名刺 (受け取った名刺と自分の名刺。名前の書体・自分の QR も) も端末にしか無い。写真・担当の画像は運ばない
            // (アイドルの画像と同じく端末の中だけ)。
            producerCards = producerCardRepository.meetings().groupBy { it.cardId }.let { meetingsByCard ->
                producerCardRepository.receivedCards().map { card ->
                    BackupProducerCardRecord(
                        card.id, card.payload, card.source, card.showId, card.showDate, card.memo, card.receivedAt,
                        card.updatedAt, via = card.via,
                        meetings = meetingsByCard[card.id].orEmpty().map {
                            BackupCardMeetingRecord(it.id, it.cardId, it.showId, it.showDate, it.via, it.metAt, it.payload)
                        }
                    )
                }
            },
            myProducerCards = listOfNotNull(producerCardRepository.myCard()).map {
                BackupMyProducerCardRecord(
                    it.id, it.name, it.message, it.sinceYear?.toLong(), it.linksJson, it.hiddenFields, it.updatedAt,
                    design = it.design, qrUrl = it.qrUrl, profileJson = it.profileJson, cardOshiJson = it.cardOshiJson,
                    cardId = it.cardId
                )
            },
            // 担当ブランドはアプリ全体の設定 (端末の SharedPreferences)。まだ決めていなければ空 (運ばない)。
            brandRolesJson = BrandRoleStore.json(context)
        )
        return buildBackupEnvelope(input, BackupKindDialect.ANDROID).envelopeJson
    }

    /**
     * @param database 端末の DB への書き込み (マーク・マイタグ・収支) を 1 トランザクションにするため。
     *   途中で止まって一部の表だけ入る、を防ぐ。
     */
    suspend fun importEnvelopeJson(
        context: Context,
        json: String,
        database: AppDatabase,
        userMarkRepository: UserMarkRepository,
        pollVoteLog: LocalPollVoteLog,
        personalTagRepository: PersonalTagRepository,
        expenseRepository: ExpenseRepository,
        playlistRepository: PlaylistRepository,
        producerCardRepository: ProducerCardRepository,
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
            },
            // 収支は id (UUID) で重複を見る。同じ id を 2 回入れると帳簿の額が倍になる。
            expenseIds = expenseRepository.allIds(),
            // プレイリストも id で重複を見る。
            playlistIds = playlistRepository.allIds(),
            producerCardIds = producerCardRepository.receivedIds(),
            myProducerCardIds = listOfNotNull(producerCardRepository.myCard()?.id),
            // 既にある受け取った名刺の id と中身 (中身が同じ別 id の名刺は入れず、その会った記録を既にある名刺に付け替える)。
            producerCards = producerCardRepository.receivedRefs(),
            cardMeetings = producerCardRepository.meetings().map {
                BackupCardMeetingRecord(it.id, it.cardId, it.showId, it.showDate, it.via, it.metAt, it.payload)
            },
            brandRolesJson = BrandRoleStore.json(context)
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
        // DB に入れる 3 つは 1 トランザクションにし、DB の外 (投票履歴・端末 ID) は入れ終えてから。
        val addedExpenses = database.withTransaction {
            userMarkRepository.restoreIfAbsent(
                plan.marksToInsert.map {
                    UserMark(it.entityType, it.entityId, it.kind, it.boolValue, it.textValue, it.updatedAt)
                }
            )
            personalTagRepository.restoreIfAbsent(
                plan.personalTagsToInsert.map {
                    PersonalTag(it.entityType, it.entityId, it.tagName, it.createdAt)
                }
            )
            expenseRepository.restoreIfAbsent(
                plan.expensesToInsert.map {
                    Expense(it.id, it.date, it.category, it.amount, it.showId, it.eventId, it.note, it.updatedAt, it.ticketKind)
                }
            )
        }
        // プレイリストは playlist_items も一緒に書くので expenses 等とは別のトランザクションに分けず、
        // repository 内で 1 件ずつ Room の @Transaction にする (DAO.insertIfAbsent)。
        val addedPlaylists = playlistRepository.restoreIfAbsent(
            plan.playlistsToInsert.map {
                Playlist(it.id, it.name, it.createdAt, it.updatedAt) to it.songIds
            }
        )
        // P名刺は id と中身で重複を見て、無いものだけ足す (メモを古いもので上書きしない)。
        val addedProducerCards = producerCardRepository.restoreReceivedIfAbsent(
            plan.producerCardsToInsert.map {
                ReceivedProducerCard(
                    it.id, it.payload, it.source, it.showId, it.showDate, it.memo, it.receivedAt, it.updatedAt,
                    via = it.via
                )
            }
        )
        // 会った記録は名刺の後 (名刺が端末に無い記録は飛ばす。中身が同じ別 id の名刺の記録はコアが付け替え済み)。
        producerCardRepository.restoreMeetingsIfAbsent(
            plan.cardMeetingsToInsert.map {
                ReceivedCardMeeting(it.id, it.cardId, it.showId, it.showDate, it.via, it.metAt, it.payload)
            }
        )
        producerCardRepository.restoreMyCardIfAbsent(
            plan.myProducerCardsToInsert.map {
                MyProducerCard(
                    it.id, it.name, it.message, it.sinceYear?.toInt(), it.linksJson, it.hiddenFields, it.updatedAt,
                    design = it.design, qrUrl = it.qrUrl, profileJson = it.profileJson, cardOshiJson = it.cardOshiJson,
                    cardId = it.cardId
                )
            }
        )
        pollVoteLog.mergeIfAbsent(plan.pollVotesToAdd.associate { it.pollId to it.entityIds.toSet() })
        // 担当ブランドは端末の設定に担当・メインが 1 つも無いときだけ (コアが決める)。
        if (plan.brandRolesJsonToRestore.isNotEmpty()) BrandRoleStore.restore(context, plan.brandRolesJsonToRestore)
        if (plan.restoreDeviceId) DeviceIdentity.restore(context, plan.info.deviceId)

        return BackupImportResult(
            addedMarks = plan.addedMarks.toInt(),
            addedVotes = plan.addedVotes.toInt(),
            addedPersonalTags = plan.addedPersonalTags.toInt(),
            // 件数は書き込み側の戻り値を正とする (「入っていないのに入ったと言う」事故が起きない)。
            addedExpenses = addedExpenses,
            addedPlaylists = addedPlaylists,
            addedProducerCards = addedProducerCards,
            deviceIdRestored = plan.restoreDeviceId,
            // コアは marks 以外 (投票・マイタグ・収支・プレイリスト) の壊れた要素も数える。旧実装は marks だけ
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
