import SwiftUI

// =============================================================================
// 機能 4: 年間まとめカード (Wrapped 風)
// その年に「参加した公演」のセトリから、参加公演数・回収曲数・最多遭遇曲・
// 担当遭遇率などを集計して 1 枚のカードにする。
//
// 集計は既存の AppDatabase メソッド + UserMarkService だけで行い (CollectionShareStats
// と同じ方針)、AppDatabase 本体には手を入れない。
//
// 曲が複数に渡るためジャケ写背景にはしない (版権・特定不能)。SoloShareScaffold の
// 単色編集デザイン + メンバーカラー差し色で構成する。
// =============================================================================

/// 年間まとめカードに焼く集計データ。
struct YearWrappedStats {
    /// 対象年 (西暦)。
    let year: Int
    /// 参加公演数 (現地 + 配信のうち attended マークが付いた公演)。
    let showCount: Int
    /// 参加したイベント (ツアー等) のユニーク数。
    let eventCount: Int
    /// 現地参加した公演数 (attendance == .live)。配信と区別して見せる。
    let liveShowCount: Int
    /// 参加公演のセトリで聴けたユニーク曲数。
    let songCount: Int
    /// 最も多く遭遇した曲 (タイトル + 遭遇回数)。同率は曲名順で先頭。
    let topSong: TopSong?
    /// 担当アイドル別の遭遇率 (原曲のうち今年聴けた割合)。先頭 3 人まで。
    let idolLines: [IdolLine]

    struct TopSong {
        let title: String
        let count: Int
    }

    struct IdolLine: Identifiable {
        let id: String
        let name: String
        let color: String?
        /// 今年の参加公演で聴けた担当原曲数。
        let heard: Int
        /// 担当の原曲総数。
        let total: Int

        var ratio: Double { total > 0 ? Double(heard) / Double(total) : 0 }
    }

    /// カードに出すだけの中身があるか (参加公演 0 ならまとめを出さない)。
    var hasContent: Bool { showCount > 0 }

    /// メンバーカラー seed: 先頭の担当カラー → なければニュートラル。
    var seed: String? { idolLines.first?.color }

    /// カード見出し用の年ラベル ("2026年のまとめ")。
    var headline: String { "\(year)年のまとめ" }
}

// MARK: - 集計

extension YearWrappedStats {
    /// 指定年の参加実績を集計する。`@MainActor` は UserMarkService 参照のため。
    @MainActor
    static func load(year: Int) async -> YearWrappedStats {
        let marks = UserMarkService.shared

        // 1) 参加公演 (show) を解決する。
        //    attended は show 直接マーク or 親 event マークの両方がありうるので
        //    両者をマージして「参加した show」の母集合を作る。
        let attendedShowIds = Set(marks.allMarked(kind: .attended, entity: .show))
        let attendedEventIds = Set(marks.allMarked(kind: .attended, entity: .event))

        var showsById: [String: Show] = [:]
        for eventId in attendedEventIds {
            for show in (try? await AppContainer.shared.showReading.shows(eventId: eventId)) ?? [] {
                showsById[show.id] = show
            }
        }
        for showId in attendedShowIds where showsById[showId] == nil {
            if let show = try? await AppContainer.shared.showReading.show(id: showId) {
                showsById[show.id] = show
            }
        }

        // 2) 対象年の公演だけに絞る (date は "YYYY-MM-DD")。
        let yearPrefix = String(year)
        let yearShows = showsById.values.filter { $0.date.hasPrefix(yearPrefix) }

        guard !yearShows.isEmpty else {
            return YearWrappedStats(
                year: year, showCount: 0, eventCount: 0, liveShowCount: 0,
                songCount: 0, topSong: nil, idolLines: []
            )
        }

        // 3) 公演数・イベント数・現地数。
        let eventIds = Set(yearShows.map(\.eventId))
        let liveShowCount = yearShows.filter { show in
            // show 直のマークがあればそれを、無ければ親 event のマークを参照。
            let type = marks.attendance(entity: .show, id: show.id)
                ?? marks.attendance(entity: .event, id: show.eventId)
            return type == .live
        }.count

        // 4) 参加公演のセトリを集計 → 曲別の遭遇公演数。
        var songEncounter: [String: Int] = [:]   // songId → 遭遇した公演数
        var songTitle: [String: String] = [:]
        for show in yearShows {
            let setlist = (try? await AppContainer.shared.showReading.setlist(showId: show.id)) ?? []
            // 同一公演内の重複 (アンコール等) は 1 公演 = 1 遭遇として数える。
            var seenInShow = Set<String>()
            for item in setlist where seenInShow.insert(item.songId).inserted {
                songEncounter[item.songId, default: 0] += 1
                songTitle[item.songId] = item.songTitle
            }
        }

        let songCount = songEncounter.count
        let topSong: TopSong? = songEncounter
            .max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                // 同率は曲名で安定ソート (降順 max なので後ろが勝たないよう逆比較)。
                return (songTitle[lhs.key] ?? "") > (songTitle[rhs.key] ?? "")
            }
            .map { TopSong(title: songTitle[$0.key] ?? "", count: $0.value) }

