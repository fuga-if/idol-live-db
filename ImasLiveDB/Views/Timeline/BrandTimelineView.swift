import os
import SwiftUI

// =============================================================================
// 年表 (ブランド史)。
//
// 横軸 = 時間、縦 = スイムレーン (節目 / ライブ / 楽曲 / その他) の俯瞰チャート。
// 「いつ何が重なっていたか」を 1 枚で感じ取らせるのが目的なので、リストではなく
// 帯 + 点で密度そのものを見せる。年ルーラーは上に、レーン名は左に貼り付いたまま残る。
//
// ⚠️ スクロールに `ScrollView` を使っていないのは意図的。
// 貼り付くルーラー/レールは本体と同じスクロール量で動かないと即座に破綻するが、
// `ScrollView` のスクロール量を `GeometryReader` + `PreferenceKey` で外に出す方法は
// スクロール中に更新が来ず、ルーラーだけ 2004 年を指したまま本体が 2026 年まで
// 流れていく (実機で確認済み)。パン量を自前の状態として持てば 3 者は定義上ずれない。
//
// 座標系: キャンバス左上を原点とした pt。日付 → x は TimelineLayout が担当し、
// 行詰め (帯が重ならない段の割り当て) も同じく純粋関数側にある。
// =============================================================================

struct BrandTimelineView: View {
    @Environment(AppDatabase.self) private var database

    @State private var viewModel: BrandTimelineViewModel

    /// キャンバスのパン量 (pt)。正の値 = 右/下へ進んだ量。ルーラー・レール・本体が共有する唯一の真実。
    @State private var pan: CGPoint = .zero
    /// 1 日あたりの pt。ピンチとズームメニューで変わる唯一の倍率。
    @State private var pointsPerDay: Double = Metrics.defaultPointsPerYear / 365.25

    /// ドラッグ開始時のパン量 (ドラッグ中の基準)。
    @State private var panAtDragStart: CGPoint?
    /// ピンチ開始時の倍率と、画面中央に見えていた日付 (ズーム後もそこを中央に保つ)。
    @State private var pinchStart: (pointsPerDay: Double, centerDate: Date)?

    /// 直近に測ったプロット領域のサイズ (ジェスチャ内でクランプに使う)。
    @State private var plotSize: CGSize = .zero

    /// 表示中の帯をタップして開く詳細シート (イベント / 楽曲シリーズ とも同じ入口)。
    @State private var sheetDestination: DetailDestination?

    init(initialBrandId: String? = nil) {
        _viewModel = State(wrappedValue: BrandTimelineViewModel(initialBrandId: initialBrandId))
    }

    // MARK: - 寸法

    private enum Metrics {
        /// 既定のズーム (1 年あたりの pt)。iPhone 縦で 4 年弱が視野に入る密度。
        static let defaultPointsPerYear: Double = 100
        static let minPointsPerYear: Double = 24
        static let maxPointsPerYear: Double = 2400
        /// 帯 1 本分の行の高さ (ラベル + バー)。
        static let rowHeight: Double = 30
        /// ラベルを描かないズームでの行の高さ (バーだけ)。
        static let compactRowHeight: Double = 13
        /// レーン上下の余白。
        static let lanePadding: Double = 9
        /// 左に貼り付くレーン名の幅。
        static let railWidth: Double = 54
        /// 上に貼り付く年ルーラーの高さ。
        static let rulerHeight: Double = 26
        /// 単日の出来事でも最低これだけの幅を持たせる。タップ領域も兼ねる。
        static let minBarWidth: Double = 18
        /// タップ判定を横方向にだけ広げる遊び。広げすぎると隣の帯を誤爆する。
        static let tapSlop: Double = 6
        /// 俯瞰ズーム (ラベル非表示) での最低幅。ここを 18pt のままにすると、時間軸を
        /// 縮めても帯だけ縮まないので重なりが増え、全体表示にするほど段数が増える
        /// という逆転が起きる。俯瞰では点として見えれば十分。
        static let compactMinBarWidth: Double = 4
        /// 帯とラベルの間、隣の帯との最低距離。
        static let packGap: Double = 8
        /// 俯瞰ズームでの帯どうしの最低距離。
        static let compactPackGap: Double = 2
        /// ラベルが占有できる最大幅。長いライブ名をそのまま占有幅に入れると行詰めが
        /// 破綻して段数が爆発するため、ここで頭打ちにして重なりは省略記号に委ねる。
        static let maxLabelWidth: Double = 150
        /// これより粗いズームではラベルを描かない (団子になるだけで読めないため)。
        static let labelVisiblePointsPerYear: Double = 64
        static let labelFontSize: Double = 10.5
        static let barThickness: Double = 7
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            Divider()
            chartArea
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(viewModel.selectedBrand?.shortName.appending("の年表") ?? "年表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { zoomMenu }
        }
        .task { await viewModel.loadIfNeeded() }
        // 年表からの遷移はハーフモーダルに統一する。年表は「見比べる」画面なので、
        // 押した先が全画面 push だと戻るまで俯瞰が失われる。半分だけ開けば、
        // 下に年表を見せたまま中身を確認して閉じられる。
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .trackScreen("brand_timeline")
    }

