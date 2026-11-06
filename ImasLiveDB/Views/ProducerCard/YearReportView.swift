import SwiftUI

/// 今年の P 活動報告。1 年の記録を 1 枚ずつめくって見せる物語 (全画面)。
///
/// 画面の右を押すと次、左で前、長押しで止める。ページは数秒で次へ進み、最後のまとめ (明るい紙) で止まる。
/// まとめは「画像を書き出す」で SNS に貼る 1 枚にする。中身 (数・題・載せる行・どのページを出すか) はコア
/// (`yearReport`)、部品は DS (`ImasYearReport`)。動きを減らす設定では動かさず、最後の形をそのまま出す。
struct YearReportView: View {
    let initialYear: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: YearReportSource.Loaded?
    @State private var isLoading = true
    @State private var year: Int
    @State private var index = 0
    @State private var progress = 0.0
    @State private var paused = false
    @State private var exportError: String?

    /// 1 ページを見せる長さ (秒)。
    private static let pageSeconds = 6.0

    init(initialYear: Int) {
        self.initialYear = initialYear
        _year = State(initialValue: initialYear)
    }

    var body: some View {
        ImasYearReportBoard {
            if let loaded, !loaded.report.isEmpty {
                let pages = loaded.report.pages
                topBar(loaded, pages: pages)
                page(pages[min(index, pages.count - 1)], loaded: loaded)
                    .id("\(year)-\(index)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(paging(pages: pages))
            } else if isLoading {
                Spacer()
                ImasInlineLoading().frame(maxWidth: .infinity)
                Spacer()
            } else {
                topBarClose
                Spacer()
                Text("\(year) 年に参加した公演はまだありません").imasYearTitle()
                Text("公演に参加の印を付けると、1 年の記録がここにまとまります。").imasYearNote()
                Spacer()
            }
        }
        .task(id: year) { await load() }
        .task(id: "\(year)-\(index)-\(paused)-\(loaded != nil)") { await tick() }
        .imasErrorAlert("画像を書き出せませんでした", message: $exportError)
        .statusBarHidden()
        .trackScreen("year_report")
    }

    // MARK: - 上

    private func topBar(_ loaded: YearReportSource.Loaded, pages: [YearReportPage]) -> some View {
        VStack(spacing: DS.Space.gap) {
            ImasStoryProgress(count: pages.count, index: index, progress: progress)
            HStack {
                if loaded.years.count > 1 {
                    Menu {
                        ForEach(loaded.years, id: \.self) { y in
                            Button("\(String(y)) 年") { year = y }
                        }
                    } label: {
                        Text("\(String(year)) 年 ▾").imasYearImprint()
                    }
                    .accessibilityLabel("ほかの年を開く")
                } else {
                    Text("\(String(year)) 年").imasYearImprint()
                }
                Spacer()
                closeButton
            }
        }
        .padding(.top, DS.Space.gap)
        .padding(.bottom, DS.Space.gapLoose)
    }

    private var topBarClose: some View {
        HStack { Spacer(); closeButton }.padding(.top, DS.Space.gap)
    }

    private var closeButton: some View {
        ImasToolbarButton(systemImage: "xmark", label: "閉じる") { dismiss() }
    }

    // MARK: - ページ

    @ViewBuilder
    private func page(_ page: YearReportPage, loaded: YearReportSource.Loaded) -> some View {
        let r = loaded.report
        let imprint = String(r.year)
        switch page {
        case .shows:
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                Text("\(imprint) · 参加公演").imasYearImprint()
                Text(r.showsTitle).imasYearTitle()
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                    ImasYearCountUp(value: Int(r.showCount), animate: true)
                    Text(r.showsCaption).imasYearNote()
                }
                ImasYearStubRoll(count: r.shows.count, animate: true) { i in
                    let s = r.shows[i]
                    ImasYearStubRow(monthImprint: s.monthImprint, day: Int(s.day), title: s.title,
                                    venue: s.venue, isLocal: s.isLocal)
                }
            }
        case .calendar:
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                Text("\(imprint) · 現場カレンダー").imasYearImprint()
                Text(r.calendarTitle).imasYearTitle()
                ImasYearCalendar(counts: r.months.map { Int($0.count) }, animate: true)
            }
        case .travel:
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                Text("\(imprint) · 遠征").imasYearImprint()
                Text(r.travelTitle).imasYearTitle()
                ImasJapanTileMap(lit: r.prefectures.map { Int($0.code) }, accent: accent(loaded, onBoard: true),
                                 animate: true)
                if let note = r.travelNote {
                    Text(note).imasYearNote()
                }
            }
        case .song:
            VStack(spacing: DS.Space.gapLoose) {
                Text("\(imprint) · いちばん聴いた曲").imasYearImprint()
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let song = r.topSong {
                    ImasJacketFlip(title: song.title, imageURL: song.artworkUrl.flatMap(URL.safeHTTP(string:)),
                                   seed: loaded.accentSeed, animate: true)
                        .padding(.top, DS.Space.gapLoose)
                    Text("「\(song.title)」 \(song.count) 回").imasYearTitle().multilineTextAlignment(.center)
                }
                Text(r.songNote).imasYearNote().multilineTextAlignment(.center)
            }
        case .summary:
            VStack(spacing: DS.Space.gapLoose) {
                summarySheet(loaded, width: 320)
                    .imasStickerFrame()
                    .frame(maxWidth: .infinity)
                ImasButton(title: "画像を書き出す", systemImage: "square.and.arrow.up", role: .primary) {
                    export(loaded)
                }
            }
        }
    }

    private func summarySheet(_ loaded: YearReportSource.Loaded, width: CGFloat) -> ImasYearSummarySheet {
        ImasYearSummarySheet(
            imprint: "P ACTIVITY REPORT · \(loaded.report.year)",
            title: loaded.report.summaryTitle,
            rows: loaded.report.summaryRows.map { .init(label: $0.label, value: $0.value, isNumber: $0.isNumber) },
            accent: accent(loaded, onBoard: false),
            width: width
        )
    }

    private func accent(_ loaded: YearReportSource.Loaded, onBoard: Bool) -> Color {
        let ink = ImasMeishiInk.screen(seed: loaded.accentSeed, brand: loaded.accentBrand)
        return onBoard ? (ink.nightAccent ?? DS.boardInk) : ink.accent
    }

    // MARK: - 操作

    /// 右を押すと次、左で前。長押しの間は止める。
    private func paging(pages: [YearReportPage]) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // まとめのページは書き出しのボタンを押せるよう、めくりは左 (前へ) だけ。
                let onSummary = pages[min(index, pages.count - 1)] == .summary
                if value.location.x < 120 {
                    go(index - 1, pages: pages)
                } else if !onSummary {
                    go(index + 1, pages: pages)
                }
            }
            .simultaneously(with: LongPressGesture(minimumDuration: 0.3)
                .onChanged { _ in paused = true }
                .onEnded { _ in paused = false })
    }

    private func go(_ next: Int, pages: [YearReportPage]) {
        guard next >= 0, next < pages.count else { return }
        progress = 0
        index = next
    }

    /// 今のページの進み具合を進め、満ちたら次へ。止めている間・まとめのページでは進めない。
    private func tick() async {
        guard let pages = loaded?.report.pages, !pages.isEmpty, !paused else { return }
        if pages[min(index, pages.count - 1)] == .summary {
            progress = 1
            return
        }
        let step = 0.05
        while !Task.isCancelled, progress < 1 {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled || paused { return }
            progress = min(1, progress + step / Self.pageSeconds)
        }
        if !Task.isCancelled { go(index + 1, pages: pages) }
    }

    private func load() async {
        isLoading = true
        let next = await YearReportSource.load(year: year)
        index = 0
        progress = 0
        loaded = next
        isLoading = false
        if next != nil { AppAnalytics.tap("year_report.open") }
    }

    private func export(_ loaded: YearReportSource.Loaded) {
        guard let image = ShareCardRenderer.render(summarySheet(loaded, width: 540)) else {
            exportError = "もう一度試すか、アプリを再起動してください。"
            return
        }
        AppAnalytics.tap("year_report.export")
        SystemShare.present(items: [ShareCardImageSource(image), loaded.report.shareText])
    }
}
