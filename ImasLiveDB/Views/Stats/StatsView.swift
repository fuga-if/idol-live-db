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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp7) {
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
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp6)
            }
            .background(DS.bg.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: DS.sp4) {
            ImasSectionHeader(title: "あなたの回収率", tight: true)
            HStack(spacing: DS.sp5) {
                CollectionRing(
                    fraction: overallTotal > 0 ? Double(overallCollected) / Double(overallTotal) : 0,
                    seed: nil
                )
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: DS.sp3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(overallCollected)")
                            .font(.imasDisplay(30, weight: .bold))
                            .foregroundStyle(DS.ink)
                        Text("/ \(overallTotal)曲")
                            .font(.imasDisplay(15))
                            .foregroundStyle(DS.ink2)
                    }
                    Text("現地ライブで聴けた曲")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                    Button {
                        showCollectionShare = true
                    } label: {
                        ImasChip(text: "カードでシェア", systemImage: "square.and.arrow.up", style: .selected)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DS.sp1)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.sp5)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
    }

    // MARK: - ブランド別回収率

    @ViewBuilder
    private var brandProgressSection: some View {
        let rows = brandProgress.filter { $0.total > 0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSectionHeader(title: "ブランド別の回収率", tight: true)
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
                .padding(.horizontal, DS.sp4)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
        }
    }

    // MARK: - この公演で未回収が聴けるかも

    @ViewBuilder
    private var catchChanceSection: some View {
        if !catchChances.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSectionHeader(title: "この公演で聴けるかも", tight: true)
                VStack(spacing: DS.sp3) {
                    ForEach(catchChances) { chance in
                        Button {
                            selectedShow = chance.show
                        } label: {
                            catchChanceCard(chance)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func catchChanceCard(_ chance: UpcomingCatchChance) -> some View {
        HStack(spacing: DS.sp4) {
            ImasLeadBar(seed: chance.brandColor)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("\(displayDate(chance.show.date)) ・ \(eventDisplayName(chance.eventName))")
                    .font(.imasDisplay(12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                    .lineLimit(1)
                Text(chance.show.name)
                    .font(.imasHeadline.weight(.bold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                if let venue = chance.show.venue, !venue.isEmpty {
                    Label {
                        Text(venue)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                ImasMetricBadge(value: "\(chance.likelyCount)", unit: "曲", seed: chance.brandColor)
                Text("過去に披露")
                    .font(.imasScaled( 10, weight: .medium))
                    .foregroundStyle(DS.ink3)
            }
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - 未回収曲

    @ViewBuilder
    private var uncollectedSection: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            HStack(alignment: .firstTextBaseline) {
                ImasSectionHeader(title: "まだ生で聴けていない曲", tight: true)
                Spacer(minLength: 12)
                if uncollectedScope == .myPick && myPickTotal > 0 {
                    Text("担当 \(myPickCollected)/\(myPickTotal)")
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(DS.ink3)
                }
            }

            scopePicker
                .onChange(of: uncollectedScope) { _, _ in applyUncollectedScope() }

            if isLoadingDashboard {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, DS.sp6)
            } else if uncollectedSongs.isEmpty {
                ImasEmptyState(
                    systemImage: "checkmark.seal",
                    title: uncollectedScope == .myPick ? "担当曲はコンプリート！" : "未回収曲はありません",
                    message: uncollectedScope == .myPick
                        ? "参加ライブを記録すると、担当のオリ曲の回収状況がここに出ます。"
                        : "参加ライブを記録すると、未回収曲がここに並びます。"
                )
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            } else {
                ImasListContainer {
                    let shown = Array(uncollectedSongs.prefix(30))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        Button {
                            selectedSong = item.song
                        } label: {
                            uncollectedRow(item)
                        }
                        .buttonStyle(.plain)
                        if index < shown.count - 1 {
                            Divider().overlay(DS.sep).padding(.leading, 70)
                        }
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

    private func uncollectedRow(_ item: UncollectedSong) -> some View {
        HStack(spacing: DS.sp4) {
            ImasArtwork(
                title: item.song.title,
                seed: item.song.brandId,
                brand: item.song.brandId,
                size: 44,
                imageURL: artworkURL(item.song.artworkUrl)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.song.title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Text(brandShortName(for: item.song.brandId) ?? "")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            frequencyBadge(item)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(DS.surface)
    }

    /// 披露頻度バッジ。 定番=warning, ときどき=neutral, レア/未披露=muted。
    private func frequencyBadge(_ item: UncollectedSong) -> some View {
        let fg: Color
        let bg: Color
        switch item.playCount {
        case 10...:
            fg = DS.warning
            bg = DS.warning.opacity(0.14)
        case 3...:
            fg = DS.ink2
            bg = DS.fill
        default:
            fg = DS.ink3
            bg = DS.fill
        }
        return VStack(alignment: .trailing, spacing: 2) {
            Text(item.frequencyLabel)
                .font(.imasScaled( 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .foregroundStyle(fg)
                .background(bg, in: Capsule())
            if item.playCount > 0 {
                Text("\(item.playCount)回披露")
                    .font(.imasScaled( 10, weight: .medium))
                    .foregroundStyle(DS.ink3)
            }
        }
    }

    // MARK: - 最新の動き

    @ViewBuilder
    private var latestSection: some View {
        if let show = latestShow {
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSectionHeader(title: "最新の動き", tight: true)
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
        return HStack(spacing: DS.sp4) {
            ImasLeadBar(seed: latestShowBrandColor)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("最新公演 ・ \(displayDate(show.date))")
                    .font(.imasDisplay(12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                Text(show.name)
                    .font(.imasHeadline.weight(.bold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                if !venueLine.isEmpty {
                    Label {
                        Text(venueLine)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .labelStyle(.titleAndIcon)
                }
                HStack {
                    ImasChip(text: "セトリを見る", systemImage: "music.note.list",
                             style: .themed, seed: latestShowBrandColor)
                }
                .padding(.top, DS.sp1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - コミュニティの熱量 (お気に入りランキング ♥)

    @ViewBuilder
    private var heatSection: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            ImasSectionHeader(title: "コミュニティの熱量", tight: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    brandFilterChip(label: "すべて", brandId: nil)
                    ForEach(brands) { brand in
                        brandFilterChip(label: brand.shortName, brandId: brand.id, seed: brand.color)
                    }
                }
                .padding(.horizontal, DS.sp1)
            }

            if isLoadingFavorites {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, DS.sp6)
            } else if favoritesRanking.isEmpty {
                ImasEmptyState(
                    systemImage: "heart",
                    title: "まだデータがありません",
                    message: "お気に入り登録が増えるとここにランキングが表示されます。"
                )
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            } else {
                ImasListContainer {
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
                            Divider().overlay(DS.sep).padding(.leading, 52)
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
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSectionHeader(title: "活動量 ・ 披露回数", tight: true)
                ImasListContainer {
                    ForEach(Array(songPlayCounts.enumerated()), id: \.offset) { index, item in
                        ImasRankingRow(
                            rank: index + 1,
                            lead: .artwork(title: item.title, imageURL: nil),
                            title: item.title,
                            sub: brandShortName(for: item.brandId),
                            metric: "\(item.playCount)",
                            unit: "回",
                            brand: brandHex(for: item.brandId)
                        )
                        if index < songPlayCounts.count - 1 {
                            Divider().overlay(DS.sep).padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 活動量 ・ 出演回数 (人)

    @ViewBuilder
    private var castShowRankingSection: some View {
        if !castShowCounts.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSectionHeader(title: "活動量 ・ 出演回数", tight: true)
                ImasListContainer {
                    ForEach(Array(castShowCounts.enumerated()), id: \.offset) { index, item in
                        ImasRankingRow(
                            rank: index + 1,
                            lead: .avatar(label: monogram(item.name), imageURL: nil),
                            title: item.name,
                            metric: "\(item.showCount)",
                            unit: "人"
                        )
                        if index < castShowCounts.count - 1 {
                            Divider().overlay(DS.sep).padding(.leading, 52)
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
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSectionHeader(title: "マスタ規模 ・ ブランド別楽曲数", tight: true)
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
                .padding(.horizontal, DS.sp4)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
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

    private func monogram(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1))
    }

    /// "1280" → "1,280" のような桁区切り。
    private func heatMetric(_ count: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// "2026-06-04" → "6/4" 表示用。失敗時は元文字列。
    private func displayDate(_ raw: String) -> String {
        let comps = raw.split(separator: "-")
        guard comps.count >= 3,
              let m = Int(comps[1]), let d = Int(comps[2]) else { return raw }
        return "\(m)/\(d)"
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

    /// 回収ダッシュボードの重い集計をまとめてバックグラウンドで実行する。
    /// autoCollectedSongIds / 担当 idol は MainActor の UserMarkService から取り、
    /// branded 全曲スキャン等の重処理は detached task で回す。
    private func loadDashboard() async {
        isLoadingDashboard = true
        defer { isLoadingDashboard = false }

        let collected = UserMarkService.shared.autoCollectedSongIds()
        let pickIdolIds = Set(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol))
        let today = Self.todayString()
        let db = database

        let result: DashboardResult? = await Task.detached(priority: .userInitiated) {
            do {
                let branded = try db.fetchBrandedSongIds()
                let brandProg = try db.fetchBrandCollectionProgress(collectedIds: collected)
                let pickSongIds = try db.fetchSongIdsWithAnyArtist(idolIds: pickIdolIds)

                // 未回収リストのスコープ別母集合
                let pickUncollected = try db.fetchUncollectedSongs(candidateIds: pickSongIds, collectedIds: collected)
                let allUncollected = try db.fetchUncollectedSongs(candidateIds: branded, collectedIds: collected)

                // 「聴けるかも」は全体の未回収 ID を母集合にする。
                let allUncollectedIds = Set(allUncollected.map(\.id))
                let chances = try db.fetchUpcomingCatchChances(uncollectedIds: allUncollectedIds, today: today)

                let pickCollectedCount = pickSongIds.intersection(collected).count
                return DashboardResult(
                    overallCollected: branded.intersection(collected).count,
                    overallTotal: branded.count,
                    brandProgress: brandProg,
                    pickUncollected: pickUncollected,
                    allUncollected: allUncollected,
                    myPickCollected: pickCollectedCount,
                    myPickTotal: pickSongIds.count,
                    catchChances: chances
                )
            } catch {
                Logger.database.error("load_failed dashboard: \(error.localizedDescription)")
                return nil
            }
        }.value

        guard let result else { return }
        overallCollected = result.overallCollected
        overallTotal = result.overallTotal
        brandProgress = result.brandProgress
        pickUncollectedCache = result.pickUncollected
        allUncollectedCache = result.allUncollected
        myPickCollected = result.myPickCollected
        myPickTotal = result.myPickTotal
        catchChances = result.catchChances
        applyUncollectedScope()
    }

    private func applyUncollectedScope() {
        uncollectedSongs = uncollectedScope == .myPick ? pickUncollectedCache : allUncollectedCache
    }

    private struct DashboardResult: Sendable {
        let overallCollected: Int
        let overallTotal: Int
        let brandProgress: [BrandCollectionProgress]
        let pickUncollected: [UncollectedSong]
        let allUncollected: [UncollectedSong]
        let myPickCollected: Int
        let myPickTotal: Int
        let catchChances: [UpcomingCatchChance]
    }

    /// "yyyy-MM-dd" 形式の今日。 公演日 (TEXT) との文字列比較に使う。
    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func loadFavoritesRanking() async {
        isLoadingFavorites = true
        favoritesRanking = (try? await CommunityAPI.shared.favoritesRanking(brandId: favoriteBrandId, limit: 20)) ?? []
        isLoadingFavorites = false
    }
}

// MARK: - 回収リング (進捗ドーナツ)

/// 回収率を表す円弧プログレス。 トラック + アクセント色の弧 + 中央% 表示。
private struct CollectionRing: View {
    /// 0.0–1.0。
    let fraction: Double
    var seed: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        let clamped = min(1, max(0, fraction))
        ZStack {
            Circle()
                .stroke(DS.fill, lineWidth: 10)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(t.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.imasDisplay(20, weight: .bold))
                .foregroundStyle(DS.ink)
        }
    }
}
