import os
import SwiftUI

/// 「今日は何の日？」— 選んだ日と同じ月日の、過去の記念日・誕生日・ライブ・リリース。
///
/// 何を拾うか・何年前か・共有文 (X の文字数に収める畳み方まで) はコア (`on_this_day.rs`)。
/// ここは返ってきたものを区画に並べ、行から詳細へ進ませるだけ。
/// 左右に払うか見出しの矢印で前後の日へ送れる。
struct OnThisDaySheet: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State var date: Date
    @State private var digest: OnThisDayDigest?
    @State private var path: [DetailDestination] = []

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack(path: $path) {
            ImasPage {
                header
                if let digest {
                    if isEmpty(digest.day) {
                        ImasEmptyState(
                            systemImage: "calendar",
                            title: "記録なし",
                            message: "この日にあった記念日・ライブ・リリースはまだ記録がありません"
                        )
                    } else {
                        sections(digest)
                    }
                } else {
                    ImasInlineLoading(tint: DS.sys)
                }
            }
            // 横に払って前後の日へ (縦のスクロールは邪魔しない)。
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                    shiftDay(value.translation.width < 0 ? 1 : -1)
                }
            )
            .navigationTitle("何の日")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .toolbar {
                if let share = digest?.day.share {
                    ToolbarItem(placement: .topBarTrailing) {
                        SocialShareMenu(payload: share, analyticsKey: "on_this_day.share") {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("この日をシェア")
                    }
                }
            }
            .navigationDestination(for: DetailDestination.self) { dest in
                DetailContentView(destination: dest) { path.append($0) }
            }
        }
        .task(id: date) { await load() }
        .trackScreen("on_this_day")
    }

    // MARK: - 頭

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.gap) {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                ImasMasthead(items: ["ON THIS DAY", mastheadDay])
                Text(digest?.day.title ?? "")
                    .imasText(.heroTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ImasIconButton(systemImage: "chevron.left", label: "前の日", size: .small) { shiftDay(-1) }
            ImasIconButton(systemImage: "chevron.right", label: "次の日", size: .small) { shiftDay(1) }
        }
    }

    /// 印字の日付 (`2026.10.04`)。
    private var mastheadDay: String {
        (digest?.day.day ?? "").replacingOccurrences(of: "-", with: ".")
    }

    // MARK: - 区画

    @ViewBuilder
    private func sections(_ digest: OnThisDayDigest) -> some View {
        let day = digest.day
        if !day.anniversaries.isEmpty {
            ImasSection("記念日", count: "\(day.anniversaries.count)件") {
                ImasCardList(day.anniversaries, id: \.anniversaryId) { ann in
                    ImasRow(
                        title: ann.label,
                        subtitle: yearMonthDay(ann.originDate),
                        leadBar: ImasRowLeadBar(brand: BrandColors.hex(for: ann.brandId)),
                        trailing: .metric("\(ann.years)", unit: ann.unit, emphasized: true)
                    ) { EmptyView() }
                }
            }
        }
        let idols = day.birthdays.compactMap { digest.idols[$0.idolId] }
        if !idols.isEmpty {
            ImasSection("誕生日", count: "\(idols.count)人") {
                ImasCardList(idols, id: \.id) { idol in
                    Button { open(.idol(idol)) } label: {
                        ImasIdolRow(idol: idol, brand: BrandColors.hex(for: idol.brandId), trailing: .chevron)
                    }
                    .buttonStyle(.imasRow)
                }
            }
        }
        if !day.lives.isEmpty {
            ImasSection("ライブ", count: "\(day.lives.count)件") {
                VStack(spacing: DS.Space.gap) {
                    ForEach(day.lives, id: \.showIds) { live in
                        Button { openEvent(live.eventId) } label: {
                            ImasShowRow(
                                date: live.date,
                                title: [live.eventName, live.showLabel].compactMap { $0 }.joined(separator: " "),
                                subtitle: [ago(live.years, from: live.date), live.venue].compactMap { $0 }
                                    .joined(separator: " ・ "),
                                brandHex: BrandColors.hex(for: live.brandId),
                                rainbow: live.isJoint,
                                showsChevron: true,
                                subtitleLineLimit: 2
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        let releaseSongs = day.releases.flatMap { release in
            release.songIds.compactMap { digest.songs[$0] }.map { (song: $0, release: release) }
        }
        if !releaseSongs.isEmpty {
            ImasSection("リリース", count: "\(releaseSongs.count)曲") {
                ImasCardList(releaseSongs, id: \.song.id) { item in
                    Button { open(.song(item.song)) } label: {
                        ImasSongRow(song: item.song) {
                            Text(ago(item.release.years, from: item.release.date)).imasText(.meta)
                        }
                    }
                    .buttonStyle(.imasRow)
                }
            }
        }
    }

    // MARK: - 文言

    /// 「2014年 ・ 12年前」。
    private func ago(_ years: UInt32, from date: String) -> String {
        "\(date.prefix(4))年 ・ \(years)年前"
    }

    /// 起点日 `2024-10-04` → 「2024年10月4日」。
    private func yearMonthDay(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return date }
        return "\(parts[0])年\(parts[1])月\(parts[2])日"
    }

    private func isEmpty(_ day: OnThisDay) -> Bool {
        day.anniversaries.isEmpty && day.birthdays.isEmpty && day.lives.isEmpty && day.releases.isEmpty
    }

    // MARK: - 操作

    private func shiftDay(_ offset: Int) {
        guard let next = calendar.date(byAdding: .day, value: offset, to: date) else { return }
        AppAnalytics.tap("on_this_day.shift_day")
        date = next
    }

    private func open(_ dest: DetailDestination) {
        path.append(dest)
    }

    private func openEvent(_ eventId: String) {
        Task {
            if let event = try? await AppContainer.shared.eventReading.event(id: eventId) {
                open(.event(event))
            }
        }
    }

    private func load() async {
        do {
            digest = try await AppContainer.shared.calendarReading.onThisDay(date)
        } catch {
            Logger.database.error("load_failed on_this_day: \(error.localizedDescription)")
        }
    }
}
