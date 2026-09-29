import Foundation

/// `EditFeedReading` ポートのアダプタ。
///
/// 編集の対象の呼び名と公演は、スナップショットにあるものはコア (`edit_record_target`:
/// 公演・セトリは「ライブ名 見分け」の正式な呼び名) が答える。参考動画 (SongVideo) は
/// スナップショットに無いので端末の DB に訊く。
struct GRDBEditFeedRepository: EditFeedReading {
    let database: AppDatabase
    let snapshot: CoreSnapshotManager

    func editRecordTargets(_ keys: [EditRecordKey]) async throws -> [EditRecordKey: EditRecordResolution] {
        var result: [EditRecordKey: EditRecordResolution] = [:]
        let unique = Array(Set(keys))
        for key in unique where key.recordType == "SongVideo" {
            let title = try await database.fetchSongVideoSongTitleAsync(videoId: key.recordName)
            result[key] = EditRecordResolution(title: title, showId: nil)
        }
        // スナップショットを 1 回待って、レコードごとに 1 回ずつ引く
        // (まとめて引く FFI はまだ無い)。
        let others = unique.filter { $0.recordType != "SongVideo" }
        guard !others.isEmpty else { return result }
        let resolved: [(EditRecordKey, EditRecordResolution)] = try await snapshot.withStore { store in
            try others.map { key in
                let target = try store.editRecordTarget(recordType: key.recordType, recordName: key.recordName)
                return (key, EditRecordResolution(title: target.title, showId: target.showId))
            }
        }
        for (key, value) in resolved { result[key] = value }
        return result
    }

    func editRecordSongId(recordType: String, recordName: String) async throws -> String? {
        try await database.fetchEditRecordSongIdAsync(recordType: recordType, recordName: recordName)
    }
}
