import SwiftUI

/// 楽曲詳細の「披露履歴」タブ。総披露 / 初披露 / 最終披露、披露実績から出した
/// 歌唱者と共起曲、そして公演ごとの履歴一覧。
///
/// 節の並びは「集計 → 集計 → 集計 → 生ログ」。人気曲の履歴は 100 行を超えるので、
/// 要約を先に置かないと集計まで辿り着けない。
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
                // 披露実績が無い曲・スナップショット未ロードでは中身が空になり、
                // 節ごと消える (空の見出しだけが残らないよう if は節の外側に置く)。
                singersSection
                coOccurringSection
                historySection
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
                evidenceNote("セトリに残っている歌唱の集計です。")
                ImasListContainer {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5 + 36) }
                        Button {
                            AppAnalytics.tap("song_detail.singer_tally")
                            navigate(.idolSongHistory(row.idol, song))
                        } label: {
                            // 副題が根拠。「よく歌う人」ではなく「何回歌ったか」を出す。
                            IdolNameRow(idol: row.idol, subtitle: "\(row.times)回 ／ 全\(row.total)回")
                                .padding(.horizontal, DS.sp5)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 共起曲 (披露実績の集計)

    /// この曲と同じ公演で歌われた曲を、一緒に来た回数の多い順に。
    @ViewBuilder
    private var coOccurringSection: some View {
        let rows = vm.performanceEvidence.coOccurring
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "同じ公演で歌われた曲", tight: true)
                evidenceNote("これまでに同じ公演で歌われた回数です。次のライブで一緒に来るとは限りません。")
                ImasListContainer {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5 + 44) }
                        Button {
                            AppAnalytics.tap("song_detail.co_occurring")
                            navigate(.song(row.song))
                        } label: {
                            coOccurringRow(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 共起曲の 1 行。`RelatedSongRow` と同じ形だが、副題は歌唱表記ではなく**根拠の回数**。
    /// この行が並んでいる理由そのものが回数なので、歌唱表記よりそちらを副題の位置に置く。
    private func coOccurringRow(_ row: CoOccurringSong) -> some View {
        HStack(spacing: DS.sp3) {
            ImasArtwork(title: row.song.title, seed: seed, size: 44,
                        imageURL: URL.safeHTTP(string: row.song.artworkUrl))
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(row.song.title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                // 分母まで出す。12/15 回 (ほぼ必ず一緒) と 12/300 回 (たまたま) は別物で、
                // 回数だけだと読み手が区別できない。
                Text("いっしょに\(row.together)回 ・ 通算\(row.performances)回の披露")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ImasRowChevron()
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - 生ログ

    private var historySection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ライブ披露履歴", count: "\(vm.history.count)回", tight: true)
            ImasListContainer {
                ForEach(Array(vm.history.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                    historyRow(row)
                }
            }
        }
    }

    /// 集計の但し書き。回数だけ並べると「予想」と読まれうるので、過去の実績だと明示する。
    private func evidenceNote(_ text: String) -> some View {
        Text(text)
            .font(.imasCaption)
            .foregroundStyle(DS.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func historyRow(_ row: PerformanceHistoryRow) -> some View {
        Button {
            Task { if let show = await vm.resolveShow(id: row.showId) { navigate(.show(show)) } }
        } label: {
            HStack(spacing: 0) {
                ImasLeadBar(seed: seed)
                    .frame(height: 34)
                    .padding(.trailing, DS.sp4)
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(eventDisplayName(row.eventName)).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                    Text([row.showName, row.date].joined(separator: " ・ "))
                        .font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                ImasRowChevron()
            }
            .padding(.horizontal, DS.sp4).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
