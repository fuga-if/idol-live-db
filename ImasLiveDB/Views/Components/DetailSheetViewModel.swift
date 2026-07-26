import Foundation
import os

/// SongSheetContent (楽曲詳細シート) のデータ取得・整形担当。
///
/// 役割分担 (IdolDetailViewModel / UnitDetailViewModel と同型):
/// - **VM (ここ)**: 5系統のデータ取得 — 楽曲メタ/歌唱者/披露履歴/回収公演/関連曲 (`songReading`)、
///   ブランド (`brandReading`)、ジャケ情報 (MusicKit)、コミュニティ (タグ/コーレス/動画/ペンライト/
///   類似曲, `CommunityAPI`) — と、楽曲情報行 (`infoRows`) / クレジット分割 (`splitCredits`) の整形。
/// - **View 側**: セグメント・各種シート等の UI 状態、お気に入りトグル (UserMarkService) と
///   再生制御 (MusicKitService) の `@Observable` 観測、`songSeed` 由来の配色。
///
/// ⚠️ ポート未整備の依存 (`CommunityAPI` / `MusicKitService.fetchSongInfo`) は現行の到達方法を
/// この VM 内に閉じ込める。新規ポート化は Tags 担当が別途進めるため、ここでは切らない。
@MainActor
@Observable
final class DetailSheetViewModel {
    // MARK: - 楽曲メタ / 歌唱 / 履歴 (SongReading + BrandReading + MusicKit)
    private(set) var history: [PerformanceHistoryRow] = []
    private(set) var originalArtists: [Idol] = []
    private(set) var performerArtists: [Idol] = []
    private(set) var artworkInfo: MusicKitSongInfo?
    private(set) var brand: Brand?
    private(set) var collectedShows: [ShowWithEventName] = []
    /// 関連楽曲 (同シリーズ/同ユニット/歌唱共有, ローカル算出)。
    private(set) var relatedSongs: [Song] = []

    // MARK: - コミュニティ (CommunityAPI + SongReading ミラー)
    private(set) var songCalls: [SongCall] = []
    private(set) var songVideos: [SongVideo] = []
    private(set) var penlightVotes: PenlightVoteResult?
    private(set) var songTagData: SongTagListResponse?
    /// タグが似ている楽曲 (この曲が好きな人にはこれもおすすめ, サーバ算出)。
    private(set) var similarTagSongs: [Song] = []
    /// similarTagSongs の song.id → 共有タグ数。
    private(set) var similarSharedTags: [String: Int] = [:]

    private let songReading: any SongReading
    private let brandReading: any BrandReading
    private let unitReading: any UnitReading
    private let showReading: any ShowReading

    nonisolated init(
        songReading: any SongReading = AppContainer.shared.songReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        unitReading: any UnitReading = AppContainer.shared.unitReading,
        showReading: any ShowReading = AppContainer.shared.showReading
    ) {
        self.songReading = songReading
        self.brandReading = brandReading
        self.unitReading = unitReading
        self.showReading = showReading
    }

    // MARK: - Loads (5系統)

    /// 楽曲メタ/歌唱者/披露履歴/回収公演/関連曲 + ブランド + ジャケ情報を取得し、
    /// 続けてコミュニティ系 (ペンライト/タグ/類似曲) も読む。
    func loadData(song: Song) async {
        do {
            history = try await songReading.songPerformanceHistory(songId: song.id)
            originalArtists = try await songReading.songArtists(songId: song.id, role: "original")
            performerArtists = try await songReading.songArtists(songId: song.id, role: "performer")
            if let brandId = song.brandId {
                let brands = try await brandReading.brands()
                brand = brands.first { $0.id == brandId }
            }
            songCalls = try await songReading.songCalls(songId: song.id)
            songVideos = try await songReading.songVideos(songId: song.id)
            collectedShows = try await songReading.collectedShows(for: song.id)
            relatedSongs = try await songReading.relatedSongs(to: song, limit: 8)
        } catch {
            Logger.database.error("load_failed song_details: \(error.localizedDescription)")
        }
        artworkInfo = await MusicKitService.shared.fetchSongInfo(title: song.title, appleMusicId: song.appleMusicId)
        await loadPenlightVotes(song: song)
        await loadSongTags(song: song)
        await loadSimilarSongs(song: song)
    }

    /// コーレス / 参考動画をローカル DB から再読込する (投稿/編集成功後の反映)。
    func loadCommunityContent(song: Song) async {
        do {
            songCalls = try await songReading.songCalls(songId: song.id)
            songVideos = try await songReading.songVideos(songId: song.id)
        } catch {
            Logger.database.error("load_failed song_community: \(error.localizedDescription)")
        }
    }

    /// タグ類似のおすすめ楽曲をサーバから取得し、ローカル DB で Song に解決する。
    ///
    /// サーバは候補を近い順に多め (30 件) 返すので、そこから表示分を**毎回抽選**する。
    /// 近さを重みにした重み付き抽選なので、似ている曲が中心に出つつ、
    /// 少しだけタグが被っている曲もときどき混ざる。曲を開き直すと顔ぶれが変わる。
    func loadSimilarSongs(song: Song) async {
        guard let response = try? await CommunityAPI.shared.similarSongsByTags(songId: song.id) else { return }
        let picked = WeightedSampling.pick(
            response.songs, count: Self.similarSongsDisplayCount, weight: \.pickWeight)
        let ids = picked.map(\.songId)
        guard !ids.isEmpty,
              let resolved = try? await songReading.songs(criterion: .songIds(ids, title: "")) else { return }
        let byId = Dictionary(resolved.map { ($0.song.id, $0.song) }) { a, _ in a }
        similarSharedTags = Dictionary(picked.map { ($0.songId, $0.sharedTags) }) { a, _ in a }
        // 抽選順 (重み付きのランダム順) を維持する。
        similarTagSongs = ids.compactMap { byId[$0] }
    }

