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
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
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
            .padding(DS.sp5)
            .padding(.bottom, 96)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
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
        HStack(spacing: DS.sp4) {
            Image(systemName: purpose == .sort ? "arrow.left.arrow.right" : "square.stack.3d.up")
                .font(.imasScaled(24, weight: .semibold))
                .foregroundStyle(DS.onSys)
                .frame(width: 52, height: 52)
                .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(purpose == .sort ? "2つから好きな方を選ぶだけ" : "段に振り分けて1枚の画像に")
                    .font(.imasHeadline).foregroundStyle(DS.ink)
                Text(purpose == .sort
                     ? "対戦を重ねると、あなたの\(subject == .song ? "好きな曲" : "好きなアイドル")ランキングができあがります。途中でやめても続きから遊べます。"
                     : "選んだ対象がぜんぶ未分類に並びます。段の数・名前・色は自由に変えられ、何枚でも端末に保存できます。")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - つづきから / 前回の結果

    private func savedCard(_ s: SortMakerSession) -> some View {
        let state = s.replay()
        return HStack(spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(s.isFinished ? "前回の結果" : "つづきから")
                    .font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
                if s.isFinished {
                    Text(s.topNames.first.map { "1位 \($0)" } ?? s.scopeLabel)
                        .font(.imasBody.weight(.bold)).foregroundStyle(DS.ink).lineLimit(1)
                } else {
                    Text("\(state.progressPercent)% · \(state.answered)戦 済み")
                        .font(.imasBody.weight(.bold)).foregroundStyle(DS.ink)
                        .monospacedDigit()
                }
                Text(s.scopeLabel).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
            }
            Spacer(minLength: DS.sp2)
            Button {
                AppAnalytics.tap(s.isFinished ? "sort_maker.open_result" : "sort_maker.resume")
                playing = s
            } label: {
                Text(s.isFinished ? "見る" : "再開")
                    .font(.imasSubhead.weight(.bold)).foregroundStyle(DS.onSys)
                    .padding(.horizontal, DS.sp5).frame(minHeight: 40)
                    .background(DS.sys, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
        .overlay(alignment: .leading) {
            if !s.isFinished {
                ProgressView(value: Double(state.progressPercent), total: 100)
                    .tint(DS.sys)
                    .padding(.horizontal, DS.sp4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 6)
            }
        }
    }

    /// 端末に保存してあるティアー表 (新しく触ったものから)。長押しで削除。
    private var savedBoardsSection: some View {
        let boards = tierStore.boards(for: subject)
        return VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                Text("保存したティアー表").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                Text("\(boards.count)").font(.imasCaption).foregroundStyle(DS.ink3).monospacedDigit()
            }
            ImasListContainer {
                ForEach(Array(boards.enumerated()), id: \.element.id) { i, b in
                    if i > 0 { ImasRowDivider(inset: DS.sp4) }
                    Button {
                        AppAnalytics.tap("tier_list.open")
                        openBoard = b
                    } label: {
                        HStack(spacing: DS.sp3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.displayTitle).font(.imasBody.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                                Text("\(b.placedCount) / \(b.itemIds.count) 振り分け済み · \(b.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1).monospacedDigit()
                            }
                            Spacer(minLength: DS.sp2)
                            Image(systemName: "chevron.right")
                                .font(.imasScaled(13, weight: .semibold)).foregroundStyle(DS.ink3)
                        }
                        .padding(.horizontal, DS.sp4)
                        .frame(minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("削除", systemImage: "trash", role: .destructive) { deletingBoard = b }
                    }
                }
            }
            Text("長押しで削除できます。").font(.imasCaption).foregroundStyle(DS.ink3)
        }
    }

    // MARK: - ブランド

    private var brandSection: some View {
        section(title: "ブランド", note: "複数選択可 · 空=全ブランド") {
            let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                BrandIconCell(brandId: nil, label: "全て", iconText: "全", color: nil,
                              isSelected: scope.brandIds.isEmpty) {
                    withAnimation(.easeInOut(duration: 0.15)) { scope.brandIds = [] }
                }
                ForEach(brands) { brand in
                    BrandIconCell(brandId: brand.id, label: brand.shortName, iconText: brand.iconText,
                                  color: brand.color, isSelected: scope.brandIds.contains(brand.id)) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if !scope.brandIds.insert(brand.id).inserted { scope.brandIds.remove(brand.id) }
                        }
                    }
                }
            }
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
                    HStack(spacing: DS.sp3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("歌っているアイドルで絞る").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                            Text(scope.idolIds.isEmpty ? "指定なし" : pickedIdols.map(\.name).joined(separator: "、"))
                                .font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
                        }
                        Spacer(minLength: DS.sp2)
                        if !scope.idolIds.isEmpty {
                            StackedAvatars(idols: pickedIdols, maxVisible: 4, size: 26)
                        }
                        Image(systemName: "chevron.right")
                            .font(.imasScaled(13, weight: .semibold)).foregroundStyle(DS.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !scope.idolIds.isEmpty {
                    Button("アイドルの指定を外す") { scope.idolIds = []; pickedIdols = [] }
                        .font(.imasCaption.weight(.semibold)).foregroundStyle(DS.sys)
                }

                Toggle(isOn: $scope.includeRemixes) {
                    Text("リミックス・別バージョンも入れる").font(.imasSubhead).foregroundStyle(DS.ink)
                }
                .tint(DS.sys)
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
                Text(hint).font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.sp1)
            }
        }
    }

    private var counts: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("対象").font(.imasCaption).foregroundStyle(DS.ink3)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(isLoading ? "…" : "\(candidates.count)").font(.imasTitle2.weight(.bold)).monospacedDigit()
                    Text(subject.counter).font(.imasCaption).foregroundStyle(DS.ink3)
                }
            }
            if purpose == .sort {
            VStack(alignment: .leading, spacing: 2) {
                Text("対戦の目安").font(.imasCaption).foregroundStyle(DS.ink3)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(isLoading ? "…" : "約\(estimate)").font(.imasTitle2.weight(.bold)).monospacedDigit()
                    Text("戦").font(.imasCaption).foregroundStyle(DS.ink3)
                }
            }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.ink)
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 対戦が長すぎる / 少なすぎるときのひとこと。
    private var hint: String? {
        if candidates.count < 2 { return "2\(subject.counter)以上になるように絞り込みをゆるめてください。" }
        if purpose == .tier {
            if candidates.count > Self.tierListLimit {
                return "ティアー表は\(Self.tierListLimit)\(subject.counter)までです。ブランドや曲の種類で絞ってください。"
            }
            return candidates.count > 120 ? "数が多いと振り分けが大変です。ブランドなどで絞るのがおすすめです。" : nil
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
        Button {
            if purpose == .sort, let s = store.session(subject), s.isFinished || !s.answers.isEmpty {
                confirmRestart = true
            } else {
                start()
            }
        } label: {
            Text(purpose == .sort ? "はじめる" : "ティアー表をつくる")
                .font(.imasHeadline).foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
                .opacity(canStart ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp3)
        .background(.bar)
    }

    /// ティアー表に並べられる上限。全部を 1 画面に並べる (遅延表示しない) ので、
    /// 全曲 (2000 超) を並べると画面ごと重くなる。振り分ける手間からも現実的な上限。
    static let tierListLimit = 200

    private var canStart: Bool {
        !isLoading && candidates.count >= 2 && (purpose == .sort || candidates.count <= Self.tierListLimit)
    }

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
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(title).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                if let note { Text(note).font(.imasCaption).foregroundStyle(DS.ink3) }
            }
            content()
        }
        .padding(DS.sp5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }
}
