import SwiftUI

/// 習熟度ダッシュボード。**どの群を見るかを選ぶ面**。
///
/// 3,000 曲ぶんを一度に出しても中身が読めないので、ここは「絞る → 群を選ぶ」まで。
/// 曲名が要る操作は `MasteryGroupDetailView` に渡す。
/// 群化・並び・絞り込みの規則は core (`domain/mastery.rs`)。
///
/// 体裁は**回収率ダッシュボード (`StatsView`) に倣う**。同じ「全体の進捗 + 群別の進捗 +
/// 対象の一覧」という形なので、そこだけ別の組み方にすると同じアプリで進捗の見せ方が
/// 2 通りになる。ScrollView + `VStack(spacing: DS.sp7)` に
/// `ImasSectionHeader(tight:) + ImasListContainer / ImasStatBar` を積む。
struct MasteryView: View {
    @Environment(AppDatabase.self) private var database
    private var marks: UserMarkService { UserMarkService.shared }

    @State private var axisIndex: Int = 0
    @State private var songs: [Song] = []
    @State private var brands: [Brand] = []
    @State private var loaded = false

    // 集計の結果は **State に持つ**。body の中で 2,000 曲を射影して FFI に渡すと、
    // 無関係な再描画や 1 打鍵ごとに全部やり直しになって目に見えて重い。
    // `.task(id:)` で「本当に変わったとき」だけ組み直す。
    @State private var groups: [MasteryGroup] = []
    @State private var summary = MasterySummary(percent: 0, doneCount: 0, setCount: 0, total: 0)
    @State private var stageCounts: [Int] = []
    @State private var songsById: [String: Song] = [:]
    @State private var scopedCount = 0

    /// 適用済みの条件。シートは下書きを持ち、「適用」で移す。
    @State private var filter = MasteryFilter()
    @State private var showFilter = false
    /// 名前絞り込みは即時 (シートを開かずに効かせる)。
    @State private var nameFilter = ""

    private static let axisLabels = ["CDシリーズ", "ユニット", "年代"]
    private var axis: MasteryAxis {
        switch axisIndex {
        case 1: return .unit
        case 2: return .year
        default: return .series
        }
    }

