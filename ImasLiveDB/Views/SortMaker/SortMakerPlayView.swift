import SwiftUI

/// 対戦の進行。答えるたびにコアで状態を作り直し、保存する。
@MainActor
@Observable
final class SortMakerPlayModel {
    private(set) var session: SortMakerSession
    private(set) var state: SortMakerState
    /// `session.itemIds` と同じ並び。消えた曲・アイドルは nil。
    private(set) var items: [SortMakerItem?] = []
    private(set) var isLoaded = false

    /// 画面に出す進み具合と残り。ベスト10モードは K 位に勝った新顔の探索が見積りに
    /// 後から乗るので、コアの値は 1 戦ごとに少し戻ることがある。表示だけは戻さない
    /// (1 つ戻る / 読み込み直しで取り直す)。
    private(set) var shownPercent: UInt32 = 0
    private(set) var shownRemaining: UInt32 = 0
    /// 保存した対象のうち、マスタから消えて引けなかった件数。
    var missingCount: Int { items.filter { $0 == nil }.count }

    init(session: SortMakerSession) {
        // 再生は load で 1 回だけ (init は SwiftUI の再評価で何度も走るので重い処理を置かない)。
        self.session = session
        self.state = SortMakerState(pair: nil, answered: 0, estimatedRemaining: 0, progressPercent: 0,
                                    ranking: [], isFinished: false)
    }

    func load() async {
        guard !isLoaded else { return }
        items = await SortMakerCandidates.load(session.subject, ids: session.itemIds)
        state = session.replay()
        resetShown()
        isLoaded = true
        if state.isFinished { finish() }
    }

    private func resetShown() {
        shownPercent = state.progressPercent
        shownRemaining = state.estimatedRemaining
    }

    func item(_ index: UInt32) -> SortMakerItem? {
        let i = Int(index)
        return items.indices.contains(i) ? items[i] : nil
    }

    var canUndo: Bool { !session.answers.isEmpty }

    /// 何戦目か (1 始まり)。
    var round: Int { Int(state.answered) + 1 }

    func answer(_ choice: SortMakerChoice) {
        guard !state.isFinished else { return }
        session.answers.append(choice.code)
        commit()
    }

    func undo() {
        guard canUndo else { return }
        session.answers.removeLast()
        session.isFinished = false
        session.topNames = []
        commit()
        resetShown()
    }

    private func commit() {
        state = session.replay()
        shownPercent = state.isFinished ? 100 : max(shownPercent, state.progressPercent)
        shownRemaining = min(shownRemaining, state.estimatedRemaining)
        session.savedAt = Date()
        if state.isFinished {
            finish()
        } else {
            SortMakerStore.shared.save(session)
        }
    }

    private func finish() {
        session.isFinished = true
        // 消えた項目も位置を詰めない (詰めると「前回の1位」が実際の 2 位になる)。
        session.topNames = state.ranking.prefix(3).map { item($0.item)?.title ?? "（見つかりません）" }
        SortMakerStore.shared.save(session)
    }

    /// 順位表の行 (消えたものは飛ばす)。
    var rankedItems: [(rank: Int, item: SortMakerItem)] {
        state.ranking.compactMap { e in item(e.item).map { (Int(e.rank), $0) } }
    }
}

/// 対戦画面。終わったら同じ画面のまま結果に切り替わる (戻るで対戦に戻らないように)。
struct SortMakerPlayView: View {
    @State private var model: SortMakerPlayModel
    @State private var showProvisional = false

    init(session: SortMakerSession) {
        _model = State(initialValue: SortMakerPlayModel(session: session))
    }

