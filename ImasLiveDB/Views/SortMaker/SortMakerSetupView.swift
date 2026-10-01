import SwiftUI

/// 何を作るか。対象の選び方はソートとティアー表で共通。
enum SortMakerPurpose {
    case sort
    case tier
}

/// ソートメーカー / ティアー表の設定画面。対象 (ブランド・曲の種類・歌唱アイドル) と
/// 決め方 (ベスト10 / 全順位) を選んで始める。途中のものがあれば「つづきから」を先頭に出す。
struct SortMakerSetupView: View {
    let subject: SortMakerSubject
    var purpose: SortMakerPurpose = .sort

    @State private var store = SortMakerStore.shared
    @State private var brands: [Brand] = []
    @State private var scope = SortMakerScope()
    @State private var depth: SortMakerDepth = .top10
    @State private var candidates: [SortMakerItem] = []
    @State private var isLoading = true
    @State private var pickedIdols: [Idol] = []
    /// 遷移先のセッション (始める / つづきから / 結果を見る)。
    @State private var playing: SortMakerSession?
    @State private var confirmRestart = false
    @State private var tierStore = TierListStore.shared
    @State private var openBoard: TierListBoard?
    @State private var deletingBoard: TierListBoard?

    /// 前回の設定。カンマ区切り (曲とアイドルで別キー)。
    @AppStorage private var brandIdsRaw: String
    @AppStorage private var depthRaw: Int

    init(subject: SortMakerSubject, purpose: SortMakerPurpose = .sort) {
        self.subject = subject
        self.purpose = purpose
        _brandIdsRaw = AppStorage(wrappedValue: "", "sortMaker.\(subject.rawValue).brandIds")
        _depthRaw = AppStorage(wrappedValue: SortMakerDepth.top10.rawValue, "sortMaker.\(subject.rawValue).depth")
    }

    private var estimate: Int {
        Int(sortMakerEstimateTotal(itemCount: UInt32(candidates.count), topK: UInt32(depth.rawValue)))
    }

    var body: some View {
        ImasPage {
            header
            if purpose == .sort, let s = store.session(subject) {
                savedCard(s)
            }
            if purpose == .tier, !tierStore.boards(for: subject).isEmpty {
                savedBoardsSection
            }
            brandSection
            if subject == .song {
                songSection
            }
            if purpose == .sort {
                depthSection
            }
            summary
        }
        .safeAreaInset(edge: .bottom) { startBar }
        .navigationTitle(purpose == .sort ? subject.title : subject.tierTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $playing) { session in
            SortMakerPlayView(session: session)
        }
        .navigationDestination(item: $openBoard) { TierListView(board: $0) }
        .confirmationDialog("「\(deletingBoard?.displayTitle ?? "")」を削除しますか？",
                            isPresented: Binding(get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let b = deletingBoard { tierStore.delete(b.id) }
                deletingBoard = nil
            }
        }
        .confirmationDialog(store.session(subject)?.isFinished == true ? "前回の結果を消して新しく始めますか？" : "前回の続きを消して最初から始めますか？",
                            isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("最初から始める", role: .destructive) { start() }
        }
        .task {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            scope.brandIds = Set(quizBrandIdsDecode(raw: brandIdsRaw))
            depth = SortMakerDepth(rawValue: depthRaw) ?? .top10
            await reload()
        }
        .onChange(of: scope) { old, new in
            if old.brandIds != new.brandIds { brandIdsRaw = quizBrandIdsEncode(brandIds: Array(new.brandIds)) }
            Task { await reload() }
        }
        .onChange(of: depth) { _, new in depthRaw = new.rawValue }
        .trackScreen(purpose == .sort ? "sort_maker_setup" : "tier_list_setup")
    }

    private func reload() async {
        isLoading = true
        let requested = scope
        let loaded = await SortMakerCandidates.load(subject, scope: requested)
        // 読んでいる間に条件が変わっていたら捨てる (古い件数で上書きしない)。
        guard requested == scope else { return }
        candidates = loaded
        isLoading = false
    }

    // MARK: - ヘッダ