    // MARK: - ブランド切替

    private var brandBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.sp2) {
                ImasFilterChip(text: "全ブランド", isSelected: viewModel.selectedBrandId == nil) {
                    Task { await select(nil) }
                }
                ForEach(viewModel.brands) { brand in
                    ImasFilterChip(
                        text: brand.shortName,
                        isSelected: viewModel.selectedBrandId == brand.id,
                        seed: brand.color
                    ) {
                        Task { await select(brand.id) }
                    }
                }
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, DS.sp3)
        }
        .background(DS.surface)
    }

    private func select(_ brandId: String?) async {
        await viewModel.select(brandId: brandId)
        jumpToNow()
    }

    // MARK: - ズーム操作

    private var zoomMenu: some View {
        Menu {
            Button("今へ", systemImage: "location") { jumpToNow() }
            Divider()
            Button("全体を表示", systemImage: "arrow.left.and.right") { zoomToFit() }
            Button("標準", systemImage: "1.magnifyingglass") { setPointsPerYear(Metrics.defaultPointsPerYear) }
            Button("拡大", systemImage: "plus.magnifyingglass") { setPointsPerYear(560) }
        } label: {
            Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
        }
        .accessibilityLabel("表示倍率")
    }

    private func setPointsPerYear(_ value: Double) {
        let center = centerDate
        withAnimation(.easeInOut(duration: 0.2)) {
            pointsPerDay = clampPointsPerDay(value / 365.25)
            recenter(on: center)
        }
    }

    private func zoomToFit() {
        guard let plan = layout(pointsPerDay: pointsPerDay), plan.totalDays > 0, plotSize.width > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            pointsPerDay = clampPointsPerDay(
                TimelineLayout.fitPointsPerDay(spanDays: plan.totalDays, width: plotSize.width)
            )
            pan.x = 0
        }
    }

    /// 「今」が画面の中央付近に来るようにパンする。
    private func jumpToNow() {
        guard let plan = layout(pointsPerDay: pointsPerDay) else { return }
        let x = TimelineLayout.x(for: Date(), origin: plan.origin, pointsPerDay: pointsPerDay)
        withAnimation(.easeInOut(duration: 0.25)) {
            pan.x = clampPanX(x - plotSize.width * 0.6, canvasWidth: plan.canvasWidth)
            pan.y = 0
        }
    }

    private func clampPointsPerDay(_ value: Double) -> Double {
        min(max(value, Metrics.minPointsPerYear / 365.25), Metrics.maxPointsPerYear / 365.25)
    }

    private func clampPanX(_ value: Double, canvasWidth: Double) -> Double {
        min(max(value, 0), max(canvasWidth - plotSize.width, 0))
    }

    private func clampPanY(_ value: Double, canvasHeight: Double) -> Double {
        min(max(value, 0), max(canvasHeight - plotSize.height, 0))
    }

    /// いま画面中央に見えている日付。ズームの支点に使う。
    private var centerDate: Date {
        guard let plan = layout(pointsPerDay: pointsPerDay) else { return Date() }
        return TimelineLayout.date(atX: pan.x + plotSize.width / 2, origin: plan.origin, pointsPerDay: pointsPerDay)
    }

    /// 指定の日付が画面中央に来るようにパンを取り直す (ズーム時に視点を保つ)。
    private func recenter(on date: Date) {
        guard let plan = layout(pointsPerDay: pointsPerDay) else { return }
        let x = TimelineLayout.x(for: date, origin: plan.origin, pointsPerDay: pointsPerDay)
        pan.x = clampPanX(x - plotSize.width / 2, canvasWidth: plan.canvasWidth)
    }

    // MARK: - チャート本体

    @ViewBuilder
    private var chartArea: some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let plot = CGSize(width: max(viewport.width - Metrics.railWidth, 1),
                              height: max(viewport.height - Metrics.rulerHeight, 1))
            Group {
                if let plan = layout(pointsPerDay: pointsPerDay), !plan.placed.isEmpty {
                    ZStack(alignment: .topLeading) {
                        // 本体
                        layer(size: plot, dx: -pan.x, dy: -pan.y) { canvas(plan: plan, plot: plot) }
                            .offset(x: Metrics.railWidth, y: Metrics.rulerHeight)
                        // 上に貼り付く年ルーラー (横だけ追従)
                        layer(size: CGSize(width: plot.width, height: Metrics.rulerHeight), dx: -pan.x, dy: 0) {
                            ruler(plan: plan)
                        }
                        .background(DS.surface)
                        .overlay(alignment: .bottom) { Rectangle().fill(DS.sep).frame(height: 1) }
                        .offset(x: Metrics.railWidth, y: 0)
                        // 左に貼り付くレーン名 (縦だけ追従)
                        layer(size: CGSize(width: Metrics.railWidth, height: plot.height), dx: 0, dy: -pan.y) {
                            rail(plan: plan)
                        }
                        .background(DS.surface)
                        .overlay(alignment: .trailing) { Rectangle().fill(DS.sep).frame(width: 1) }
                        .offset(x: 0, y: Metrics.rulerHeight)
                        // 左上の角 (ルーラーとレールの交差部)
                        Rectangle().fill(DS.surface)
                            .frame(width: Metrics.railWidth, height: Metrics.rulerHeight)
                    }
                    .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    // パンを優先し、指が動かなかったときだけタップとして扱う。
                    // 帯 1 本ずつを Button にすると、少し滑らせただけの操作でも
                    // 指を離した瞬間に発火して誤爆する (実機で「すぐ押しちゃう」状態)。
                    .gesture(ExclusiveGesture(panGesture(plan: plan), tapGesture(plan: plan, plot: plot)))
                    .simultaneousGesture(zoomGesture)
                    .onAppear {
                        plotSize = plot
                        jumpToNow()
                    }
                    .onChange(of: plot) { _, new in plotSize = new }
                } else {
                    emptyOrLoading.frame(width: viewport.width, height: viewport.height)
                }
            }
        }
    }

    /// 「窓 (size) の中に、content を (dx, dy) だけずらして置いて切り取る」共通レイヤ。
    private func layer<Content: View>(
        size: CGSize,
        dx: Double,
        dy: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(x: dx, y: dy)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if viewModel.isLoading {
            ImasLoadingState()
        } else {
            ImasEmptyState(
                systemImage: "chart.bar.xaxis",
                title: "年表を描けるデータがありません",
                message: "このブランドにはまだライブ・楽曲の日付が登録されていません。"
            )
        }
    }

    // MARK: ジェスチャ

    /// パン。指を離したら慣性で少し滑らせる。
    ///
    /// `minimumDistance` は小さめ。ここを大きくすると「スクロールしたつもりが
    /// タップ扱い」になる範囲が広がる (ExclusiveGesture はパンが成立しなかった時だけ
    /// タップに落ちるので、この値がそのまま誤タップの許容半径になる)。
    private func panGesture(plan: TimelinePlan) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let base = panAtDragStart ?? pan
                if panAtDragStart == nil { panAtDragStart = pan }
                pan = CGPoint(
                    x: clampPanX(base.x - value.translation.width, canvasWidth: plan.canvasWidth),
                    y: clampPanY(base.y - value.translation.height, canvasHeight: plan.canvasHeight)
                )
            }
            .onEnded { value in
                let base = panAtDragStart ?? pan
                panAtDragStart = nil
                let projected = CGPoint(
                    x: clampPanX(base.x - value.predictedEndTranslation.width, canvasWidth: plan.canvasWidth),
                    y: clampPanY(base.y - value.predictedEndTranslation.height, canvasHeight: plan.canvasHeight)
                )
                withAnimation(.easeOut(duration: 0.45)) { pan = projected }
            }
    }

    /// タップ。キャンバス側で 1 回だけヒットテストする。
    ///
    /// 帯ごとに Button を置く方式はやめた。Button はタッチダウンで反応してしまい、
    /// 少し滑らせる操作でも指を離した瞬間に開いてしまう。ここでは「パンが成立しなかった
    /// 操作」= 純粋なタップだけがこの経路に来る。
    private func tapGesture(plan: TimelinePlan, plot: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                guard let bar = hitTest(at: value.location, plan: plan, plot: plot) else { return }
                open(bar)
            }
    }

    /// 画面上の点 → その位置にある帯。ルーラー/レールの領域は対象外。
    private func hitTest(at point: CGPoint, plan: TimelinePlan, plot: CGSize) -> TimelineBar? {
        guard point.x >= Metrics.railWidth, point.y >= Metrics.rulerHeight else { return nil }
        // 画面座標 → キャンバス座標 (貼り付くヘッダーぶんを引いて、パン量を足す)。
        let x = point.x - Metrics.railWidth + pan.x
        let y = point.y - Metrics.rulerHeight + pan.y

        let targets = plan.placed.filter { $0.bar.target != .none }
        let boxes = targets.map {
            TimelineLayout.HitBox(x: $0.x, width: $0.barWidth, y: $0.y, height: plan.rowHeight)
        }
        guard let index = TimelineLayout.hitIndex(x: x, y: y, boxes: boxes, slop: Metrics.tapSlop) else {
            return nil
        }
        return targets[index].bar
    }

    /// ピンチズーム。画面中央の日付を支点に保つ。
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (pointsPerDay, centerDate)
                if pinchStart == nil { pinchStart = start }
                pointsPerDay = clampPointsPerDay(start.pointsPerDay * value.magnification)
                recenter(on: start.centerDate)
            }
            .onEnded { _ in pinchStart = nil }
    }

    // MARK: キャンバス (グリッド + 帯)

    private func canvas(plan: TimelinePlan, plot: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            laneBands(plan: plan)
            yearColumns(plan: plan)
            todayLine(plan: plan)
            bars(plan: plan, plot: plot)
        }
        .frame(width: plan.canvasWidth, height: max(plan.canvasHeight, plot.height), alignment: .topLeading)
    }

    /// レーンごとの背景バンド。交互に薄く塗って行を追いやすくする。
    private func laneBands(plan: TimelinePlan) -> some View {
        ForEach(Array(plan.lanes.enumerated()), id: \.element.lane) { index, lane in
            Rectangle()
                .fill(index.isMultiple(of: 2) ? Color.clear : DS.fill.opacity(0.4))
                .frame(width: plan.canvasWidth, height: lane.height)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.sep).frame(height: 1) }
                .offset(y: lane.y)
        }
    }

    /// 年の区切り線。
    private func yearColumns(plan: TimelinePlan) -> some View {
        ForEach(plan.years, id: \.year) { tick in
            Rectangle()
                .fill(DS.sep.opacity(0.7))
                .frame(width: 1, height: plan.canvasHeight)
                .offset(x: tick.x)
        }
    }

    @ViewBuilder
    private func todayLine(plan: TimelinePlan) -> some View {
        if let x = plan.todayX {
            Rectangle()
                .fill(DS.pick.opacity(0.7))
                .frame(width: 1.5, height: plan.canvasHeight)
                .offset(x: x)
        }
    }

    /// 帯。見えている x 範囲に掛かるものだけ描く。
    /// 判定に使う `pan` は自前の状態なので、描画とズレることがない。
    private func bars(plan: TimelinePlan, plot: CGSize) -> some View {
        let minX = pan.x - plot.width
        let maxX = pan.x + plot.width * 2
        let visible = plan.placed.filter { $0.x + $0.barWidth + $0.labelWidth >= minX && $0.x <= maxX }
        return ForEach(visible) { placed in
            TimelineBarView(
                placed: placed,
                pointsPerDay: plan.pointsPerDay,
                rowHeight: plan.rowHeight,
                showsMarks: plan.pointsPerDay * 30 > 6,
                barThickness: Metrics.barThickness,
                labelFontSize: Metrics.labelFontSize,
                // 左端で切れている帯は、ラベルを画面内へ引き寄せて何の帯かを見せる。
                labelShift: stickyLabelShift(for: placed),
                // 実タップはキャンバス側のヒットテストで拾う。ここは VoiceOver 用。
                accessibilityAction: { open(placed.bar) }
            )
            .offset(x: placed.x, y: placed.y)
        }
    }

    /// 帯の左端が画面外に出ているとき、ラベルを画面左へ貼り付けるためのずらし量。
    /// 次のラベルと自分の帯の右端を越えない範囲に収める (`labelLimitX`)。
    private func stickyLabelShift(for placed: PlacedBar) -> Double {
        guard placed.showsLabel else { return 0 }
        let wanted = pan.x + 4 - placed.x
        return max(0, min(wanted, placed.labelLimitX - placed.x))
    }

    // MARK: 貼り付くヘッダー

    private func ruler(plan: TimelinePlan) -> some View {
        // 年の幅が狭いと "2004" が "20…" に潰れて読めなくなる。潰す代わりに間引く
        // (5 年ごと → 10 年ごと)。罫線は毎年引いたままなので密度感は失わない。
        let stride = plan.yearLabelStride
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: plan.canvasWidth, height: Metrics.rulerHeight)
            ForEach(plan.years, id: \.year) { tick in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.sep).frame(width: 1)
                    if tick.year.isMultiple(of: stride) {
                        Text(String(tick.year))
                            .font(.imasDisplay(11, weight: .semibold))
                            .foregroundStyle(DS.ink2)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.leading, 4)
                    }
                }
                .frame(width: max(tick.width, 1), height: Metrics.rulerHeight, alignment: .leading)
                .offset(x: tick.x)
            }
        }
    }

    private func rail(plan: TimelinePlan) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Metrics.railWidth, height: max(plan.canvasHeight, 1))
            ForEach(plan.lanes, id: \.lane) { lane in
                VStack(spacing: 3) {
                    Image(systemName: lane.lane.systemImage)
                        .font(.imasScaled(12, weight: .semibold))
                    Text(lane.lane.title)
                        .font(.imasCaption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(DS.ink2)
                .frame(width: Metrics.railWidth, height: min(lane.height, 56), alignment: .top)
                .offset(y: lane.y + Metrics.lanePadding)
            }
        }
    }

    // MARK: - 遷移

    private func open(_ bar: TimelineBar) {
        switch bar.target {
        case let .event(id):
            Task {
                if let event = try? await AppContainer.shared.eventReading.event(id: id) {
                    sheetDestination = .event(event)
                }
            }
        case let .seriesGroup(name):
            sheetDestination = .filteredSongs(.seriesGroup(name))
        case let .cdSeries(name):
            sheetDestination = .filteredSongs(.cdSeries(name))
        case let .releaseYear(year):
            sheetDestination = .filteredSongs(.releaseYear(year))
        case .none:
            break
        }
    }

    // MARK: - レイアウト計算

    /// 帯 → 配置済みキャンバスへの変換。倍率が変わるたびに作り直す。
    private func layout(pointsPerDay: Double) -> TimelinePlan? {
        guard let range = TimelineLayout.yearRange(of: viewModel.bars) else { return nil }
        let boundaries = TimelineLayout.yearBoundaries(range)
        guard let origin = boundaries.first?.date, let last = boundaries.last?.date else { return nil }

        let totalDays = last.timeIntervalSince(origin) / 86_400
        let canvasWidth = totalDays * pointsPerDay

        // 年カラムの位置と幅は「実日数 × 倍率」。うるう年でずれない。
        // 境界の x は一括変換で 1 回の FFI 呼び出しにまとめる (要素ごとに呼ばない)。
        let boundaryXs = TimelineLayout.xs(for: boundaries.map(\.date), origin: origin, pointsPerDay: pointsPerDay)
        var years: [TimelinePlan.YearTick] = []
        for index in 0..<(boundaries.count - 1) {
            years.append(.init(
                year: boundaries[index].year,
                x: boundaryXs[index],
                width: boundaryXs[index + 1] - boundaryXs[index]
            ))
        }

        let showsLabels = pointsPerDay * 365.25 >= Metrics.labelVisiblePointsPerYear
        let rowHeight = showsLabels ? Metrics.rowHeight : Metrics.compactRowHeight
        let minBarWidth = showsLabels ? Metrics.minBarWidth : Metrics.compactMinBarWidth

        var lanes: [TimelinePlan.LaneBlock] = []
        var placed: [PlacedBar] = []
        var y: Double = 0

        for lane in TimelineLane.allCases {
            let laneBars = viewModel.bars.filter { $0.lane == lane }
            guard !laneBars.isEmpty else { continue }

            // 帯の始点/終点の x も一括変換。ラベル幅の見積もりだけが UI 側の仕事。
            let startXs = TimelineLayout.xs(for: laneBars.map(\.start), origin: origin, pointsPerDay: pointsPerDay)
            let endXs = TimelineLayout.xs(for: laneBars.map(\.end), origin: origin, pointsPerDay: pointsPerDay)
            let geometry = laneBars.indices.map { index -> (x: Double, barWidth: Double, labelWidth: Double) in
                let raw = endXs[index] - startXs[index]
                let labelWidth = showsLabels
                    ? min(Self.estimatedWidth(of: Self.label(for: laneBars[index]), fontSize: Metrics.labelFontSize),
                          Metrics.maxLabelWidth)
                    : 0
                return (startXs[index], max(raw, minBarWidth), labelWidth)
            }

            // 行詰めは **帯の幅だけ** で行う。ラベル幅まで占有させると、密な年 (765AS の
            // 2011 年は 28 公演) で段数が実態の何倍にも膨らみ、レーンが縦に伸びて
            // 「1 枚で俯瞰する」という目的が壊れる。
            let spans = geometry.map { TimelineLayout.Span(start: $0.x, end: $0.x + $0.barWidth) }
            let rows = TimelineLayout.packRows(
                spans,
                gap: showsLabels ? Metrics.packGap : Metrics.compactPackGap
            )
            let rowCount = (rows.max() ?? 0) + 1

            // ラベルは「同じ段で直前のラベルと重ならないもの」にだけ出す。
            // 帯そのものは全部描くので、密度は失われずラベルだけが間引かれる。
            var labelVisible = [Bool](repeating: false, count: laneBars.count)
            // ラベルを右へずらせる上限 (画面左で切れた帯のラベルを画面内に貼り付けるため)。
            // 「次のラベルにぶつからない」かつ「自分の帯からはみ出さない」範囲まで。
            var labelLimit = [Double](repeating: 0, count: laneBars.count)
            let byX = laneBars.indices.sorted { geometry[$0].x < geometry[$1].x }
            if showsLabels {
                var lastLabelEnd: [Int: Double] = [:]
                var previousLabeled: [Int: Int] = [:]
                for index in byX {
                    let row = rows[index]
                    guard geometry[index].x >= lastLabelEnd[row] ?? -.greatestFiniteMagnitude else { continue }
                    labelVisible[index] = true
                    // 直前にラベルを出した帯は、この帯の手前までしかずらせない。
                    if let previous = previousLabeled[row] {
                        labelLimit[previous] = min(
                            labelLimit[previous],
                            geometry[index].x - geometry[previous].labelWidth - Metrics.packGap
                        )
                    }
                    // 自分の帯の右端は越えない (越えると帯と切り離されて浮いて見える)。
                    labelLimit[index] = geometry[index].x + geometry[index].barWidth - 8
                    lastLabelEnd[row] = geometry[index].x + geometry[index].labelWidth + Metrics.packGap
                    previousLabeled[row] = index
                }
            }

            for (index, bar) in laneBars.enumerated() {
                placed.append(
                    PlacedBar(
                        bar: bar,
                        x: geometry[index].x,
                        barWidth: geometry[index].barWidth,
                        labelWidth: geometry[index].labelWidth,
                        showsLabel: labelVisible[index],
                        labelLimitX: max(labelLimit[index], geometry[index].x),
                        y: y + Metrics.lanePadding + Double(rows[index]) * rowHeight
                    )
                )
            }

            let height = Double(rowCount) * rowHeight + Metrics.lanePadding * 2
            lanes.append(.init(lane: lane, y: y, height: height))
            y += height
        }

        let todayX: Double? = {
            let now = Date()
            guard now >= origin, now <= last else { return nil }
            return TimelineLayout.x(for: now, origin: origin, pointsPerDay: pointsPerDay)
        }()

        return TimelinePlan(
            origin: origin,
            pointsPerDay: pointsPerDay,
            totalDays: totalDays,
            canvasWidth: canvasWidth,
            canvasHeight: max(y, 1),
            rowHeight: rowHeight,
            showsLabels: showsLabels,
            years: years,
            lanes: lanes,
            placed: placed,
            todayX: todayX
        )
    }

    /// 帯に出す文字列 (タイトル + バッジ)。
    fileprivate static func label(for bar: TimelineBar) -> String {
        guard let badge = bar.badge else { return bar.title }
        return "\(bar.title)  \(badge)"
    }

    /// 文字列の描画幅の近似。全角は 1em、半角は約 0.55em として数える。
    /// 正確な計測 (TextKit) は帯 1,000 本ぶん走らせると重いので、行詰めにはこの近似で足りる。
    fileprivate static func estimatedWidth(of text: String, fontSize: Double) -> Double {
        var units = 0.0
        for scalar in text.unicodeScalars {
            units += scalar.value > 0x2E7F ? 1.0 : 0.55
        }
        return units * fontSize
    }
}