    var body: some View {
        Group {
            if !model.isLoaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.state.isFinished {
                SortMakerResultView(model: model)
                    .transition(.opacity)
            } else {
                SortMakerBattleView(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.state.isFinished)
        .sensoryFeedback(.success, trigger: model.state.isFinished) { _, new in new }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(model.session.subject.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isLoaded && !model.state.isFinished {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProvisional = true
                    } label: {
                        Label("いまの順位", systemImage: "list.number")
                    }
                    .disabled(model.state.ranking.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showProvisional) {
            NavigationStack {
                ScrollView {
                    SortMakerRankingList(rows: model.rankedItems, onSelect: nil)
                        .padding(DS.sp5)
                }
                .background(DS.bg.ignoresSafeArea())
                    .navigationTitle("いまの順位")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showProvisional = false } }
                    }
                    .safeAreaInset(edge: .top) {
                        Text("ここまでの対戦で並んだ分だけの暫定順位です。")
                            .font(.imasCaption).foregroundStyle(DS.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.sp5).padding(.top, DS.sp3)
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .task { await model.load() }
        .onDisappear { MusicKitService.shared.stop() }
        .trackScreen("sort_maker_play")
    }
}

// MARK: - 対戦

struct SortMakerBattleView: View {
    let model: SortMakerPlayModel

    /// 押した側 (一瞬だけ強調してから次の対戦へ)。
    @State private var picked: SortMakerChoice?
    @State private var feedback = 0
    @State private var undoFeedback = 0

    var body: some View {
        GeometryReader { geo in
            // カード 1 枚の中身の幅から絵の大きさを決める (SE / mini の 375pt 幅でもはみ出さない)。
            let cardInner = (geo.size.width - DS.sp5 * 2 - DS.sp4) / 2 - DS.sp4 * 2
            let visual = max(64, min(148, cardInner))
            // 普段は中央に置き、文字を大きくして収まらないときだけスクロールさせる。
            ViewThatFits(in: .vertical) {
                VStack(spacing: DS.sp5) {
                    progressHeader
                    Spacer(minLength: 0)
                    battle(visual: visual)
                    Spacer(minLength: 0)
                }
                ScrollView {
                    VStack(spacing: DS.sp5) {
                        progressHeader
                        battle(visual: visual)
                    }
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.top, DS.sp3)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp3)
                .background(DS.bg)
        }
        .sensoryFeedback(.selection, trigger: feedback)
        .sensoryFeedback(.impact(weight: .light), trigger: undoFeedback)
    }

    @ViewBuilder
    private func battle(visual: CGFloat) -> some View {
        VStack(spacing: DS.sp5) {
            if model.missingCount > 0 {
                Text("対象のうち \(model.missingCount) 件がデータの更新で見つからなくなりました。気になるときは設定から作り直してください。")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("どっちが好き？")
                .font(.imasTitle2.weight(.bold)).foregroundStyle(DS.ink)
                .frame(maxWidth: .infinity)
            if let pair = model.state.pair {
                HStack(alignment: .top, spacing: DS.sp4) {
                    card(pair.left, side: .left, visual: visual)
                    card(pair.right, side: .right, visual: visual)
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .top) { vsBadge.padding(.top, DS.sp5 + visual / 2 - 18) }
                .id("\(pair.left)-\(pair.right)-\(model.state.answered)")
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                        removal: .opacity))
            }
        }
    }

    // MARK: 進み具合

    private var progressHeader: some View {
        VStack(spacing: DS.sp2) {
            HStack(alignment: .firstTextBaseline) {
                Text("第\(model.round)戦").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                Spacer()
                Text("残り約\(model.shownRemaining)戦 · \(model.shownPercent)%")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(DS.sys)
                        .frame(width: max(6, geo.size.width * CGFloat(model.shownPercent) / 100))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.3), value: model.shownPercent)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: カード

    private func card(_ index: UInt32, side: SortMakerChoice, visual: CGFloat) -> some View {
        let item = model.item(index)
        return SortMakerCard(item: item, visualSize: visual, isPicked: picked == side, isDimmed: picked != nil && picked != side && picked != .tie,
                             isTied: picked == .tie) {
            choose(side)
        }
    }

    private var vsBadge: some View {
        Text("VS")
            .font(.imasScaled(13, weight: .black))
            .foregroundStyle(DS.onSys)
            .frame(width: 36, height: 36)
            .background(DS.sys, in: Circle())
            .overlay(Circle().stroke(DS.bg, lineWidth: 3))
            .accessibilityHidden(true)
    }

    // MARK: 下の操作

    private var bottomBar: some View {
        HStack(spacing: DS.sp3) {
            Button {
                undoFeedback += 1
                MusicKitService.shared.stop()
                withAnimation(.easeInOut(duration: 0.2)) { model.undo() }
            } label: {
                Label("1つ戻る", systemImage: "arrow.uturn.backward")
                    .font(.imasSubhead.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(model.canUndo ? DS.ink : DS.ink3)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo || picked != nil)

            Button {
                choose(.tie)
            } label: {
                Label("引き分け", systemImage: "equal")
                    .font(.imasSubhead.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(DS.ink)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(picked != nil)
            .accessibilityHint("どちらも同じくらい好き")
        }
    }

    private func choose(_ choice: SortMakerChoice) {
        guard picked == nil else { return }
        feedback += 1
        MusicKitService.shared.stop()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { picked = choice }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeInOut(duration: 0.22)) {
                model.answer(choice)
                picked = nil
            }
        }
    }
}

/// 対戦カード 1 枚。全面がタップ領域。曲は試聴ボタン付き。
struct SortMakerCard: View {
    let item: SortMakerItem?
    /// ジャケ / アイコンの一辺。画面幅から決まる。
    let visualSize: CGFloat
    let isPicked: Bool
    let isDimmed: Bool
    let isTied: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: item?.seed, brand: item?.brandId, scheme: scheme)
        VStack(spacing: DS.sp3) {
            Button(action: action) {
                VStack(spacing: DS.sp3) {
                    visual
                    VStack(spacing: DS.sp1) {
                        Text(item?.title ?? "（見つかりません）")
                            .font(.imasHeadline).foregroundStyle(DS.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                        if let sub = item?.subtitle {
                            Text(sub).font(.imasCaption).foregroundStyle(DS.ink3)
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, DS.sp4)
                .padding(.top, DS.sp5)
                .padding(.bottom, DS.sp5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rLG, style: .continuous)
                        .stroke(theme.accent, lineWidth: isPicked || isTied ? 3 : 0)
                )
                .overlay(alignment: .top) {
                    Capsule().fill(theme.accent).frame(width: 36, height: 4).padding(.top, 6)
                }
                .scaleEffect(isPicked ? 1.03 : (isDimmed ? 0.97 : 1))
                .opacity(isDimmed ? 0.5 : 1)
                .contentShape(RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
            }
            .buttonStyle(QuizPressStyle())
            .accessibilityLabel(item.map { "\($0.title)\($0.subtitle.map { "、\($0)" } ?? "")" } ?? "不明")
            .accessibilityHint("こちらが好き")

            previewButton
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch item {
        case .song(let song):
            ArtworkImageView(url: song.artworkUrl.flatMap(URL.safeHTTP(string:)), size: visualSize,
                             songTitle: song.title, songId: song.id)
                .allowsHitTesting(false)
        case .idol(let idol):
            IdolAvatarView(idol: idol, size: visualSize * 0.92, reservesPickRing: false)
        case nil:
            ImasArtwork(title: "?", size: visualSize)
        }
    }

    /// 曲だけ: 試聴。カードのタップ (＝選ぶ) とは別のボタンにする。
    @ViewBuilder
    private var previewButton: some View {
        if case .song(let song) = item, let url = song.previewUrl.flatMap(URL.safeHTTP(string:)) {
            let playing = MusicKitService.shared.isPlaying(songId: song.id)
            Button {
                MusicKitService.shared.togglePreview(url: url, songId: song.id)
            } label: {
                Label(playing ? "停止" : "試聴", systemImage: playing ? "stop.fill" : "play.fill")
                    .font(.imasCaption.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                    .padding(.horizontal, DS.sp4).frame(minHeight: 32)
                    .background(DS.fill, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 32)
        }
    }
}