    /// おすすめとして画面に出す件数。候補はサーバから多めに取り、ここまで絞る。
    private static let similarSongsDisplayCount = 6

    func loadPenlightVotes(song: Song) async {
        penlightVotes = try? await CommunityAPI.shared.penlightVotes(songId: song.id)
    }

    func loadSongTags(song: Song) async {
        songTagData = try? await CommunityAPI.shared.songTags(songId: song.id)
    }

    /// 自分の付けたタグを外し、タグ一覧を再取得する。
    func removeSongTag(song: Song, tagId: String) async {
        try? await CommunityAPI.shared.removeSongTag(songId: song.id, tagId: tagId)
        await loadSongTags(song: song)
    }

    // MARK: - 非同期遷移解決

    /// ユニット行タップ時に unitId から Unit を解決する。
    func resolveUnit(id: String) async -> Unit? {
        try? await unitReading.unit(id: id)
    }

    /// 披露履歴/回収公演の行タップ時に showId から Show を解決する。
    func resolveShow(id: String) async -> Show? {
        try? await showReading.show(id: id)
    }

    // MARK: - 整形 (楽曲情報行 / クレジット)

    /// アーティスト = 歌唱アイドル名連結 (なければ singerLabel / unitName)。
    func artistLine(for song: Song) -> String? {
        if !originalArtists.isEmpty {
            return originalArtists.map(\.name).joined(separator: " / ")
        }
        return song.singerLabel ?? song.unitName
    }

    /// 「楽曲情報」セクションの行を宣言的モデルとして組み立てる。
    /// 描画 (ImasLabeledRow 等) と divider は View 側がインデックスから行う。
    func infoRows(for song: Song) -> [SongInfoRow] {
        var rows: [SongInfoRow] = []

        if let artistLine = artistLine(for: song) {
            rows.append(SongInfoRow(key: "アーティスト", kind: .plain(value: artistLine, mono: false)))
        }
        if let brand {
            rows.append(SongInfoRow(key: "ブランド",
                                    kind: .navigate(value: brand.shortName,
                                                    destination: .filteredSongs(.brand(id: brand.id, label: brand.shortName)))))
        }
        if !song.songType.isEmpty, song.songType != "unknown" {
            rows.append(SongInfoRow(key: "タイプ",
                                    kind: .navigate(value: song.songTypeLabel,
                                                    destination: .filteredSongs(.songType(song.songType)))))
        }
        if let composer = song.composer {
            rows.append(SongInfoRow(key: composer == song.arranger ? "作曲 / 編曲" : "作曲",
                                    kind: .credit(names: splitCredits(composer))))
        }
        if let arranger = song.arranger, arranger != song.composer {
            rows.append(SongInfoRow(key: "編曲", kind: .credit(names: splitCredits(arranger))))
        }
        if let lyricist = song.lyricist {
            rows.append(SongInfoRow(key: "作詞", kind: .credit(names: splitCredits(lyricist))))
        }
        if let cdSeries = song.cdSeries {
            rows.append(SongInfoRow(key: "CDシリーズ",
                                    kind: .navigate(value: cdSeries, destination: .filteredSongs(.cdSeries(cdSeries)))))
        }
        if let date = song.releaseDate {
            let year = String(date.prefix(4))
            if year.count == 4, Int(year) != nil {
                rows.append(SongInfoRow(key: "リリース日",
                                        kind: .navigate(value: date, destination: .filteredSongs(.releaseYear(year)))))
            } else {
                rows.append(SongInfoRow(key: "リリース日", kind: .plain(value: date, mono: false)))
            }
        }
        if let dur = durationValue(for: song) {
            rows.append(SongInfoRow(key: "再生時間", kind: .plain(value: dur, mono: true)))
        }
        if let unitId = song.unitId, let unitName = song.unitName {
            rows.append(SongInfoRow(key: "ユニット", kind: .unit(value: unitName, unitId: unitId)))
        }
        return rows
    }

    /// クレジット文字列を区切り文字で複数名に分割する。
    func splitCredits(_ s: String) -> [String] {
        let separators = CharacterSet(charactersIn: "/／,、・")
        return s.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func durationValue(for song: Song) -> String? {
        guard let sec = song.durationSec, sec > 0 else { return nil }
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

/// 「楽曲情報」行の宣言的モデル。View はこの kind に応じて行を描画する。
struct SongInfoRow: Identifiable {
    let id = UUID()
    let key: String
    let kind: Kind

    enum Kind {
        /// タップ不可の値表示 (mono=等幅)。
        case plain(value: String, mono: Bool)
        /// 値タップで destination へ遷移。
        case navigate(value: String, destination: DetailDestination)
        /// クレジット (作曲/作詞/編曲): 名前ごとに creator 絞り込みへ。
        case credit(names: [String])
        /// ユニット: タップ時に unitId から Unit を非同期解決して遷移。
        case unit(value: String, unitId: String)
    }
}