// MARK: - 配置結果

/// キャンバス上に配置が確定した 1 本の帯。
struct PlacedBar: Identifiable {
    let bar: TimelineBar
    /// 帯の左端 (pt)。
    let x: Double
    /// 帯そのものの幅 (pt)。タップ領域でもある。
    let barWidth: Double
    /// ラベルの想定幅 (pt)。ラベルは帯からはみ出して右に伸びる。
    let labelWidth: Double
    /// この帯にラベルを出すか (同じ段で重なるものは間引かれる)。
    let showsLabel: Bool
    /// ラベルの左端をここまで右へずらしてよい、という上限 (キャンバス座標)。
    /// 画面左で切れた帯のラベルを画面内へ貼り付けるときの止め位置。
    let labelLimitX: Double
    /// キャンバス上の絶対 y (pt)。
    let y: Double

    var id: String { bar.id }
}

/// 1 回のレイアウト計算の結果一式。
struct TimelinePlan {
    struct YearTick { let year: Int; let x: Double; let width: Double }
    struct LaneBlock { let lane: TimelineLane; let y: Double; let height: Double }

    let origin: Date
    let pointsPerDay: Double
    let totalDays: Double
    let canvasWidth: Double
    let canvasHeight: Double
    /// 現在のズームでの 1 段の高さ。
    let rowHeight: Double
    /// ラベルを描くズームか。
    let showsLabels: Bool
    let years: [YearTick]
    let lanes: [LaneBlock]
    let placed: [PlacedBar]
    let todayX: Double?