        // 5) 担当遭遇率 (今年聴けた担当原曲 / 担当原曲総数)。
        let heardSongIds = Set(songEncounter.keys)
        let pickIds = marks.allMarked(kind: .myPick, entity: .idol)
        let pickIdols = (try? await AppContainer.shared.idolReading.idols(ids: pickIds)) ?? []
        var idolLines: [IdolLine] = []
        for idol in pickIdols.prefix(3) {
            let originalIds = ((try? await AppContainer.shared.idolReading.idolSongs(idolId: idol.id, role: "original")) ?? []).map(\.id)
            idolLines.append(IdolLine(
                id: idol.id,
                name: idol.name,
                color: idol.color,
                heard: originalIds.filter { heardSongIds.contains($0) }.count,
                total: originalIds.count
            ))
        }

        return YearWrappedStats(
            year: year,
            showCount: yearShows.count,
            eventCount: eventIds.count,
            liveShowCount: liveShowCount,
            songCount: songCount,
            topSong: topSong,
            idolLines: idolLines
        )
    }
}

// MARK: - カード本体

/// 年間まとめカード。単色 near-black 地に「西暦 (明朝ヒーロー) + 主要 KPI タイル +
/// 最多遭遇曲 + 担当遭遇率バー」を編集的に積む。メンバーカラーは差し色のみ。
struct YearWrappedShareCard: View {
    let stats: YearWrappedStats
    var size: ShareCard.Size = ShareCard.portrait

    private var palette: ShareCardPalette { ShareCardPalette(seed: stats.seed) }
    private let ink = Color.white
    private var ink2: Color { .white.opacity(0.66) }

    /// 正方形 (1:1) は縦が短く全要素が収まりにくいので、ヒーローと縦アキを詰める。
    private var isCompact: Bool { size.height / size.width <= 1.1 }
    /// 縦アキの一括スケール (正方形で詰める)。
    private var vGap: CGFloat { isCompact ? 0.62 : 1.0 }

