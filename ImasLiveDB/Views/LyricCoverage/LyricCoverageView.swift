import SwiftUI

/// 歌詞の投稿状況 (プロデュース → みんな → 歌詞の投稿状況)。
///
/// 歌詞が公開された曲が、投稿できる曲のうち何曲あるかを全体とブランド別に出して、投稿を呼びかける。
/// どの曲に歌詞があるかは端末に無いので、サーバの公開曲 id (`GET /lyrics/published`、本文なし) を取り、
/// 数えるのはコア (`lyric_coverage`) に任せる。
///
/// 「歌詞あり」の数とブランドの行を押すと、その歌詞のある曲の一覧が開く (一覧の母集合もコアの
/// `lyric_song_ids` で、出ている数と行数が一致する)。
struct LyricCoverageView: View {
    @Environment(AppDatabase.self) private var database

    @State private var coverage: LyricCoverageRecord?
    /// 直近に取れた公開曲 id。一覧を開くときに取り直さない。
    @State private var publishedIds: [String] = []
    @State private var loadFailed = false
    @State private var isLoading = true
    @State private var sheetDestination: DetailDestination?

    var body: some View {
        ImasPage {
            if isLoading && coverage == nil {
                ImasInlineLoading()
            } else if let coverage {
                summarySection(coverage)
                coverageSection(coverage)
                shareSection(coverage)
            }
            if !isLoading && loadFailed {
                ImasNotice(kind: .error, message: "歌詞の投稿状況を取得できませんでした。",
                           actionTitle: "再試行", actionSystemImage: "arrow.clockwise") { Task { await load() } }
            }
        }
        .navigationTitle("歌詞の投稿状況")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .task { await load() }
        .refreshable { await load() }
        .trackScreen("lyric_coverage")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = try await AppContainer.shared.lyricsQuizReading.publishedSongIds()
            coverage = try await AppContainer.shared.statsReading.lyricCoverage(publishedSongIds: ids)
            publishedIds = ids
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// 歌詞のある曲の一覧を開く。`brand` が nil なら全ブランド (並びは 50 音)。
    private func openSongs(brand: BrandLyricCoverageRecord?) {
        AppAnalytics.tap(brand == nil ? "lyric_coverage.songs_all" : "lyric_coverage.songs_brand")
        Task {
            guard let ids = try? await AppContainer.shared.statsReading.lyricSongIds(
                publishedSongIds: publishedIds, brandId: brand?.brandId), !ids.isEmpty else { return }
            let title = brand.map { "歌詞のある曲（\($0.shortName)）" } ?? "歌詞のある曲"
            sheetDestination = .filteredSongs(.songIds(ids, title: title))
        }
    }

    private static func percent(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }

    // MARK: - サマリ

    private func summarySection(_ c: LyricCoverageRecord) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            ImasStatGrid(columns: 3) {
                Button { openSongs(brand: nil) } label: {
                    ImasStatTile(systemImage: "text.quote", value: "\(c.published)", unit: "曲", label: "歌詞あり",
                                 tappable: c.published > 0)
                }
                .buttonStyle(.plain)
                .disabled(c.published == 0)
                ImasStatTile(systemImage: "music.note.list", value: "\(c.eligible)", unit: "曲", label: "投稿できる曲")
                ImasStatTile(systemImage: "chart.bar.fill", value: Self.percent(c.coverage), label: "掲載率")
            }
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text("歌詞はみんなの投稿で増えています。曲の歌詞タブから、CD の歌詞カードなどを見て投稿できます。")
                Text("投稿できるのはアイドルマスターシリーズのオリジナル曲です (カバー曲と別バージョンは数えていません)。公開の反映は 30 分ほど遅れることがあります。")
            }
            .imasText(.meta)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - ブランド別

    private func coverageSection(_ c: LyricCoverageRecord) -> some View {
        ImasSection("ブランド別の掲載率", style: .small,
                    footer: "歌詞のある曲 / 投稿できる曲。ブランドを押すと、歌詞のある曲の一覧が開きます。") {
            ImasCard {
                VStack(spacing: 0) {
                    ForEach(c.brands, id: \.brandId) { b in
                        Button { openSongs(brand: b) } label: {
                            ImasStatBar(label: b.shortName, value: "\(b.published)/\(b.eligible)",
                                        percent: b.coverage * 100, seed: b.color, valueWidth: 64,
                                        tappable: b.published > 0)
                        }
                        .buttonStyle(.plain)
                        .disabled(b.published == 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shareSection(_ c: LyricCoverageRecord) -> some View {
        if c.published > 0 {
            ImasSection("公開された歌詞の内訳", style: .small, footer: "歌詞のある \(c.published) 曲のうち、そのブランドの曲の割合") {
                ImasCard {
                    VStack(spacing: 0) {
                        ForEach(c.brands.filter { $0.published > 0 }, id: \.brandId) { b in
                            ImasStatBar(label: b.shortName, value: Self.percent(b.share),
                                        percent: b.share * 100, seed: b.color, valueWidth: 64)
                        }
                    }
                }
            }
        }
    }
}