    /// 年ラベルを何年おきに出すか。1 年ぶんの幅に "2004" が入らないズームでは間引く。
    var yearLabelStride: Int {
        let width = years.first?.width ?? 0
        if width >= 36 { return 1 }
        if width >= 16 { return 5 }
        return 10
    }
}

// MARK: - 帯 1 本の描画

/// 年表の帯 1 本。ラベル (上) + バーと点 (下)。
///
/// **タップは受け取らない** (`allowsHitTesting(false)`)。実タップは親キャンバスの
/// ヒットテストが一括で処理する。帯を Button にするとタッチダウンで反応してしまい、
/// 少し滑らせただけの操作でも指を離した瞬間に開いてしまうため。
/// VoiceOver からの操作だけは `accessibilityAction` で受ける。
private struct TimelineBarView: View {
    let placed: PlacedBar
    let pointsPerDay: Double
    let rowHeight: Double
    /// 点を描くか。ズームアウト時は点が団子になるだけなので省いて描画コストを下げる。
    let showsMarks: Bool
    let barThickness: Double
    let labelFontSize: Double
    /// ラベルを右へずらす量 (画面左で切れた帯を画面内に見せるため)。
    let labelShift: Double
    /// VoiceOver の「アクティベート」で呼ばれる遷移。
    let accessibilityAction: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Self.theme(for: placed.bar, scheme: scheme)

