import SwiftUI

/// 楽曲詳細の「披露履歴」タブ。総披露 / 初披露 / 最終披露、披露実績から出した
/// 歌唱者と共起曲、そして公演ごとの履歴一覧。
///
/// 節の並びは「数の要約 → 公演の一覧 → 歌った人 → 同じ公演の曲」。開いて最初に見たいのは
/// どのライブで歌われたかなので、一覧を要約のすぐ下に置く (2026-10-02 ユーザー指定)。
///
/// 親の状態は一切触らない。公演/曲/アイドルへの遷移だけ `navigate` で返す。
struct SongHistoryTab: View {
    /// 歌唱者行から「このアイドル × この曲」の履歴へ飛ぶために要る。
    let song: Song
    let seed: String?
    let vm: DetailSheetViewModel
    let navigate: (DetailDestination) -> Void

    var body: some View {
        VStack(spacing: DS.sp5) {
            if vm.history.isEmpty {
                ImasEmptyState(
                    systemImage: "mic",
                    title: "披露履歴はまだありません",
                    message: "この曲がライブで披露されると、ここに記録されます。",
                    seed: seed
                )
            } else {
                summaryTiles
                historySection
                // 披露実績がまだ 1 度も無い曲でだけ中身が空になり、節ごと消える
                // (空の見出しだけが残らないよう if は節の外側に置く)。共有コアの
                // スナップショットが無い間も SQL 経路が同じ値を返すので、節は消えない。
                singersSection
                coOccurringSection
            }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    /// 履歴は新しい順なので、初披露は末尾・最終披露は先頭。
    @ViewBuilder
    private var summaryTiles: some View {
        if let first = vm.history.last?.date, let last = vm.history.first?.date {
            HStack(spacing: DS.sp3) {
                ImasStatTile(systemImage: "mic.fill", value: "\(vm.history.count)", unit: "回", label: "総披露", seed: seed)
                ImasStatTile(systemImage: "calendar", value: ShortYearMonth.format(first), label: "初披露", seed: seed)
                ImasStatTile(systemImage: "calendar.badge.clock", value: ShortYearMonth.format(last), label: "最終披露", seed: seed)
            }
        }
    }

    // MARK: - 歌唱者 (披露実績の集計)

    /// この曲を歌った人を回数の多い順に。行タップで「そのアイドル × この曲」の履歴へ。
    @ViewBuilder
    private var singersSection: some View {
        let rows = vm.performanceEvidence.singers
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "この曲を歌った人", tight: true)
                // 分母 (全 N 回) は上のサマリタイル「総披露」と同じ数え方。同じ画面に
                // 単位の違う数字 (共起節は公演数) が並ぶので、どちらなのかを言っておく。
                ImasNote("セトリに残っている歌唱の集計です。分母は上の「総披露」と同じ回数です。")
                ImasCardList {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5 + 36) }
                        Button {
                            AppAnalytics.tap("song_detail.singer_tally")
                            navigate(.idolSongHistory(row.idol, song))
                        } label: {
                            // 副題が根拠。「よく歌う人」ではなく「何回歌ったか」を出す。
                            IdolNameRow(idol: row.idol, subtitle: "\(row.times)回 ／ 全\(row.total)回")
                        }
                        .buttonStyle(.imasRow)
                    }
                }
            }
        }
    }

    // MARK: - 共起曲 (披露実績の集計)

    /// この曲と同じ公演で歌われた曲を、一緒に来た**公演数**の多い順に。
    @ViewBuilder
    private var coOccurringSection: some View {
        let rows = vm.performanceEvidence.coOccurring
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "同じ公演で歌われた曲", tight: true)
                // ⚠️ ここだけ単位が「公演」。1 公演で 2 回演奏されても 1 と数えるため、
                // 相手の曲を開いた先の「総披露 N 回」(セトリ行数) より小さい数になる
                // (同梱 master で 48 曲がこのズレを持つ。例: 初 = 39 公演 / 64 回)。
                // 単位を書かないと「どちらが本当の回数か」が読み手に判断できない。
                ImasNote("同じ公演に両方あった公演数です (1 公演で 2 回歌っても 1 公演)。次のライブで一緒に来るとは限りません。")
                ImasCardList {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5 + 44) }
                        Button {
                            AppAnalytics.tap("song_detail.co_occurring")
                            navigate(.song(row.song))
                        } label: {
                            coOccurringRow(row)
                        }
                        .buttonStyle(.imasRow)
                    }
                }
            }
        }
    }

    /// 共起曲の 1 行。`RelatedSongRow` と同じ形だが、副題は歌唱表記ではなく**根拠の回数**。
    /// この行が並んでいる理由そのものが回数なので、歌唱表記よりそちらを副題の位置に置く。
    private func coOccurringRow(_ row: CoOccurringSong) -> some View {
        ImasSongRow(
            title: row.song.title,
            subtitle: "いっしょに\(row.together)公演 ／ 全\(row.performances)公演",
            artworkURL: URL.safeHTTP(string: row.song.artworkUrl),
            brandHex: seed,
            trailing: .chevron,
            density: .compact
        ) {
            EmptyView()
        }
    }

    // MARK: - 生ログ

    private var historySection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ライブ披露履歴", count: "\(vm.history.count)回", tight: true)
            ImasCardList {
                ForEach(Array(vm.history.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                    historyRow(row)
                }
            }
        }
    }

    private func historyRow(_ row: PerformanceHistoryRow) -> some View {
        Button {
            Task { if let show = await vm.resolveShow(id: row.showId) { navigate(.show(show)) } }
        } label: {
            ImasRow(
                title: eventDisplayName(row.eventName),
                subtitle: [row.showName, row.date].joined(separator: " ・ "),
                leading: .bar(seed: seed),
                trailing: .chevron,
                density: .compact
            )
        }
        .buttonStyle(.imasRow)
    }
}
