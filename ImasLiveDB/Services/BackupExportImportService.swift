import CryptoKit
import Foundation

// MARK: - Backup payload (iOS/Android共通契約)

/// バックアップ本体。フィールド名はプラットフォーム間の共通契約のため camelCase 固定。
struct BackupPayload: Codable {
    var schemaVersion: Int
    var exportedAt: String
    var platform: String
    var appVersion: String
    var deviceId: String
    var userMarks: [BackupUserMark]
    var pollVotes: [BackupPollVote]
}

struct BackupUserMark: Codable {
    var entityType: String
    var entityId: String
    /// canonical 表記。iOS の内部表記 (`UserMarkKind.rawValue`) をそのまま使う (Android 側が変換する契約)。
    var kind: String
    var boolValue: Bool
    var textValue: String?
    var updatedAt: String
}

struct BackupPollVote: Codable {
    var pollId: String
    var entityIds: [String]
}

// MARK: - Envelope

private struct BackupEnvelope: Codable {
    var envelopeVersion: Int
    var checksum: String
    var payload: String
}

// MARK: - Errors / Result

enum BackupError: LocalizedError {
    case malformedFile
    case checksumMismatch
    case unsupportedSchemaVersion(Int)

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
    var deviceIdRestored: Bool
    var skippedMarks: Int
}

// MARK: - BackupExportImportService

@MainActor
enum BackupExportImportService {
    static let currentSchemaVersion = 1
    private static let envelopeVersion = 1

    // MARK: Export

    /// `BackupPayload` を構築し、envelope 込みの JSON 文字列を返す。
    static func buildEnvelopeJSON(database: AppDatabase) throws -> String {
        let marks = try database.allUserMarks().map {
            BackupUserMark(
                entityType: $0.entityType,
                entityId: $0.entityId,
                kind: $0.kind,
                boolValue: $0.boolValue,
                textValue: $0.textValue,
                updatedAt: $0.updatedAt
            )
        }
        let votes = LocalPollVoteLog.shared.allEntries()

        let payload = BackupPayload(
            schemaVersion: currentSchemaVersion,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            platform: "ios",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            deviceId: DeviceIdentity.shared,
            userMarks: marks,
            pollVotes: votes
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        // checksum はこの文字列バイト列に対して計算するため、以後 payload は再シリアライズしない。
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw BackupError.malformedFile
        }

        let checksum = "sha256:" + sha256Hex(payloadString)
        let envelope = BackupEnvelope(envelopeVersion: envelopeVersion, checksum: checksum, payload: payloadString)

        let envelopeEncoder = JSONEncoder()
        envelopeEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let envelopeData = try envelopeEncoder.encode(envelope)
        guard let envelopeString = String(data: envelopeData, encoding: .utf8) else {
            throw BackupError.malformedFile
        }
        return envelopeString
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
    static func importEnvelopeJSON(
        _ json: String,
        database: AppDatabase,
        restoreDeviceId: Bool
    ) throws -> BackupImportResult {
        guard let envelopeData = json.data(using: .utf8) else { throw BackupError.malformedFile }
        let envelope: BackupEnvelope
        do {
            envelope = try JSONDecoder().decode(BackupEnvelope.self, from: envelopeData)
        } catch {
            throw BackupError.malformedFile
        }

        let expectedChecksum = "sha256:" + sha256Hex(envelope.payload)
        guard envelope.checksum == expectedChecksum else {
            throw BackupError.checksumMismatch
        }

        guard let payloadData = envelope.payload.data(using: .utf8),
              let topLevel = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw BackupError.malformedFile
        }

        guard let schemaVersion = topLevel["schemaVersion"] as? Int else {
            throw BackupError.malformedFile
        }
        guard schemaVersion <= currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(schemaVersion)
        }

        let decoder = JSONDecoder()
        var skipped = 0

        var marks: [UserMark] = []
        if let rawMarks = topLevel["userMarks"] as? [[String: Any]] {
            for raw in rawMarks {
                do {
                    let data = try JSONSerialization.data(withJSONObject: raw)
                    let mark = try decoder.decode(BackupUserMark.self, from: data)
                    marks.append(UserMark(
                        entityType: mark.entityType,
                        entityId: mark.entityId,
                        kind: mark.kind,
                        boolValue: mark.boolValue,
                        textValue: mark.textValue,
                        updatedAt: mark.updatedAt
                    ))
                } catch {
                    skipped += 1
                }
            }
        }

        var votes: [BackupPollVote] = []
        if let rawVotes = topLevel["pollVotes"] as? [[String: Any]] {
            for raw in rawVotes {
                do {
                    let data = try JSONSerialization.data(withJSONObject: raw)
                    votes.append(try decoder.decode(BackupPollVote.self, from: data))
                } catch {
                    skipped += 1
                }
            }
        }

        let addedMarks = try database.restoreUserMarksIfAbsent(marks)
        let addedVotes = LocalPollVoteLog.shared.mergeIfAbsent(votes)

        var deviceIdRestored = false
        if restoreDeviceId, let deviceId = topLevel["deviceId"] as? String, !deviceId.isEmpty {
            DeviceIdentity.restore(deviceId)
            deviceIdRestored = true
        }

        return BackupImportResult(
            addedMarks: addedMarks,
            addedVotes: addedVotes,
            deviceIdRestored: deviceIdRestored,
            skippedMarks: skipped
        )
    }

    // MARK: - Checksum

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
