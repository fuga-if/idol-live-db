import Foundation

// MARK: - Backup payload (iOS/Android共通契約)

/// 1 お題ぶんの投票履歴。`LocalPollVoteLog` の永続化と共有コアの射影の間の受け渡しに使う。
/// フィールド名はプラットフォーム間の共通契約のため camelCase 固定。
struct BackupPollVote: Codable {
    var pollId: String
    var entityIds: [String]
}

// MARK: - Errors / Result

enum BackupError: LocalizedError {
    case malformedFile
    case checksumMismatch
    case unsupportedSchemaVersion(Int)

    /// 共有コアの中断理由を、これまでどおりの日本語文面に載せ替える。
    /// 生成バインディングの `BackupImportError` は `errorDescription` が
    /// `String(reflecting:)` (= `ImasLiveDB.BackupImportError.MalformedFile`) なので、
    /// そのまま画面に出すと英語の型名が見えてしまう。
    ///
    /// 対応は 1:1 だが、「どの中断理由になるか」が旧実装と 1 箇所だけ違う
    /// (空文字 checksum が `.checksumMismatch` でなく `.malformedFile` に落ちる)。
    /// 詳細は `importEnvelopeJSON` の「旧 iOS 実装との意図的な差分」を参照。
    init(_ error: BackupImportError) {
        switch error {
        case .MalformedFile:                        self = .malformedFile
        case .ChecksumMismatch:                     self = .checksumMismatch
        case .UnsupportedSchemaVersion(let found):  self = .unsupportedSchemaVersion(Int(found))
        }
    }

    var errorDescription: String? {
        switch self {
        case .malformedFile:
            return "ファイルの形式が正しくありません"
        case .checksumMismatch:
            return "データが破損しています"
        case .unsupportedSchemaVersion(let v):
            return "対応していないバックアップ形式です (schemaVersion: \(v))"
        }
    }
}

struct BackupImportResult {
    var addedMarks: Int
    var addedVotes: Int
    var addedPersonalTags: Int
    var deviceIdRestored: Bool
    var skippedMarks: Int
}

// MARK: - BackupExportImportService

/// バックアップ (ファイル書き出し / 引き継ぎコード) の書き出しと取り込み。
///
/// payload と envelope の**組み立て規則・checksum・整合判定・重複判定**は
/// imas-core (Rust) の `domain/backup_summary.rs`。担当・お気に入り・メモ・参加は
/// クラウドにもサーバにも無い端末唯一データで、取り込み規則を 1bit 間違えると
/// ユーザーのデータが壊れるため、境界 (空・未知バージョン・重複 id・不正 JSON) は
/// そちらでテスト固定してある。checksum を payload と同じ関数の中で作るのも
/// 「シリアライズした文字列」と「ハッシュした文字列」がズレないようにするため。
///
/// ここに残すのは OS 側の責務だけ:
/// ファイル IO・DB 読み書き・UserDefaults (投票履歴)・端末 ID の保存。
/// 取り込みは**非破壊**を維持する: 共有コアが決めた「ローカルに無い行」だけを、
/// これまでどおり `restore...IfAbsent` 経由で追加する (既存行は上書きも削除もしない)。
@MainActor
enum BackupExportImportService {
    /// このアプリが書き出す payload の schemaVersion (共有コアと同値)。
    static var currentSchemaVersion: Int { Int(backupCurrentSchemaVersion()) }

    // MARK: Export

    /// ローカルの担当/投票/マイタグを射影して共有コアに渡し、envelope 込みの JSON 文字列を得る。
    static func buildEnvelopeJSON(database: AppDatabase) throws -> String {
        let marks = try database.allUserMarks().map {
            BackupUserMarkRecord(
                entityType: $0.entityType,
                entityId: $0.entityId,
                kind: $0.kind,
                boolValue: $0.boolValue,
                textValue: $0.textValue,
                updatedAt: $0.updatedAt
            )
        }
        let votes = LocalPollVoteLog.shared.allEntries().map {
            BackupPollVoteRecord(pollId: $0.pollId, entityIds: $0.entityIds)
        }
        let personalTags = try database.allPersonalTags().map {
            BackupPersonalTagRecord(
                entityType: $0.entityType,
                entityId: $0.entityId,
                tagName: $0.tagName,
                createdAt: $0.createdAt
            )
        }

        // 時刻・アプリ版・端末 ID は OS からしか分からないので引数で渡す (共有コアは時刻を取らない)。
        let input = BackupExportInput(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            platform: "ios",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            deviceId: DeviceIdentity.shared,
            userMarks: marks,
            pollVotes: votes,
            personalTags: personalTags
        )
        // iOS の kind 表記 (UserMarkKind.rawValue) がそのまま JSON の canonical 表記。
        return buildBackupEnvelope(input: input, dialect: .canonical).envelopeJson
    }

