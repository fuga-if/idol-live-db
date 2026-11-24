import os
import SwiftUI

/// 未回収曲の一覧 (回収ダッシュボードのブランド別の回収率のバー・「すべて見る」の先)。
///
/// 数え方は原曲単位 (imas-core `uncollected_songs`)。いま回収できる曲 (披露済み) と、
/// まだ披露されていない曲を分けて並べ、ver 違いは原曲の行の下にたたむ。
struct UncollectedSongsView: View {
    enum Scope: Hashable {
        /// ブランドを問わない全曲。
        case all
        /// 根の曲がこのブランドのもの。
        case brand(id: String, name: String, color: String?)
        /// 担当のオリ曲。
        case myPick
    }

    let scope: Scope

    @Environment(AppDatabase.self) private var database
    @State private var list: UncollectedSongList?
    @State private var failed = false
    @State private var brands: [Brand] = []
    @State private var expanded: Set<String> = []
    @State private var selectedSong: Song?

    var body: some View {
        ImasPage {
            if let list {
                summary(list)
                if list.uncollectedCount == 0 {
                    ImasCard {
                        ImasEmptyState(systemImage: "checkmark.seal", title: "コンプリート！",
                                       message: "ここにある曲はすべて生で聴けています。")
                    }
                } else {
                    if !list.performed.isEmpty {
                        ImasSection("回収できる曲", count: "\(list.performed.count)曲", style: .small,
                                    footer: "ライブで披露されたことのある曲です。披露の多い順。") {
                            songList(list.performed)
                        }
                    }
                    if !list.unperformed.isEmpty {
                        ImasSection("まだ披露されていない曲", count: "\(list.unperformed.count)曲", style: .small,
                                    footer: "リアルライブでまだ一度も披露されていない曲です。") {
                            songList(list.unperformed)
                        }
                    }
                }
            } else if failed {
                ImasCard {
                    ImasEmptyState(.failed, title: "未回収曲を読み込めませんでした", message: "もう一度開いてください。")
                }
            } else {
                ImasInlineLoading()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $selectedSong) { song in
            DetailSheetView(destination: .song(song))
                .environment(database)
        }
        .trackScreen("uncollected_songs")
    }

    // MARK: - 上の回収率

    private func summary(_ list: UncollectedSongList) -> some View {
        let p = list.progress
        return VStack(alignment: .leading, spacing: DS.Space.gap) {
            ImasBoard(cells: [
                .init(value: "\(p.collected)/\(p.total)", unit: "曲", label: "全曲（\(Self.percent(p.fraction))%）"),
                .init(value: "\(p.performedCollected)/\(p.performedTotal)", unit: "曲",
                      label: "披露済み（\(Self.percent(p.performedFraction))%）"),
            ])
            ImasNote("ユニットVer.・Game Size などの ver 違いは原曲にまとめて数えます。どれか 1 つを生で聴けば回収です。")
        }
    }

    private static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }

    // MARK: - 曲の一覧

    private func songList(_ rows: [UncollectedSong]) -> some View {
        ImasCardList(rows) { item in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    selectedSong = item.song
                } label: {
                    ImasSongRow(
                        song: item.song,
                        subtitle: subtitle(item.song),
                        playsPreview: false,
                        trailing: .custom(AnyView(UncollectedFrequencyBadge(item: item)))
                    )
                }
                .buttonStyle(.imasRow)
                if !item.variants.isEmpty {
                    variants(item)
                }
            }
        }
    }

    @ViewBuilder
    private func variants(_ item: UncollectedSong) -> some View {
        let isExpanded = Binding(
            get: { expanded.contains(item.id) },
            set: { open in
                if open { expanded.insert(item.id) } else { expanded.remove(item.id) }
            }
        )
        ImasRowDivider(inset: DS.Space.rowH)
        ImasDisclosureRow(title: "ver違い", count: "\(item.variants.count)曲・すべて未回収", isExpanded: isExpanded)
        if isExpanded.wrappedValue {
            ForEach(item.variants) { variant in
                Button {
                    selectedSong = variant.song
                } label: {
                    ImasSongRow(
                        song: variant.song,
                        playsPreview: false,
                        trailing: variant.playCount > 0
                            ? .metric("\(variant.playCount)", unit: "回披露")
                            : .badge(ImasBadge(text: "未披露", kind: .negative)),
                        density: .compact
                    )
                }
                .buttonStyle(.imasRow)
                .environment(\.imasRowPosition, .following)
            }
        }
    }

    /// 行の副題。ブランドで絞った一覧では歌唱者 (既定)、それ以外はブランド名。
    private func subtitle(_ song: Song) -> String? {
        if case .brand = scope { return nil }
        guard let brandId = song.brandId else { return nil }
        return brands.first(where: { $0.id == brandId })?.shortName
    }

    private var title: String {
        let name: String
        switch scope {
        case .all: name = "全ブランド"
        case let .brand(_, brandName, _): name = brandName
        case .myPick: name = "担当のオリ曲"
        }
        guard let list else { return "\(name)の未回収" }
        return "\(name)の未回収 \(list.uncollectedCount)曲"
    }

    // MARK: - 読み込み

    private func load() async {
        let coreScope: CollectionScope
        switch scope {
        case .all: coreScope = .all
        case let .brand(id, _, _): coreScope = .brand(brandId: id)
        case .myPick: coreScope = .myPick(idolIds: Array(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol)))
        }
        do {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            list = try await AppContainer.shared.statsReading.uncollectedSongs(
                collectedSongIds: UserMarkService.shared.autoCollectedSongIds(), scope: coreScope)
            failed = false
            #if DEBUG
            // シミュレータで ver 違いを開いた形を撮るため (`UNCOLLECTED_EXPAND_FIRST=1`)。
            if ProcessInfo.processInfo.environment["UNCOLLECTED_EXPAND_FIRST"] == "1",
               let first = list?.performed.first(where: { !$0.variants.isEmpty }) {
                expanded.insert(first.id)
            }
            #endif
        } catch {
            Logger.database.error("load_failed uncollected_songs: \(error.localizedDescription)")
            failed = true
        }
    }
}

/// 未回収曲の披露頻度の札と披露回数 (回収ダッシュボードと未回収一覧で共有)。
/// 定番=attention(墨の線)、ときどき=neutral(灰)、レア/未披露=negative(薄字)。
struct UncollectedFrequencyBadge: View {
    let item: UncollectedSong

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
            ImasBadge(text: item.frequencyLabel, kind: kind)
            if item.playCount > 0 {
                ImasMetric(value: "\(item.playCount)", unit: "回披露", size: .small)
            }
        }
    }

    private var kind: ImasBadge.Kind {
        switch item.frequency {
        case .staple: .attention
        case .sometimes: .neutral
        case .rare, .never: .negative
        }
    }
}
