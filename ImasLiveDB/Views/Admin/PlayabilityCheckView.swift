import SwiftUI
import MusicKit
import GRDB
import UniformTypeIdentifiers

/// master.sqlite の全曲を MusicCatalogResourceRequest で fetch し、
/// `playParameters` が nil = サブスク再生不可な曲を抽出する管理画面。
///
/// 用途: DB の apple_music_id が iTunes Store 購入専用 ID (例: Orange Sapphire の 4:34 版)
/// を掴んでいる曲を発見し、 サブスク配信の正しい storeID に差し替えるための候補リストを得る。
struct PlayabilityCheckView: View {
    @State private var brandFilter: String = ""
    @State private var concurrency: Int = 8
    @State private var totalCount: Int = 0
    @State private var processed: Int = 0
    @State private var rows: [PlayabilityReport] = []
    @State private var isRunning: Bool = false
    @State private var errorMessage: String? = nil
    @State private var jsonURL: URL? = nil
    // 代替検索の状態
    @State private var altRows: [AlternativeCandidate] = []
    @State private var altProcessed: Int = 0
    @State private var altTotal: Int = 0
    @State private var altRunning: Bool = false
    @State private var altJsonURL: URL? = nil

    private var unplayable: [PlayabilityReport] { rows.filter { !$0.playable } }