    var body: some View {
        let palette = self.palette
        SoloShareScaffold(palette: palette, size: size, badge: "年間まとめ") {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 8)

                // ヒーロー: 西暦を明朝で大きく。
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(stats.year))
                        .font(.imasScaled( isCompact ? 82 : 104, weight: .bold, design: .serif).monospacedDigit())
                        .foregroundStyle(ink)
                    Text("年")
                        .font(.imasScaled( isCompact ? 28 : 34, weight: .regular, design: .serif))
                        .foregroundStyle(ink2)
                }
                .minimumScaleFactor(0.7)
                .lineLimit(1)

                Text("参加したライブの記録")
                    .font(.imasScaled( 16, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(ink2)
                    .padding(.top, 2)

                // KPI タイル (公演数 / 回収曲数)。
                HStack(spacing: 14) {
                    metricTile(value: "\(stats.showCount)", unit: "公演",
                               caption: liveCaption)
                    metricTile(value: "\(stats.songCount)", unit: "曲",
                               caption: "聴けた曲")
                }
                .padding(.top, 22 * vGap)

                if let top = stats.topSong {
                    topSongBlock(top)
                        .padding(.top, 24 * vGap)
                }

                if !stats.idolLines.isEmpty {
                    Rectangle().fill(ink.opacity(0.14)).frame(height: 0.75).padding(.top, 24 * vGap)
                    VStack(alignment: .leading, spacing: isCompact ? 11 : 14) {
                        Text("担当の曲、どれだけ聴けた？")
                            .font(.imasScaled( 14, weight: .semibold))
                            .foregroundStyle(ink2)
                        ForEach(stats.idolLines) { line in
                            idolRow(line)
                        }
                    }
                    .padding(.top, 20 * vGap)
                }

                Spacer(minLength: 8)
            }
        }
    }

    /// 現地/配信の内訳キャプション。現地が 0 なら出さない。
    private var liveCaption: String {
        if stats.liveShowCount > 0, stats.liveShowCount < stats.showCount {
            return "うち現地 \(stats.liveShowCount)"
        }
        if stats.liveShowCount == stats.showCount {
            return "すべて現地"
        }
        return "参加した公演"
    }

    private func metricTile(value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.imasScaled( 46, weight: .bold, design: .serif).monospacedDigit())
                    .foregroundStyle(ink)
                Text(unit)
                    .font(.imasScaled( 18, weight: .regular, design: .serif))
                    .foregroundStyle(ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(caption)
                .font(.imasScaled( 13, weight: .medium))
                .foregroundStyle(ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topSongBlock(_ top: YearWrappedStats.TopSong) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle().fill(palette.accent).frame(width: 18, height: 3)
                Text("いちばん多く出会った曲")
                    .font(.imasScaled( 14, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(ink2)
            }
            Text(top.title)
                .font(.imasScaled( 28, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text("\(top.count) 公演で遭遇")
                .font(.imasScaled( 14, weight: .medium).monospacedDigit())
                .foregroundStyle(ink2)
        }
    }

    private func idolRow(_ line: YearWrappedStats.IdolLine) -> some View {
        let fill = Color(hexString: line.color, default: palette.accent)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Circle().fill(fill).frame(width: 10, height: 10)
                Text(line.name)
                    .font(.imasScaled( 16, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer()
                Text("\(line.heard)/\(line.total)曲")
                    .font(.imasScaled( 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.14))
                    Capsule()
                        .fill(fill)
                        .frame(width: max(5, geo.size.width * min(max(line.ratio, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - 年間まとめシェア sheet (MyPage から開く)

/// MyPage の「今年のまとめをシェア」から開く年間まとめ sheet。
/// 既定で今年を表示し、データのある過去年があれば年セグメントで切り替えられる。
struct YearWrappedShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 選択可能な年 (参加実績のある年・降順)。空なら今年だけ出す。
    @State private var availableYears: [Int] = []
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var stats: YearWrappedStats?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.sp5) {
                    if availableYears.count > 1 {
                        Picker("年", selection: $selectedYear) {
                            ForEach(availableYears, id: \.self) { year in
                                Text("\(String(year))年").tag(year)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.sp8)
                    } else if let stats, stats.hasContent {
                        ShareCardActionPane { size in
                            YearWrappedShareCard(stats: stats, size: size)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .navigationTitle("今年のまとめ")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("year_wrapped_share")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await prepareYears() }
            .onChange(of: selectedYear) { _, year in Task { await reload(year: year) } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.sp3) {
            Image(systemName: "calendar.badge.clock")
                .font(.imasScaled( 40))
                .foregroundStyle(DS.ink3)
            Text("この年の参加記録がまだありません")
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
            Text("ライブに「参加した」を付けると、その年のまとめが作れます。")
                .font(.imasFootnote)
                .foregroundStyle(DS.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.sp8)
    }

    /// 参加実績のある年を洗い出し、初期表示年 (今年 → 無ければ最新実績年) を決める。
    private func prepareYears() async {
        let years = await attendedYears()
        availableYears = years
        let thisYear = Calendar.current.component(.year, from: Date())
        selectedYear = years.contains(thisYear) ? thisYear : (years.first ?? thisYear)
        await reload(year: selectedYear)
    }

    private func reload(year: Int) async {
        isLoading = true
        stats = await YearWrappedStats.load(year: year)
        isLoading = false
    }

    /// 参加マークの付いた公演の「年」一覧 (降順・重複なし)。
    private func attendedYears() async -> [Int] {
        let marks = UserMarkService.shared
        let attendedShowIds = Set(marks.allMarked(kind: .attended, entity: .show))
        let attendedEventIds = Set(marks.allMarked(kind: .attended, entity: .event))

        var dates: [String] = []
        for eventId in attendedEventIds {
            dates += ((try? await AppContainer.shared.showReading.shows(eventId: eventId)) ?? []).map(\.date)
        }
        for showId in attendedShowIds {
            if let show = try? await AppContainer.shared.showReading.show(id: showId) { dates.append(show.date) }
        }
        let years = dates.compactMap { Int($0.prefix(4)) }
        return Array(Set(years)).sorted(by: >)
    }
}