        ZStack(alignment: .bottomLeading) {
            Color.clear
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.accent.opacity(0.3))
                    .frame(width: placed.barWidth, height: barThickness)
                if showsMarks {
                    ForEach(Array(placed.bar.marks.enumerated()), id: \.offset) { _, mark in
                        Circle()
                            .fill(theme.accent)
                            .frame(width: barThickness - 1, height: barThickness - 1)
                            .offset(x: markX(mark))
                    }
                }
            }
            .frame(height: barThickness)
        }
        .frame(width: placed.barWidth, height: rowHeight - 3, alignment: .bottomLeading)
        .overlay(alignment: .topLeading) {
            if placed.showsLabel {
                Text(BrandTimelineView.label(for: placed.bar))
                    .font(.imasScaled(labelFontSize, weight: .semibold))
                    .foregroundStyle(theme.chipText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: placed.labelWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: labelShift)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(placed.bar.target == .none ? [] : .isButton)
        .accessibilityAction { accessibilityAction() }
    }

    /// 帯の色。**必ずブランドカラーが起点**で、楽曲レーンだけそこから振ったバリエーションを使う。
    ///
    /// 以前は楽曲シリーズをシリーズ名の安定ハッシュから塗っていたため、全ブランド表示で
    /// 「どれがどのブランドか」が色から読めなかった。ブランド色を基準にすれば、
    /// 全ブランドではブランドごとにまとまり、1 ブランドでもシリーズが見分けられる。
    static func theme(for bar: TimelineBar, scheme: ColorScheme) -> ImasTheme {
        guard let seed = bar.seedHex else {
            // ブランド未設定 (稀) のときだけ分類キー由来の色にフォールバックする。
            return ImasTheme.derive(categoryKey: bar.categoryKey, scheme: scheme)
        }
        guard bar.lane == .music else {
            return ImasTheme.derive(seed: seed, scheme: scheme)
        }
        return ImasTheme.derive(
            hex: ColorMath.variantHex(of: seed, key: bar.categoryKey),
            dark: scheme == .dark
        )
    }

    /// 帯の左端を 0 とした点の x。
    private func markX(_ mark: Date) -> Double {
        let offset = mark.timeIntervalSince(placed.bar.start) / 86_400 * pointsPerDay
        return min(max(offset, 0), max(placed.barWidth - (barThickness - 1), 0))
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = TimelineDateParser.calendar
        formatter.timeZone = TimelineDateParser.calendar.timeZone
        formatter.dateFormat = "yyyy年M月"
        let from = formatter.string(from: placed.bar.start)
        let to = formatter.string(from: placed.bar.end)
        let period = from == to ? from : "\(from)〜\(to)"
        return "\(placed.bar.title) \(period)\(placed.bar.badge.map { " \($0)" } ?? "")"
    }
}