    private var header: some View {
        ImasSetupHeader(
            systemImage: purpose == .sort ? "arrow.left.arrow.right" : "square.stack.3d.up",
            title: purpose == .sort ? "2つから好きな方を選ぶだけ" : "段に振り分けて1枚の画像に",
            message: purpose == .sort
                ? "対戦を重ねると、あなたの\(subject == .song ? "好きな曲" : "好きなアイドル")ランキングができあがります。途中でやめても続きから遊べます。"
                : "選んだ対象がぜんぶ未分類に並びます。段の数・名前・色は自由に変えられ、何枚でも端末に保存できます。")
    }

    // MARK: - つづきから / 前回の結果

    private func savedCard(_ s: SortMakerSession) -> some View {
        let state = s.replay()
        return ImasCard {
            HStack(spacing: DS.sp3) {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(s.isFinished ? "前回の結果" : "つづきから").imasText(.meta)
                    if s.isFinished {
                        Text(s.topNames.first.map { "1位 \($0)" } ?? s.scopeLabel).imasText(.rowTitle)
                    } else {
                        Text("\(state.progressPercent)% · \(state.answered)戦 済み").imasText(.rowTitle).monospacedDigit()
                    }
                    Text(s.scopeLabel).imasText(.meta)
                    if !s.isFinished {
                        ImasProgressBar(fraction: Double(state.progressPercent) / 100)
                            .padding(.top, DS.Space.gapTight)
                    }
                }
                Spacer(minLength: DS.sp2)
                ImasButton(title: s.isFinished ? "見る" : "再開", role: .primary, size: .medium) {
                    AppAnalytics.tap(s.isFinished ? "sort_maker.open_result" : "sort_maker.resume")
                    playing = s
                }
            }
        }
    }

    /// 端末に保存してあるティアー表 (新しく触ったものから)。長押しで削除。
    private var savedBoardsSection: some View {
        let boards = tierStore.boards(for: subject)
        return VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                Text("保存したティアー表").imasText(.value)
                Text("\(boards.count)").imasText(.meta).monospacedDigit()
            }
            ImasCardList {
                ForEach(Array(boards.enumerated()), id: \.element.id) { i, b in
                    if i > 0 { ImasRowDivider(inset: DS.sp4) }
                    Button {
                        AppAnalytics.tap("tier_list.open")
                        openBoard = b
                    } label: {
                        ImasRow(
                            title: b.displayTitle,
                            subtitle: "\(b.placedCount) / \(b.itemIds.count) 振り分け済み · \(b.savedAt.formatted(date: .abbreviated, time: .shortened))",
                            trailing: .chevron
                        )
                    }
                    .buttonStyle(.imasRow)
                    .contextMenu {
                        Button("削除", systemImage: "trash", role: .destructive) { deletingBoard = b }
                    }
                }
            }
            ImasNote("長押しで削除できます。")
        }
    }

    // MARK: - ブランド

    private var brandSection: some View {
        section(title: "ブランド", note: "複数選択可 · 空=全ブランド") {
            ImasBrandPicker(brands: brands, selection: $scope.brandIds)
        }
    }

    // MARK: - 曲の絞り込み

    private var songSection: some View {
        section(title: "曲の種類", note: nil) {
            VStack(alignment: .leading, spacing: DS.sp4) {
                ImasSegmented(options: SortMakerSongType.allCases, selection: $scope.songType) { $0.label }

                NavigationLink {
                    IdolPickerView(title: "歌唱", mode: .multi, selected: scope.idolIds) { ids in
                        scope.idolIds = ids
                        Task {
                            pickedIdols = (try? await AppContainer.shared.idolReading.idols(ids: Array(ids))) ?? []
                        }
                    }
                } label: {
                    ImasRow(
                        title: "歌っているアイドルで絞る",
                        subtitle: scope.idolIds.isEmpty ? "指定なし" : pickedIdols.map(\.name).joined(separator: "、"),
                        trailing: .custom(AnyView(
                            HStack(spacing: DS.Space.gap) {
                                if !scope.idolIds.isEmpty {
                                    StackedAvatars(idols: pickedIdols, maxVisible: 4, size: 26)
                                }
                                ImasRowChevron()
                            }
                        ))
                    )
                }
                .buttonStyle(.imasRow)
                if !scope.idolIds.isEmpty {
                    ImasButton(title: "アイドルの指定を外す", role: .plain, size: .small) {
                        scope.idolIds = []; pickedIdols = []
                    }
                }

                ImasToggleRow(title: "リミックス・別バージョンも入れる", isOn: $scope.includeRemixes)
            }
        }
    }

    // MARK: - 決め方

    private var depthSection: some View {
        section(title: "決める順位", note: depth == .top10 ? "上位だけ決めるので対戦が少なく済みます" : "全部に順位をつけます") {
            ImasSegmented(options: SortMakerDepth.allCases, selection: $depth) { $0.label }
        }
    }

    // MARK: - 件数と見積り

    private var summary: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            counts
            if !isLoading, let hint {
                ImasNote(hint)
            }
        }
    }

    private var counts: some View {
        ImasStatGrid(columns: purpose == .sort ? 2 : 1) {
            ImasStatTile(value: isLoading ? "…" : "\(candidates.count)", unit: subject.counter, label: "対象")
            if purpose == .sort {
                ImasStatTile(value: isLoading ? "…" : "約\(estimate)", unit: "戦", label: "対戦の目安")
            }
        }
    }

    /// 対戦が長すぎる / 少なすぎるときのひとこと。
    private var hint: String? {
        if candidates.count < 2 { return "2\(subject.counter)以上になるように絞り込みをゆるめてください。" }
        if purpose == .tier {
            return candidates.count > 200 ? "未分類は名前で絞り込めるので、全\(subject.counter)からでも探して振り分けられます。" : nil
        }
        if estimate > 600 {
            return depth == .all
                ? "かなり長くなります。ブランドを絞るか「ベスト10」がおすすめです。途中保存されるので少しずつでも大丈夫です。"
                : "長めです。途中保存されるので、少しずつ進めても大丈夫です。"
        }
        return nil
    }

    // MARK: - 開始

    private var startBar: some View {
        ImasButton(title: purpose == .sort ? "はじめる" : "ティアー表をつくる", role: .primary, size: .large) {
            if purpose == .sort, let s = store.session(subject), s.isFinished || !s.answers.isEmpty {
                confirmRestart = true
            } else {
                start()
            }
        }
        .disabled(!canStart)
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp3)
        .background(.bar)
    }

    private var canStart: Bool { !isLoading && candidates.count >= 2 }

    private func start() {
        if purpose == .tier {
            AppAnalytics.tap("tier_list.start")
            let board = TierListBoard(subject: subject, itemIds: candidates.map(\.id), scopeLabel: scopeLabel)
            tierStore.save(board)
            openBoard = board
            return
        }
        AppAnalytics.tap("sort_maker.start")
        let session = SortMakerSession(
            subject: subject,
            itemIds: candidates.map(\.id),
            seed: UInt64.random(in: 0...UInt64.max),
            topK: depth.rawValue,
            scopeLabel: scopeLabel,
            answers: "",
            savedAt: Date()
        )
        store.save(session)
        playing = session
    }

    /// 結果と共有文に出す範囲の説明。「シャニマス・ソロ曲 28曲」
    private var scopeLabel: String {
        var parts: [String] = []
        let names = brands.filter { scope.brandIds.contains($0.id) }.map(\.shortName)
        parts.append(names.isEmpty ? "全ブランド" : names.joined(separator: "・"))
        if subject == .song {
            if scope.songType != .any { parts.append(scope.songType.label) }
            if !pickedIdols.isEmpty {
                parts.append(pickedIdols.count <= 2 ? pickedIdols.map(\.name).joined(separator: "・")
                                                   : "\(pickedIdols[0].name)ほか")
            }
        }
        let base = parts.joined(separator: "・") + " \(candidates.count)\(subject.counter)"
        guard purpose == .sort else { return base }
        return base + "から" + (depth == .top10 ? "ベスト10" : "全順位")
    }

    // MARK: - 部品

    private func section<Content: View>(title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        ImasCard {
            VStack(alignment: .leading, spacing: DS.sp3) {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(title).imasText(.value)
                    if let note { ImasNote(note) }
                }
                content()
            }
        }
    }
}