    var body: some View {
        Form {
            Section("対象") {
                TextField("brand_id (空=全ブランド / 例: cg, ml, 765as)", text: $brandFilter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Picker("並列度", selection: $concurrency) {
                    Text("1 (安全)").tag(1)
                    Text("2 (再試行向け)").tag(2)
                    Text("4").tag(4)
                    Text("8 (初回向け)").tag(8)
                }
                .pickerStyle(.segmented)
                Text("レート制限で DecodingError が出たら並列度を 2 に落として再実行してください。")
                    .font(.caption).foregroundStyle(DS.ink2)
            }
            Section {
                Button {
                    Task { await start() }
                } label: {
                    Label(isRunning ? "実行中…" : "チェック開始", systemImage: "play.fill")
                }
                .disabled(isRunning)

                if totalCount > 0 {
                    VStack(alignment: .leading, spacing: DS.sp2) {
                        ProgressView(value: Double(processed), total: Double(totalCount))
                        Text("\(processed) / \(totalCount) (再生不可 \(unplayable.count))")
                            .font(.caption).foregroundStyle(DS.ink2)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }

            if !unplayable.isEmpty {
                Section("代替 storeID 検索") {
                    Button {
                        Task { await searchAlternatives() }
                    } label: {
                        Label(altRunning ? "検索中…" : "playable な代替を探す", systemImage: "magnifyingglass")
                    }
                    .disabled(altRunning || isRunning)
                    if altTotal > 0 {
                        VStack(alignment: .leading, spacing: DS.sp2) {
                            ProgressView(value: Double(altProcessed), total: Double(altTotal))
                            let hits = altRows.filter { $0.candidateAppleMusicId != nil }.count
                            Text("\(altProcessed) / \(altTotal) (代替見つかった: \(hits))")
                                .font(.caption).foregroundStyle(DS.ink2)
                        }
                    }
                    if let altJsonURL {
                        ShareLink(item: altJsonURL) {
                            Label("代替候補 JSON を共有", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }

            if !rows.isEmpty {
                Section("再生不可一覧 (\(unplayable.count))") {
                    if let jsonURL {
                        ShareLink(item: jsonURL) {
                            Label("JSON を共有 (AirDrop など)", systemImage: "square.and.arrow.up")
                        }
                    }
                    ForEach(unplayable) { row in
                        VStack(alignment: .leading, spacing: DS.sp1) {
                            Text(row.title).font(.subheadline.weight(.semibold))
                            HStack(spacing: DS.sp3) {
                                Text(row.brandId).font(.caption.monospaced()).foregroundStyle(.blue)
                                Text("amid: \(row.appleMusicId)").font(.caption.monospaced())
                                if let d = row.catalogDurationSec { Text("cat \(d)s").font(.caption) }
                                if let d = row.dbDurationSec { Text("db \(d)s").font(.caption) }
                            }
                            .foregroundStyle(DS.ink2)
                            if let err = row.error {
                                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                        .padding(.vertical, DS.sp1)
                    }
                }
            }
        }
        .navigationTitle("再生可否チェック")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }
        processed = 0
        rows = []
        jsonURL = nil

        // 認可確認 (アプリ全体ですでに通っている前提だが念のため request)
        let status: MusicAuthorization.Status
        if MusicAuthorization.currentStatus == .authorized {
            status = .authorized
        } else {
            status = await MusicAuthorization.request()
        }
        guard status == .authorized else {
            errorMessage = "MusicAuthorization が \(status)。 設定でアクセス許可してください。"
            return
        }

        let songs: [SongRow]
        do {
            songs = try fetchSongs(brandFilter: brandFilter)
        } catch {
            errorMessage = "DB 読み込み失敗: \(error.localizedDescription)"
            return
        }
        totalCount = songs.count
        guard totalCount > 0 else {
            errorMessage = "対象曲が 0 件です。"
            return
        }

        // 設定された並列度で逐次処理。 結果を main で逐次反映。
        let maxParallel = concurrency
        await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: PlayabilityReport.self) { group in
                var inFlight = 0
                for song in songs {
                    if inFlight >= maxParallel {
                        if let r = await group.next() {
                            await MainActor.run { append(r) }
                        }
                        inFlight -= 1
                    }
                    group.addTask { await checkOne(song) }
                    inFlight += 1
                }
                while let r = await group.next() {
                    await MainActor.run { append(r) }
                }
            }
        }.value

        // JSON ファイル書き出し → ShareLink 用 URL を立てる。
        do {
            let dir = FileManager.default.temporaryDirectory
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = dir.appendingPathComponent("playability_\(stamp).json")
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try enc.encode(rows.sorted { ($0.brandId, $0.title) < ($1.brandId, $1.title) })
            try data.write(to: file)
            jsonURL = file
        } catch {
            errorMessage = "JSON 書き出し失敗: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func append(_ r: PlayabilityReport) {
        rows.append(r)
        processed += 1
    }

    @MainActor
    private func appendAlt(_ r: AlternativeCandidate) {
        altRows.append(r)
        altProcessed += 1
    }

    private func searchAlternatives() async {
        errorMessage = nil
        altRunning = true
        defer { altRunning = false }
        altRows = []
        altProcessed = 0
        altJsonURL = nil

        // 不可曲のうち playParameters=nil (= 確定不可) を対象。 DecodingError 群は別途再試行で
        // 解消すべきなのでここでは対象外 (混ぜると無駄に検索回数が増える)。
        let targets = rows.filter { !$0.playable && $0.error == nil }
        altTotal = targets.count
        guard altTotal > 0 else { errorMessage = "確定不可の曲が 0 件です。"; return }

        // 並列度 2 (検索 API はカタログ取得より重い)。
        await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: AlternativeCandidate.self) { group in
                let maxParallel = 2
                var inFlight = 0
                for r in targets {
                    if inFlight >= maxParallel {
                        if let v = await group.next() {
                            await MainActor.run { appendAlt(v) }
                        }
                        inFlight -= 1
                    }
                    group.addTask { await searchOne(r) }
                    inFlight += 1
                }
                while let v = await group.next() {
                    await MainActor.run { appendAlt(v) }
                }
            }
        }.value

        // JSON 書き出し → 共有可能に。
        do {
            let dir = FileManager.default.temporaryDirectory
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = dir.appendingPathComponent("alternatives_\(stamp).json")
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try enc.encode(altRows.sorted { ($0.brandId, $0.dbTitle) < ($1.brandId, $1.dbTitle) })
            try data.write(to: file)
            altJsonURL = file
        } catch {
            errorMessage = "代替 JSON 書き出し失敗: \(error.localizedDescription)"
        }
    }
}

// MARK: - 代替検索

private func searchOne(_ src: PlayabilityReport) async -> AlternativeCandidate {
    // タイトル + アーティスト指定の方が精度高いが、 アーティスト情報が DB の brand_id だけ
    // なので使えない。 title 完全一致で検索し、 playable な候補のみ集計。
    var req = MusicCatalogSearchRequest(term: src.title, types: [MusicKit.Song.self])
    req.limit = 25
    do {
        let resp = try await req.response()
        let allHits = Array(resp.songs)
        // タイトル完全一致だけに絞る (誤マッチ防止)。 大文字小文字・全角半角は許容。
        let normalizedDb = normalizeForCompare(src.title)
        let titleMatched = allHits.filter { normalizeForCompare($0.title) == normalizedDb }
        let playable = titleMatched.filter { $0.playParameters != nil }
        // 候補が複数あれば「DB の duration_sec に最も近いもの」 を採用 (game version か full かを尺で判別)。
        let best: MusicKit.Song? = pickBest(playable, dbDuration: src.dbDurationSec)
        let bestDur = best?.duration.map { Int($0.rounded()) }
        return AlternativeCandidate(
            songId: src.id, dbTitle: src.title, brandId: src.brandId,
            originalAppleMusicId: src.appleMusicId, dbDurationSec: src.dbDurationSec,
            candidateAppleMusicId: best?.id.rawValue,
            candidateTitle: best?.title,
            candidateArtist: best?.artistName,
            candidateDurationSec: bestDur,
            totalHits: allHits.count, playableHits: playable.count
        )
    } catch {
        return AlternativeCandidate(
            songId: src.id, dbTitle: src.title, brandId: src.brandId,
            originalAppleMusicId: src.appleMusicId, dbDurationSec: src.dbDurationSec,
            candidateAppleMusicId: nil, candidateTitle: nil,
            candidateArtist: nil, candidateDurationSec: nil,
            totalHits: 0, playableHits: 0
        )
    }
}

private func pickBest(_ candidates: [MusicKit.Song], dbDuration: Int?) -> MusicKit.Song? {
    guard !candidates.isEmpty else { return nil }
    if let target = dbDuration {
        return candidates.min { a, b in
            let aDiff = abs(Int((a.duration ?? 0).rounded()) - target)
            let bDiff = abs(Int((b.duration ?? 0).rounded()) - target)
            return aDiff < bDiff
        }
    }
    // duration 不明なら最初の playable を返す。
    return candidates.first
}

private func normalizeForCompare(_ s: String) -> String {
    s.lowercased()
        .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s.lowercased()
}

// MARK: - Models

struct SongRow: Sendable {
    let id: String
    let title: String
    let appleMusicId: String
    let brandId: String
    let durationSec: Int?
}

struct PlayabilityReport: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let appleMusicId: String
    let brandId: String
    let dbDurationSec: Int?
    let catalogTitle: String?
    let catalogDurationSec: Int?
    let playable: Bool
    let error: String?
}

/// 不可曲 → 代替候補 (サブスク再生可な同名の別 storeID)。
struct AlternativeCandidate: Codable, Identifiable, Sendable {
    let songId: String       // DB の songs.id
    let dbTitle: String
    let brandId: String
    let originalAppleMusicId: String
    let dbDurationSec: Int?
    let candidateAppleMusicId: String?
    let candidateTitle: String?
    let candidateArtist: String?
    let candidateDurationSec: Int?
    /// 何曲ヒットしたか (検索全体)。
    let totalHits: Int
    /// playable な候補数。
    let playableHits: Int
    var id: String { songId }
}

// MARK: - DB

@MainActor
private func fetchSongs(brandFilter: String) throws -> [SongRow] {
    let db = AppDatabase.shared
    let trimmed = brandFilter.trimmingCharacters(in: .whitespaces)
    return try db.dbQueue.read { dbConn -> [SongRow] in
        let baseSQL = """
            SELECT id, title, apple_music_id, COALESCE(brand_id, ''), COALESCE(duration_sec, -1)
            FROM songs
            WHERE apple_music_id IS NOT NULL AND apple_music_id != ''
            """
        let (sql, args): (String, StatementArguments) = trimmed.isEmpty
            ? (baseSQL + " ORDER BY brand_id, title", StatementArguments())
            : (baseSQL + " AND brand_id = ? ORDER BY brand_id, title", StatementArguments([trimmed]))
        let rows = try Row.fetchAll(dbConn, sql: sql, arguments: args)
        return rows.map { row in
            SongRow(
                id: row[0] as String,
                title: row[1] as String,
                appleMusicId: row[2] as String,
                brandId: row[3] as String,
                durationSec: (row[4] as Int) == -1 ? nil : (row[4] as Int)
            )
        }
    }
}

// MARK: - MusicKit

private func checkOne(_ song: SongRow) async -> PlayabilityReport {
    let id = MusicItemID(rawValue: song.appleMusicId)
    let req = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
    do {
        let resp = try await req.response()
        if let s = resp.items.first {
            let dur = s.duration.map { Int($0.rounded()) }
            return PlayabilityReport(
                id: song.id, title: song.title, appleMusicId: song.appleMusicId,
                brandId: song.brandId, dbDurationSec: song.durationSec,
                catalogTitle: s.title, catalogDurationSec: dur,
                playable: s.playParameters != nil, error: nil
            )
        }
        return PlayabilityReport(
            id: song.id, title: song.title, appleMusicId: song.appleMusicId,
            brandId: song.brandId, dbDurationSec: song.durationSec,
            catalogTitle: nil, catalogDurationSec: nil,
            playable: false, error: "empty_response"
        )
    } catch {
        return PlayabilityReport(
            id: song.id, title: song.title, appleMusicId: song.appleMusicId,
            brandId: song.brandId, dbDurationSec: song.durationSec,
            catalogTitle: nil, catalogDurationSec: nil,
            playable: false, error: "\(error)"
        )
    }
}