    var body: some View {
        // ⚠️ **List でなければならない**。群の行のスワイプ (`swipeActions`) は
        // List の行にしか効かず、ScrollView + LazyVStack だと無言で消える。
        List {
            summarySection.plainRow(background: DS.bg)
            groupHeader.plainRow(background: DS.bg)
            groupRows
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("習熟度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    AppAnalytics.tap("mastery.filter")
                    showFilter = true
                } label: {
                    Image(systemName: filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("フィルタ")
            }
        }
        .sheet(isPresented: $showFilter) {
            MasteryFilterSheet(brands: brands, filter: $filter)
        }
        .task { if !loaded { await load() } }
        .task(id: recomputeKey) { await recompute() }
        .trackScreen("mastery")
    }

    /// 組み直しが要る条件。ここに出てこない変化では再集計しない。
    private struct RecomputeKey: Equatable {
        var loaded: Bool
        var axisIndex: Int
        var brandIds: Set<String>
        var progress: MasteryProgressFilter
        var sort: MasteryGroupSort
        var name: String
        /// マークの変更番号。段階を付け替えたときだけ動く。
        var token: Int
    }

    private var recomputeKey: RecomputeKey {
        RecomputeKey(loaded: loaded, axisIndex: axisIndex, brandIds: filter.brandIds,
                     progress: filter.progress, sort: filter.sort, name: nameFilter,
                     token: marks.changeToken)
    }

    private func recompute() async {
        guard loaded else { return }
        // 打鍵ごとに 2,000 件を FFI へ渡さないよう、少しだけ待つ
        // (`.task(id:)` は鍵が変わると前のタスクを畳むので、これがデバウンスになる)。
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        let scoped = filter.brandIds.isEmpty
            ? songs
            : songs.filter { filter.brandIds.contains($0.brandId ?? "") }
        let collected = marks.autoCollectedSongIds()
        let entries = scoped.map { s in
            MasterySong(songId: s.id, title: s.title,
                        seriesGroup: s.seriesGroup, cdSeries: s.cdSeries,
                        unitName: s.unitName, singerLabel: s.singerLabel,
                        releaseDate: s.releaseDate, level: marks.mastery(songId: s.id),
                        collected: collected.contains(s.id))
        }
        let steps = marks.scale.steps

        // 段ごとの本数は**絞り込んだ範囲で**数える。サービスの全体集計を使うと、
        // ブランドで絞っているのに帯だけ全曲のままになって数字が合わない。
        var counts = [Int](repeating: 0, count: Int(steps))
        for e in entries where e.level > 0 {
            let i = Int(min(e.level, steps)) - 1
            if i < counts.count { counts[i] += 1 }
        }

        summary = masterySummary(songs: entries, steps: steps)
        groups = buildMasteryGroups(songs: entries, axis: axis, steps: steps,
                                    sort: filter.sort, progress: filter.progress,
                                    nameFilter: nameFilter)
        stageCounts = counts
        songsById = Dictionary(scoped.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        scopedCount = scoped.count
    }

    // MARK: - 集計

    private var scopedSongs: [Song] {
        guard !filter.brandIds.isEmpty else { return songs }
        return songs.filter { filter.brandIds.contains($0.brandId ?? "") }
    }

    // MARK: - 全体の進捗 (回収率サマリーと同じ組み方)

    private var summarySection: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: DS.sp4) {
            ImasSectionHeader(title: "あなたの習熟度", tight: true)
            HStack(spacing: DS.sp5) {
                MasteryRing(fraction: Double(s.percent) / 100)
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: DS.sp3) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
                        Text("\(s.setCount)")
                            .font(.imasDisplay(30, weight: .bold))
                            .foregroundStyle(DS.ink)
                        Text("/ \(s.total)曲")
                            .font(.imasDisplay(15))
                            .foregroundStyle(DS.ink2)
                    }
                    Text("段階を付けた曲")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                    Text("\(marks.scale.label(marks.scale.steps)) \(s.doneCount) 曲")
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.sp5)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))

            stageBars
        }
    }

    /// 段ごとの本数。ブランド別回収率と同じ `ImasStatBar` の積み方。
    private var stageBars: some View {
        let total = max(scopedCount, 1)
        return VStack(spacing: 0) {
            ForEach(Array((1...Int(marks.scale.steps)).reversed()), id: \.self) { level in
                let c = level - 1 < stageCounts.count ? stageCounts[level - 1] : 0
                ImasStatBar(label: marks.scale.label(UInt8(level)),
                            value: "\(c)",
                            percent: Double(c) / Double(total) * 100)
            }
        }
        .padding(.horizontal, DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - 群の一覧

    /// 一覧の見出しと絞り込み。List の 1 行として差す。
    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            HStack(alignment: .firstTextBaseline) {
                ImasSectionHeader(title: "グループ別", tight: true)
                Spacer(minLength: 12)
                Text("\(groups.count) 件")
                    .font(.imasCaption.weight(.semibold))
                    .foregroundStyle(DS.ink3)
            }

            // ブランドは**常に見える位置**に置く。この一覧はブランドで絞らないと
            // 群が数百件並んで用を成さないので、シートの中に畳んではいけない。
            brandChips

            ImasSegmented(labels: Self.axisLabels, selection: $axisIndex)

            NameFilterField(prompt: "\(Self.axisLabels[axisIndex])名で絞り込み", text: $nameFilter)

            if filter.progress != .all || filter.sort != .songCount {
                activeFilterChips
            }
        }
    }

    /// 群の行。List の行なので、ユニット軸の 1,047 群でも必要なぶんしか組まれない。
    @ViewBuilder
    private var groupRows: some View {
        if !loaded {
            ImasInlineLoading().padding(.vertical, DS.sp6).plainRow(background: DS.bg)
        } else if groups.isEmpty {
            ImasEmptyState(
                systemImage: "line.3.horizontal.decrease",
                title: "該当するグループがありません",
                message: "絞り込みを緩めてください。"
            )
            .plainRow(background: DS.bg)
        } else {
            ForEach(groups, id: \.key) { group in
                NavigationLink {
                    // destination は**押されたときに**組む。ここで
                    // `songIds.compactMap` すると行ごとに群の曲数ぶん走る。
                    MasteryGroupDetailView(title: group.label, songIds: group.songIds,
                                           axis: axis, groupKey: group.key)
                        .environment(database)
                } label: {
                    groupRow(group)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    unsetBulkButtons(group)
                }
            }
        }
    }

    /// 群の行を**右スワイプ**したときに出る一括更新。その群の
    /// **まだ付けていない曲だけ**をまとめて付ける。
    ///
    /// 「このシリーズは一通り聞いた」を一覧から 2 手で終わらせるための口。
    /// 既に付いている記録に触らない操作だけなので、誤って押しても失うものがない
    /// (段の塗り替え・未設定に戻すは、直前の 1 回を戻せる詳細画面に残す)。
    @ViewBuilder
    private func unsetBulkButtons(_ g: MasteryGroup) -> some View {
        let unset = g.levels.filter { $0 == 0 }.count
        if unset > 0 {
            // スワイプで出るボタンは左から並ぶので、押しやすい手前に低い段を置く
            // (「聞いた」を付ける回数が一番多い)。
            ForEach(1...Int(marks.scale.steps), id: \.self) { level in
                Button {
                    applyToUnset(g, level: UInt8(level))
                } label: {
                    Text(marks.scale.swipeLabel(UInt8(level)))
                }
                .tint(MasteryPalette.fill(level: UInt8(level), steps: marks.scale.steps))
            }
        }
    }

    /// 未設定の曲だけに段階を付ける。対象の選び方は core の `masteryBulkTargets` 一本。
    private func applyToUnset(_ g: MasteryGroup, level: UInt8) {
        let targets = masteryBulkTargets(songIds: g.songIds, levels: g.levels, scope: .unsetOnly)
        guard !targets.isEmpty else { return }
        // 失敗しても一覧は前の値のまま。書けなかったことは知らせる。
        do { try marks.setMastery(songIds: targets, level: level) }
        catch { LocalWriteFailure.report(error, action: "習熟度のまとめての記録") }
    }

    /// ブランド絞り込み。複数選択は OR、空集合は全ブランド (既存の絞り込みと同じ意味)。
    private var brandChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.sp3) {
                ImasFilterChip(text: "全て", isSelected: filter.brandIds.isEmpty) {
                    filter.brandIds = []
                }
                ForEach(brands) { brand in
                    ImasFilterChip(text: brand.shortName,
                                   isSelected: filter.brandIds.contains(brand.id),
                                   brand: brand.id) {
                        if filter.brandIds.contains(brand.id) {
                            filter.brandIds.remove(brand.id)
                        } else {
                            filter.brandIds.insert(brand.id)
                        }
                    }
                }
            }
            .padding(.vertical, DS.sp1)
        }
    }

    /// 適用中の条件。解除はチップからもできる (リセットはシートのツールバー)。
    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.sp3) {
                if filter.progress != .all {
                    ImasRemovableChip(text: MasteryFilter.progressLabel(filter.progress)) {
                        filter.progress = .all
                    }
                }
                if filter.sort != .songCount {
                    ImasRemovableChip(text: MasteryFilter.sortLabel(filter.sort)) {
                        filter.sort = .songCount
                    }
                }
            }
            .padding(.vertical, DS.sp1)
        }
    }

    /// 群 1 行。既存の一覧行と同じ `ImasLeadRow` + 末尾に進捗。
    ///
    /// ブランド色は**先頭 1 曲だけ**引く。`compactMap` で群の全曲を舐めると、
    /// 行の数だけ全曲走査が走る (一覧全体で O(曲数×群数) になっていた)。
    private func groupRow(_ g: MasteryGroup) -> some View {
        let brandId = g.songIds.first.flatMap { songsById[$0]?.brandId }
        // 矢印は List の NavigationLink が出すので、行の側では描かない (二重になる)。
        return ImasLeadRow(title: g.label, subtitle: subtitle(g), brand: BrandColors.hex(for: brandId), titleLineLimit: 2) {
            ImasMetricBadge(value: "\(g.percent)", unit: "%",
                            emphasized: g.percent > 0, seed: nil)
        }
    }

    private func subtitle(_ g: MasteryGroup) -> String {
        var parts: [String] = []
        if g.discCount > 1 { parts.append("\(g.discCount)枚") }
        parts.append("\(g.total)曲")
        // 「聴いたのにまだ未設定」は覚える優先度が高いので、そこだけ名指しで出す。
        if g.heardButUnsetCount > 0 {
            parts.append("聴いたのに未設定 \(g.heardButUnsetCount)")
        } else if g.collectedCount > 0 {
            parts.append("聴いた \(g.collectedCount)")
        }
        if g.doneCount > 0 { parts.append("\(marks.scale.label(marks.scale.steps)) \(g.doneCount)") }
        return parts.joined(separator: " ・ ")
    }

    // MARK: - 読み込み

    private func load() async {
        // 分母にする曲の選び方はコア (Q-08b: リミックス・別バージョン・other・ライブ履歴だけの曲を数えない)。
        let container = AppContainer.shared
        songs = (try? await container.songReading.masterySongs()) ?? []
        brands = (try? await container.brandReading.brands()) ?? []
        loaded = true
    }
}

