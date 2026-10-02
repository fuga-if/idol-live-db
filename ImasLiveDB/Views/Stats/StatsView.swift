import os
import SwiftUI

struct StatsView: View {
    @Environment(AppDatabase.self) private var database

    @State private var brandCounts: [BrandSongCount] = []
    @State private var songPlayCounts: [SongPlayCount] = []
    @State private var castShowCounts: [CastShowCount] = []
    @State private var yearlyShowCounts: [YearlyShowCount] = []
    @State private var latestShow: Show?
    @State private var latestShowBrandColor: String?
    @State private var latestShowSongCount: Int = 0
    @State private var favoritesRanking: [FavoriteRankingEntry] = []
    @State private var favoriteBrandId: String? = nil
    @State private var brands: [Brand] = []
    @State private var selectedSong: Song?
    @State private var selectedShow: Show?
    @State private var isLoadingFavorites = false
    /// 回収率シェアカードの sheet 表示。
    @State private var showCollectionShare = false

    // MARK: 回収ダッシュボード state

    /// 全体の回収進捗 (回収済み / branded 全曲)。
    @State private var overallCollected = 0
    @State private var overallTotal = 0
    /// ブランド別回収進捗。
    @State private var brandProgress: [BrandCollectionProgress] = []
    /// 未回収曲一覧 (スコープ依存)。
    @State private var uncollectedSongs: [UncollectedSong] = []
    /// 担当オリ曲の回収状況 (担当スコープのサマリ表示用)。
    @State private var myPickCollected = 0
    @State private var myPickTotal = 0
    /// 未来公演の「聴けるかも」候補。
    @State private var catchChances: [UpcomingCatchChance] = []
    /// 未回収リストのスコープ (担当オリ曲 / 全体)。
    @State private var uncollectedScope: UncollectedScope = .myPick
    @State private var isLoadingDashboard = false
    /// 担当/全体スコープのキャッシュ。 セグメント切替時は再クエリせずキャッシュから差し替える。
    @State private var pickUncollectedCache: [UncollectedSong] = []
    @State private var allUncollectedCache: [UncollectedSong] = []

    private enum UncollectedScope: Int { case myPick, all }
    /// 「イベント名を省略」の設定 (既定 ON)。省略した名前はコアが返す。
    @AppStorage(eventNameAbbreviateKey) private var abbreviateEventNames = true

    var body: some View {
        NavigationStack {
            ImasPage {
                collectionSummarySection
                brandProgressSection
                catchChanceSection
                uncollectedSection
                latestSection
                heatSection
                songPlayRankingSection
                castShowRankingSection
                brandSongSection
            }
            .navigationTitle("回収ダッシュボード")
            .task { await loadStats() }
            .sheet(item: $selectedSong) { song in
                DetailSheetView(destination: .song(song))
                    .environment(database)
            }
            .sheet(item: $selectedShow) { show in
                DetailSheetView(destination: .show(show))
                    .environment(database)
            }
            .sheet(isPresented: $showCollectionShare) {
                CollectionShareSheet()
                    .environment(database)
            }
        }
        .trackScreen("stats")
    }

    // MARK: - 回収サマリー (全体リング + シェア導線)