    /// 一時ディレクトリにバックアップ JSON を書き出し、`ShareLink` 等で使える URL を返す。
    static func exportToFile(database: AppDatabase) throws -> URL {
        let json = try buildEnvelopeJSON(database: database)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "ImasLiveDB_backup_\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    // MARK: Import

    /// envelope JSON 文字列 (ローカルファイル/サーバー共通) をパースして復元する。
    /// 壊れた要素はスキップしてカウントする。checksum 不一致・schemaVersion 不整合は中断する。
    ///
    /// ## 旧 iOS 実装との意図的な差分 (この 3 つだけ挙動が変わる)
    ///
    /// 共有コアへ寄せた結果、次の 3 点は移送前と一致しない。いずれも
    /// 「取り込める件数が増える / 中断理由の文言が変わる」だけで、
    /// **既存のローカルデータを消す・上書きする方向の変化は無い** (取り込みは
    /// 従来どおり `restore...IfAbsent` の非破壊マージ)。
    ///
    /// 1. **配列に壊れた要素が混ざったとき、その 1 件だけ捨てる。**
    ///    旧実装の `topLevel["userMarks"] as? [[String: Any]]` は Swift の配列条件
    ///    キャストが全要素を検査するため、非辞書要素が 1 つでも混ざると
    ///    **キャストごと失敗して userMarks が丸ごと 0 件・skipped も 0**
    ///    (=「壊れていた」ことすら画面に出ない) だった。共有コアは要素ごとに読み、
    ///    健全な要素を取り込んで壊れた 1 件だけ `skippedMarks` に積む
    ///    (Android 原本と同じ)。固定テスト:
    ///    `domain::backup_summary::tests::mixed_arrays_are_read_element_wise_unlike_ios`。
    /// 2. **`envelopeVersion` キーが無いファイルを弾かない。**
    ///    旧実装は `JSONDecoder` が必須項目として弾き `.malformedFile` にしていたが、
    ///    この値は iOS も Android も読み取り時に一度も検査していない。検証できる
    ///    ファイルを版番号の有無だけで捨てないよう、読めたときだけ持ち回る。
    ///    固定テスト: `missing_envelope_version_is_tolerated`。
    /// 3. **`checksum` / `payload` が空文字のときの中断理由が変わる。**
    ///    旧実装は空文字でも比較まで進んで `.checksumMismatch`
    ///    (「データが破損しています」) を出していた。共有コアは空文字を「値が無い」と
    ///    見なすため `MalformedFile` になり、画面文言が
    ///    「ファイルの形式が正しくありません」に変わる。**中断する点は同じ**で、
    ///    checksum が非空で食い違う通常の破損は従来どおり `.checksumMismatch`。
    static func importEnvelopeJSON(
        _ json: String,
        database: AppDatabase,
        restoreDeviceId: Bool
    ) throws -> BackupImportResult {
        // ローカルの現状 (同一性キーだけ) を射影して渡す。何を追加すべきかは共有コアが決める。
        let local = BackupLocalState(
            markKeys: try database.allUserMarks().map {
                BackupMarkKey(entityType: $0.entityType, entityId: $0.entityId, kind: $0.kind)
            },
            tagKeys: try database.allPersonalTags().map {
                BackupTagKey(entityType: $0.entityType, entityId: $0.entityId, tagName: $0.tagName)
            },
            pollVotes: LocalPollVoteLog.shared.allEntries().map {
                BackupPollVoteRecord(pollId: $0.pollId, entityIds: $0.entityIds)
            }
        )

        let plan: BackupImportPlan
        do {
            plan = try planBackupImport(
                envelopeJson: json, local: local, restoreDeviceId: restoreDeviceId, dialect: .canonical
            )
        } catch let error as BackupImportError {
            throw BackupError(error)
        }

        let marks = plan.marksToInsert.map {
            UserMark(
                entityType: $0.entityType,
                entityId: $0.entityId,
                kind: $0.kind,
                boolValue: $0.boolValue,
                textValue: $0.textValue,
                updatedAt: $0.updatedAt
            )
        }
        let personalTags = plan.personalTagsToInsert.map {
            PersonalTag(
                entityType: $0.entityType,
                entityId: $0.entityId,
                tagName: $0.tagName,
                createdAt: $0.createdAt
            )
        }
        let votes = plan.pollVotesToAdd.map { BackupPollVote(pollId: $0.pollId, entityIds: $0.entityIds) }

        // 件数は書き込み側の戻り値を正とする (共有コアの計画件数と一致するが、
        // 実際に入った数を報告する方が「入っていないのに入ったと言う」事故が起きない)。
        let addedMarks = try database.restoreUserMarksIfAbsent(marks)
        let addedVotes = LocalPollVoteLog.shared.mergeIfAbsent(votes)
        let addedPersonalTags = try database.restorePersonalTagsIfAbsent(personalTags)

        if plan.restoreDeviceId {
            DeviceIdentity.restore(plan.info.deviceId)
        }

        return BackupImportResult(
            addedMarks: addedMarks,
            addedVotes: addedVotes,
            addedPersonalTags: addedPersonalTags,
            deviceIdRestored: plan.restoreDeviceId,
            skippedMarks: Int(plan.info.skippedEntries)
        )
    }
}