// MARK: - 適用中の条件

/// 習熟度一覧の絞り込み条件。判定自体は core が持ち、ここは**選んだ値の入れ物**。
struct MasteryFilter: Equatable {
    var brandIds: Set<String> = []
    var progress: MasteryProgressFilter = .all
    var sort: MasteryGroupSort = .songCount

    var isActive: Bool { !brandIds.isEmpty || progress != .all || sort != .songCount }

    static func progressLabel(_ v: MasteryProgressFilter) -> String {
        switch v {
        case .all:       return "すべて"
        case .hasUnset:  return "未設定あり"
        case .untouched: return "手つかず"
        case .complete:  return "完了"
        case .heardButUnset: return "聴いたのに未設定"
        }
    }

    static func sortLabel(_ v: MasteryGroupSort) -> String {
        switch v {
        case .songCount:    return "曲数順"
        case .progressAsc:  return "進み具合が低い順"
        case .progressDesc: return "進み具合が高い順"
        case .name:         return "名前順"
        }
    }
}

/// フィルタシート。体裁は `imasFilterSheetChrome()` + `filterSheetToolbar()` に揃える
/// (リセットはツールバー 1 箇所だけ、という確定 IA)。
struct MasteryFilterSheet: View {
    let brands: [Brand]
    @Binding var filter: MasteryFilter
    @Environment(\.dismiss) private var dismiss