    private var collectionSummarySection: some View {
        ImasSection("あなたの回収率", style: .small) {
            ImasCard {
                HStack(spacing: DS.Space.card) {
                    ImasProgressRing(fraction: overallTotal > 0 ? Double(overallCollected) / Double(overallTotal) : 0,
                                      size: 92)
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        ImasBoard(cells: [
                            .init(value: "\(overallCollected) / \(overallTotal)", unit: "曲", label: "現地ライブで聴けた曲"),
                        ])
                        Button {
                            showCollectionShare = true
                        } label: {
                            ImasChip(text: "カードでシェア", systemImage: "square.and.arrow.up", style: .selected)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - ブランド別回収率

    @ViewBuilder
    private var brandProgressSection: some View {
        let rows = brandProgress.filter { $0.total > 0 }
        if !rows.isEmpty {
            ImasSection("ブランド別の回収率", style: .small) {
                ImasCard {
                    VStack(spacing: 0) {
                        ForEach(rows) { item in
                            ImasStatBar(
                                label: item.shortName,
                                value: "\(item.collected)/\(item.total)",
                                percent: item.fraction * 100,
                                seed: item.color
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - この公演で未回収が聴けるかも

    @ViewBuilder
    private var catchChanceSection: some View {
        if !catchChances.isEmpty {
            ImasSection("この公演で聴けるかも", style: .small) {
                VStack(spacing: DS.Space.gap) {
                    ForEach(catchChances) { chance in
                        ImasTicket(
                            label: "\(dateLabel(date: chance.show.date, today: JSTDay.today())) ・ "
                                + (abbreviateEventNames ? chance.eventShortName : chance.eventName),
                            imprint: nil,
                            title: chance.show.name,
                            meta: (chance.show.venue?.isEmpty == false) ? chance.show.venue : nil,
                            metaIcon: "mappin.and.ellipse",
                            brand: chance.brandColor,
                            // 回収する根拠 (何回披露された曲が) まで読めるように。
                            countdown: .init(prefix: "過去に披露", value: "\(chance.likelyCount)", unit: "曲"),
                            onOpen: { selectedShow = chance.show }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 未回収曲

    @ViewBuilder
    private var uncollectedSection: some View {
        ImasSection(
            "まだ生で聴けていない曲",
            count: (uncollectedScope == .myPick && myPickTotal > 0) ? "担当 \(myPickCollected)/\(myPickTotal)" : nil,
            style: .small
        ) {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                scopePicker
                    .onChange(of: uncollectedScope) { _, _ in applyUncollectedScope() }

                if isLoadingDashboard {
                    ImasInlineLoading()
                } else if uncollectedSongs.isEmpty {
                    ImasCard {
                        ImasEmptyState(
                            systemImage: "checkmark.seal",
                            title: uncollectedScope == .myPick ? "担当曲はコンプリート！" : "未回収曲はありません",
                            message: uncollectedScope == .myPick
                                ? "参加ライブを記録すると、担当のオリ曲の回収状況がここに出ます。"
                                : "参加ライブを記録すると、未回収曲がここに並びます。"
                        )
                    }
                } else {
                    let shown = Array(uncollectedSongs.prefix(30))
                    ImasCardList(shown) { item in
                        Button {
                            selectedSong = item.song
                        } label: {
                            ImasSongRow(
                                song: item.song,
                                subtitle: brandShortName(for: item.song.brandId),
                                playsPreview: false,
                                trailing: .custom(AnyView(frequencyBadge(item)))
                            )
                        }
                        .buttonStyle(.imasRow)
                    }
                }
            }
        }
    }

    private var scopePicker: some View {
        let binding = Binding(
            get: { uncollectedScope.rawValue },
            set: { uncollectedScope = UncollectedScope(rawValue: $0) ?? .myPick }
        )
        return ImasSegmented(labels: ["担当のオリ曲", "全体"], selection: binding)
    }

    /// 披露頻度バッジ。 定番=attention(墨の線)、ときどき=neutral(灰)、レア/未披露=negative(薄字)。
    private func frequencyBadge(_ item: UncollectedSong) -> some View {
        let kind: ImasBadge.Kind
        switch item.frequency {
        case .staple: kind = .attention
        case .sometimes: kind = .neutral
        case .rare, .never: kind = .negative
        }
        return VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
            ImasBadge(text: item.frequencyLabel, kind: kind)
            if item.playCount > 0 {
                ImasMetric(value: "\(item.playCount)", unit: "回披露", size: .small)
            }
        }
    }

    // MARK: - 最新の動き

    @ViewBuilder
    private var latestSection: some View {
        if let show = latestShow {
            ImasSection("最新の動き", style: .small) {
                NavigationLink {
                    SetlistView(show: show)
                } label: {
                    latestCard(show)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func latestCard(_ show: Show) -> some View {
        let venueLine: String = {
            var parts: [String] = []
            if let venue = show.venue, !venue.isEmpty { parts.append(venue) }
            if latestShowSongCount > 0 { parts.append("セトリ \(latestShowSongCount)曲") }
            return parts.joined(separator: " ・ ")
        }()
        return ImasShowRow(
            date: show.date,
            title: show.name,
            subtitle: venueLine.isEmpty ? nil : venueLine,
            brandHex: latestShowBrandColor,
            badges: [ImasBadgeSpec(text: "最新公演", kind: .neutral)],
            detailAccessibilityLabel: "セトリを見る",
            subtitleLineLimit: 2
        ) {
            ImasChip(text: "セトリを見る", systemImage: "music.note.list", style: .themed, seed: latestShowBrandColor)
        }
    }

    // MARK: - コミュニティの熱量 (お気に入りランキング ♥)

    @ViewBuilder
    private var heatSection: some View {
        ImasSection("コミュニティの熱量", style: .small) {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ImasChipRow {
                    brandFilterChip(label: "すべて", brandId: nil)
                    ForEach(brands) { brand in
                        brandFilterChip(label: brand.shortName, brandId: brand.id, seed: brand.color)
                    }
                }

                if isLoadingFavorites {
                    ImasInlineLoading()
                } else if favoritesRanking.isEmpty {
                    ImasCard {
                        ImasEmptyState(
                            systemImage: "heart",
                            title: "まだデータがありません",
                            message: "お気に入り登録が増えるとここにランキングが表示されます。"
                        )
                    }
                } else {
                    ImasCardList {
                        ForEach(Array(favoritesRanking.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                Task { selectedSong = try? await AppContainer.shared.songReading.song(id: entry.songId) }
                            } label: {
                                ImasRankingRow(
                                    rank: index + 1,
                                    lead: .artwork(title: entry.title, imageURL: artworkURL(entry.artworkUrl)),
                                    title: entry.title,
                                    sub: brandShortName(for: entry.brandId),
                                    metric: heatMetric(entry.count),
                                    unit: "♥",
                                    brand: brandHex(for: entry.brandId)
                                )
                            }
                            .buttonStyle(.plain)
                            if index < favoritesRanking.count - 1 {
                                ImasRowDivider(inset: 52)
                            }
                        }
                    }
                }
            }
        }
        .task(id: favoriteBrandId) { await loadFavoritesRanking() }
    }

    // MARK: - 活動量 ・ 披露回数 (曲)

    @ViewBuilder
    private var songPlayRankingSection: some View {
        if !songPlayCounts.isEmpty {
            ImasSection("活動量 ・ 披露回数", style: .small) {
                ImasCardList {
                    ForEach(Array(songPlayCounts.enumerated()), id: \.offset) { index, item in
                        ImasRankingRow(
                            rank: index + 1,
                            lead: .artwork(title: item.title, imageURL: artworkURL(item.artworkUrl)),
                            title: item.title,
                            sub: brandShortName(for: item.brandId),
                            metric: "\(item.playCount)",
                            unit: "回",
                            brand: brandHex(for: item.brandId)
                        )
                        if index < songPlayCounts.count - 1 {
                            ImasRowDivider(inset: 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 活動量 ・ 出演回数 (公演)

    @ViewBuilder
    private var castShowRankingSection: some View {
        if !castShowCounts.isEmpty {
            ImasSection("活動量 ・ 出演回数", style: .small) {
                ImasCardList {
                    ForEach(Array(castShowCounts.enumerated()), id: \.offset) { index, item in
                        ImasRankingRow(
                            rank: index + 1,
                            // アイコンは写真か判子 (担当色)。ほかの画面と同じ。
                            lead: .avatar(label: item.shortName ?? item.name,
                                          imageURL: CustomImageService.shared.imageURL(for: item.id)),
                            title: item.name,
                            metric: "\(item.showCount)",
                            unit: "公演",
                            seed: item.color
                        )
                        if index < castShowCounts.count - 1 {
                            ImasRowDivider(inset: 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: - マスタ規模 ・ ブランド別楽曲数

    @ViewBuilder
    private var brandSongSection: some View {
        if !brandCounts.isEmpty {
            let maxCount = brandCounts.map(\.songCount).max() ?? 1
            ImasSection("マスタ規模 ・ ブランド別楽曲数", style: .small) {
                ImasCard {
                    VStack(spacing: 0) {
                        ForEach(brandCounts) { item in
                            ImasStatBar(
                                label: item.shortName,
                                value: "\(item.songCount)",
                                percent: maxCount > 0 ? Double(item.songCount) / Double(maxCount) * 100 : 0,
                                seed: item.color
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - ブランドフィルタチップ

    private func brandFilterChip(label: String, brandId: String?, seed: String? = nil) -> some View {
        let isSelected = favoriteBrandId == brandId
        return Button {
            favoriteBrandId = brandId
        } label: {
            ImasChip(text: label, style: isSelected ? .selected : .neutral, seed: seed)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func brandHex(for brandId: String?) -> String? {
        guard let brandId else { return nil }
        return brands.first(where: { $0.id == brandId })?.color
    }

    private func brandShortName(for brandId: String?) -> String? {
        guard let brandId else { return nil }
        return brands.first(where: { $0.id == brandId })?.shortName
    }

    private func artworkURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// "1280" → "1,280" のような桁区切り。
    private func heatMetric(_ count: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - Loading

    private func loadStats() async {
        do {
            let statsReading = AppContainer.shared.statsReading
            brandCounts = try await statsReading.brandSongCounts()
            songPlayCounts = try await statsReading.songPlayCountRanking(limit: 20)
            castShowCounts = try await statsReading.castShowCountRanking(limit: 20)
            yearlyShowCounts = try await statsReading.yearlyShowCounts()
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []

            let show = try await AppContainer.shared.showReading.latestShow()
            latestShow = show
            if let show {
                latestShowSongCount = (try? await AppContainer.shared.showReading.setlist(showId: show.id).count) ?? 0
                let event = try? await AppContainer.shared.eventReading.event(id: show.eventId)
                latestShowBrandColor = brandHex(for: event?.brandId)
            }
        } catch {
            Logger.database.error("load_failed stats: \(error.localizedDescription)")
        }
        await loadDashboard()
        await loadFavoritesRanking()
    }

    /// 回収ダッシュボード。組み立てはコア (`collection_dashboard`) が 1 回で行う。
    /// 回収済みの曲と担当は端末ローカルの印 (UserMarkService) から渡す。
    private func loadDashboard() async {
        isLoadingDashboard = true
        defer { isLoadingDashboard = false }
        do {
            let dashboard = try await AppContainer.shared.statsReading.collectionDashboard(
                collectedSongIds: UserMarkService.shared.autoCollectedSongIds(),
                pickIdolIds: Set(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol)),
                today: JSTDay.today(),
                chanceLimit: Self.catchChanceLimit)
            overallCollected = dashboard.overallCollected
            overallTotal = dashboard.overallTotal
            brandProgress = dashboard.brandProgress
            pickUncollectedCache = dashboard.pickUncollected
            allUncollectedCache = dashboard.allUncollected
            myPickCollected = dashboard.myPickCollected
            myPickTotal = dashboard.myPickTotal
            catchChances = dashboard.catchChances
            applyUncollectedScope()
        } catch {
            Logger.database.error("load_failed dashboard: \(error.localizedDescription)")
        }
    }

    /// 「この公演で聴けるかも」に並べる公演の数。
    private static let catchChanceLimit = 8

    private func applyUncollectedScope() {
        uncollectedSongs = uncollectedScope == .myPick ? pickUncollectedCache : allUncollectedCache
    }

    private func loadFavoritesRanking() async {
        isLoadingFavorites = true
        favoritesRanking = (try? await CommunityAPI.shared.favoritesRanking(brandId: favoriteBrandId, limit: 20)) ?? []
        isLoadingFavorites = false
    }
}