    @State private var draft = MasteryFilter()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                BrandFilterSection(brands: brands, selectedBrandIds: $draft.brandIds)

                Section("進み具合") {
                    ForEach([MasteryProgressFilter.all, .heardButUnset, .hasUnset,
                             .untouched, .complete], id: \.self) { value in
                        Button {
                            draft.progress = value
                        } label: {
                            HStack {
                                Text(MasteryFilter.progressLabel(value))
                                    .foregroundStyle(DS.ink)
                                Spacer()
                                ImasSelectionMark(isSelected: draft.progress == value)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("並び") {
                    ForEach([MasteryGroupSort.songCount, .progressAsc, .progressDesc, .name],
                            id: \.self) { value in
                        Button {
                            draft.sort = value
                        } label: {
                            HStack {
                                Text(MasteryFilter.sortLabel(value))
                                    .foregroundStyle(DS.ink)
                                Spacer()
                                ImasSelectionMark(isSelected: draft.sort == value)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .imasFilterSheetChrome()
            .toolbar {
                filterSheetToolbar(
                    analyticsPrefix: "mastery.filter",
                    canReset: draft.isActive,
                    onReset: { draft = MasteryFilter() },
                    onApply: { filter = draft; dismiss() }
                )
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = filter
            loaded = true
        }
    }
}

// MARK: - 共有パーツ

/// 全体の進み具合のリング。回収率の `CollectionRing` と同じ寸法・同じ描き方。
struct MasteryRing: View {
    /// 0.0–1.0。
    let fraction: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: nil, scheme: scheme)
        let clamped = min(1, max(0, fraction))
        ZStack {
            Circle().stroke(DS.fill, lineWidth: 10)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(t.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.imasDisplay(18, weight: .bold))
                .foregroundStyle(DS.ink)
        }
    }
}

/// マス 1 つ。未設定は面を持たず点線の枠だけ。
struct MasteryCell: View {
    let level: UInt8
    let scale: MasteryScale
    var size: CGFloat = 14

    var body: some View {
        let radius: CGFloat = size > 10 ? 3 : 2
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(level == 0 ? Color.clear : MasteryPalette.fill(level: level, steps: scale.steps))
            .overlay {
                if level == 0 {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(DS.ink3, lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
    }
}
