import SwiftUI
import MusicKit

struct IntroGameSetupView: View {
    @Environment(AppDatabase.self) private var database

    /// 曲一覧の絞り込みをそのまま出題プールにする場合のプリセット (nil ならブランド選択)。
    var presetPool: [Song]? = nil
    var presetLabel: String? = nil

    /// 設定画面内で「絞り込んで出題」から曲一覧を開いて選び直したプリセット。
    @State private var pickedPool: [Song]? = nil
    @State private var pickedLabel: String? = nil

    /// 実際に使う出題範囲 (アプリ内で選び直したものを優先)。
    private var effectivePool: [Song]? { pickedPool ?? presetPool }
    private var effectiveLabel: String? { pickedLabel ?? presetLabel }

    @State private var session = IntroGameSession()
    @State private var partySession = IntroPartySession()
    @State private var navigateToParty = false
    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    @State private var mode: IntroGameMode = .normal
    @State private var answerMode: IntroAnswerMode = .choices
    @AppStorage("introPlaybackMode") private var playbackRaw: String = IntroPlaybackMode.full.rawValue
    private var playback: IntroPlaybackMode { IntroPlaybackMode(rawValue: playbackRaw) ?? .full }
    @State private var questionCount: Int = 10
    @State private var introDuration: TimeInterval = 5.0
    @State private var rushTimeLimit: TimeInterval = 60
    @State private var isLoading = false
    @State private var showAdvanced = false
    @State private var showSongFilter = false
    @State private var navigateToGame = false
    @State private var errorMessage: String? = nil
    @State private var authStatus: MusicAuthorization.Status = MusicKitService.shared.authorizationStatus

    private let questionCounts = [5, 10, 20]
    private let rushTimes: [(label: String, value: TimeInterval)] = [
        ("30秒", 30), ("60秒", 60), ("120秒", 120),
    ]
    private let durations: [(label: String, sub: String, value: TimeInterval)] = [
        ("0.2秒", "超イントロ", 0.2),
        ("2秒", "再生", 2.0),
        ("5秒", "再生", 5.0),
        ("10秒", "再生", 10.0),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ① モード (先に決める)
                IDSectionLabel(text: "モード")
                    .padding(.horizontal, 20)
                Spacer().frame(height: 12)
                modeSection
                    .padding(.horizontal, 20)

                // ② 出題範囲: プリセット(曲一覧の絞り込み) があればそれを表示、無ければブランド選択。
                Spacer().frame(height: 24)
                IDSectionLabel(text: "出題範囲", hint: effectivePool == nil ? "ブランドで絞る" : nil)
                    .padding(.horizontal, 20)
                Spacer().frame(height: 12)
                if let pool = effectivePool {
                    presetRangeCard(count: IntroGameSession.playable(pool).count)
                        .padding(.horizontal, 20)
                    Spacer().frame(height: 10)
                    refineButton(title: "出題範囲を変更")
                        .padding(.horizontal, 20)
                } else {
                    brandSection
                        .padding(.horizontal, 20)
                    Spacer().frame(height: 10)
                    refineButton(title: "タグ・担当・検索で絞り込んで出題")
                        .padding(.horizontal, 20)
                }

                // ③ モード別の設定 (必要な項目だけ出す)
                modeSpecificSection

                // ④ 詳細設定 (折りたたみ): 再生方式・難易度
                Spacer().frame(height: 24)
                advancedSection
                    .padding(.horizontal, 20)

                if authStatus != .authorized {
                    Spacer().frame(height: 20)
                    authWarningCard
                        .padding(.horizontal, 20)
                }

                if let err = errorMessage {
                    Spacer().frame(height: 16)
                    errorCard(err)
                        .padding(.horizontal, 20)
                }

                Spacer().frame(height: 32)

                IDActionButton(
                    title: isLoading ? "問題を生成中..." : "スタート",
                    icon: isLoading ? nil : "play.fill",
                    style: .primary,
                    isLoading: isLoading
                ) {
                    AppAnalytics.tap("intro_game_setup.start")
                    Task { await startGame() }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 32)
            }
            .padding(.top, 16)
        }
        .background(ID.menuBg.ignoresSafeArea())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            IntroGameView(session: session)
        }
        .navigationDestination(isPresented: $showSongFilter) {
            // 曲一覧でタグ/担当/検索などで絞り込み →「この範囲で出題」で設定に戻りプール反映。
            SongListView(
                selectionMode: true,
                onSelectPool: { pool, label in
                    pickedPool = pool
                    pickedLabel = label
                    showSongFilter = false
                }
            )
            .environment(database)
        }
        .navigationDestination(isPresented: $navigateToParty) {
            IntroPartyGameView(session: partySession)
        }
        .task {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        }
        .trackScreen("intro_game_setup")
    }

    // MARK: - Brand Section

    /// ブランド選択 = 曲フィルターと同じ丸アイコングリッド (BrandIconCell)。複数選択可・空=全て。
    private var brandSection: some View {
        let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
            BrandIconCell(brandId: nil, label: "全て", iconText: "全", color: nil,
                          isSelected: selectedBrandIds.isEmpty) {
                withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
            }
            ForEach(brands) { brand in
                BrandIconCell(brandId: brand.id, label: brand.shortName, iconText: brand.iconText,
                              color: brand.color, isSelected: selectedBrandIds.contains(brand.id)) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if !selectedBrandIds.insert(brand.id).inserted {
                            selectedBrandIds.remove(brand.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Count / Duration Sections

    private var countSection: some View {
        HStack(spacing: 8) {
            ForEach(questionCounts, id: \.self) { n in
                IDSegmentButton(
                    primary: "\(n)",
                    secondary: "問",
                    selected: questionCount == n
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { questionCount = n }
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(durations, id: \.value) { d in
                    IDSegmentButton(
                        primary: d.label,
                        secondary: d.sub,
                        selected: abs(introDuration - d.value) < 0.001
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { introDuration = d.value }
                    }
                }
            }

            // 細かく秒数を決めるスライダー (0.2〜10秒)。超イントロ(1秒未満)も自由に。
            VStack(spacing: 6) {
                HStack {
                    Text(introDuration < 1.0 ? "超イントロ" : "再生時間")
                        .font(ID.font(12, weight: .semibold))
                        .foregroundColor(introDuration < 1.0 ? ID.accentGold : ID.menuTextSecondary)
                    Spacer()
                    Text(String(format: "%.1f秒", introDuration))
                        .font(ID.font(14, weight: .bold))
                        .foregroundColor(ID.menuText)
                        .monospacedDigit()
                }
                Slider(value: $introDuration, in: 0.2...10.0, step: 0.1)
                    .tint(ID.accentGold)
            }
        }
    }

    /// タグ・担当・検索で細かく絞って出題したい時に曲一覧へ飛ぶボタン。
    private func refineButton(title: String) -> some View {
        Button {
            AppAnalytics.tap("intro_game_setup.refine")
            showSongFilter = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.imasScaled( 14, weight: .semibold))
                Text(title)
                    .font(ID.font(13, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.imasScaled( 12, weight: .semibold))
            }
            .foregroundColor(ID.accentPurple)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ID.accentPurple.opacity(0.08))
            .clipShape(IDCorner(radius: 12))
        }
        .idPress()
    }

    /// 出題範囲: 曲一覧の絞り込みプリセットの表示カード。
    private func presetRangeCard(count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.imasScaled( 18, weight: .bold))
                .foregroundColor(ID.accentPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text(effectiveLabel ?? "曲一覧の絞り込み")
                    .font(ID.font(14, weight: .bold))
                    .foregroundColor(ID.menuText)
                    .lineLimit(1)
                Text("\(count)曲から出題")
                    .font(.imasScaled(12))
                    .foregroundColor(ID.menuTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner(radius: 14))
    }

    // MARK: - Section layout helpers

    /// 見出し付きセクション (上に余白 + ラベル + 中身)。
    @ViewBuilder
    private func labeledSection<C: View>(_ title: String, hint: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        Spacer().frame(height: 24)
        IDSectionLabel(text: title, hint: hint).padding(.horizontal, 20)
        Spacer().frame(height: 12)
        content().padding(.horizontal, 20)
    }

    /// ③ モード別に必要な設定だけ出す。
    @ViewBuilder
    private var modeSpecificSection: some View {
        switch mode {
        case .normal:
            labeledSection("回答方式") { answerModeSection }
            labeledSection("問題数") { countSection }
        case .rush:
            labeledSection("制限時間") { rushTimeSection }
        case .allSongs:
            Spacer().frame(height: 20)
            allSongsNote.padding(.horizontal, 20)
        case .party:
            labeledSection("ラウンド数") { countSection }
        }
    }

    private var allSongsNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "infinity")
                .font(.imasScaled( 16, weight: .bold))
                .foregroundColor(ID.accentGold)
            Text("選択した出題範囲の全曲を出し切るまで挑戦。タイムと正答率を競います。")
                .font(.imasScaled(12))
                .foregroundColor(ID.menuTextSecondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(ID.accentGold.opacity(0.08))
        .clipShape(IDCorner(radius: 14))
    }

    /// ④ 詳細設定 (折りたたみ): 再生方式・難易度。
    private var advancedSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("詳細設定")
                        .font(ID.font(11, weight: .bold))
                        .tracking(2)
                        .foregroundColor(ID.menuTextMuted)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.imasScaled( 12, weight: .bold))
                        .foregroundColor(ID.menuTextMuted)
                }
                .padding(.vertical, 6)
            }
            .idPress()

            if showAdvanced {
                VStack(spacing: 18) {
                    advancedBlock("再生方式") { playbackSection }
                    if mode == .normal || mode == .party {
                        advancedBlock("難易度 (イントロ再生時間)") { durationSection }
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    @ViewBuilder
    private func advancedBlock<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ID.font(11, weight: .bold))
                .tracking(1.5)
                .foregroundColor(ID.menuTextMuted)
            content()
        }
    }

    // MARK: - Mode / Answer Mode

    private var modeSection: some View {
        VStack(spacing: 8) {
            modeRow(.normal, icon: "list.number", title: "ノーマル", sub: "決めた問題数で挑戦")
            modeRow(.rush, icon: "timer", title: "ラッシュ", sub: "制限時間内に何問正解できるか")
            modeRow(.allSongs, icon: "infinity", title: "全曲チャレンジ", sub: "全曲出し切るまで・タイムと正答率を競う")
            modeRow(.party, icon: "person.2.fill", title: "パーティ対戦", sub: "1台2人・分割画面で早押し")
        }
    }

    private func modeRow(_ m: IntroGameMode, icon: String, title: String, sub: String) -> some View {
        let selected = mode == m
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { mode = m }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.imasScaled( 16, weight: .semibold))
                    .foregroundColor(selected ? ID.menuCardDarkText : ID.accentPurple)
                    .frame(width: 36, height: 36)
                    .background((selected ? Color.white.opacity(0.18) : ID.accentPurple.opacity(0.10)))
                    .clipShape(IDCorner(radius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ID.font(15, weight: .bold))
                        .foregroundColor(selected ? ID.menuCardDarkText : ID.menuText)
                    Text(sub)
                        .font(ID.font(11, weight: .semibold))
                        .foregroundColor(selected ? ID.menuCardDarkText.opacity(0.8) : ID.menuTextSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(ID.menuCardDarkText)
                        .font(.imasScaled( 18))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? ID.menuCardDark : ID.menuCardSubtle)
            .clipShape(IDCorner(radius: 14))
        }
        .idPress()
    }

    private var answerModeSection: some View {
        HStack(spacing: 8) {
            answerModeButton(.choices, icon: "square.grid.2x2.fill", title: "4択", sub: "タップで回答")
            answerModeButton(.voice, icon: "mic.fill", title: "音声判定", sub: "声で曲名を回答")
        }
    }

    private func answerModeButton(_ a: IntroAnswerMode, icon: String, title: String, sub: String) -> some View {
        let selected = answerMode == a
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { answerMode = a }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.imasScaled( 18, weight: .semibold))
                Text(title)
                    .font(ID.font(15, weight: .bold))
                Text(sub)
                    .font(ID.font(10, weight: .semibold))
            }
            .foregroundColor(selected ? ID.menuCardDarkText : ID.menuTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selected ? ID.menuCardDark : ID.menuCardSubtle)
            .clipShape(IDCorner(radius: 16))
        }
        .idPress()
    }

    private var playbackSection: some View {
        HStack(spacing: 8) {
            playbackButton(.full, icon: "music.note", title: "フル再生", sub: "実イントロ(要サブスク)")
            playbackButton(.preview, icon: "bolt.fill", title: "プレビュー", sub: "30秒・サクサク")
        }
    }

    private func playbackButton(_ p: IntroPlaybackMode, icon: String, title: String, sub: String) -> some View {
        let selected = playback == p
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { playbackRaw = p.rawValue }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.imasScaled( 18, weight: .semibold))
                Text(title)
                    .font(ID.font(15, weight: .bold))
                Text(sub)
                    .font(ID.font(10, weight: .semibold))
            }
            .foregroundColor(selected ? ID.menuCardDarkText : ID.menuTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selected ? ID.menuCardDark : ID.menuCardSubtle)
            .clipShape(IDCorner(radius: 16))
        }
        .idPress()
    }

    private var rushTimeSection: some View {
        HStack(spacing: 8) {
            ForEach(rushTimes, id: \.value) { t in
                IDSegmentButton(
                    primary: t.label.replacingOccurrences(of: "秒", with: ""),
                    secondary: "秒",
                    selected: abs(rushTimeLimit - t.value) < 0.001
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { rushTimeLimit = t.value }
                }
            }
        }
    }

    // MARK: - Warnings / Error

    private var authWarningCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(ID.accentGold)
                Text("Apple Music が未認証です")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.menuText)
                Spacer()
            }
            IDActionButton(title: "Apple Music を許可する", style: .secondary) {
                AppAnalytics.tap("intro_game_setup.music_auth")
                Task {
                    await MusicKitService.shared.requestAuthorization()
                    authStatus = MusicKitService.shared.authorizationStatus
                }
            }
        }
        .padding(14)
        .background(ID.accentGold.opacity(0.08))
        .clipShape(IDCorner(radius: 14))
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(ID.incorrect)
            Text(msg)
                .font(.imasScaled( 13))
                .foregroundColor(ID.menuText)
            Spacer()
        }
        .padding(14)
        .background(ID.incorrect.opacity(0.08))
        .clipShape(IDCorner(radius: 14))
    }

    // MARK: - Start

    private func startGame() async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true

        if MusicKitService.shared.authorizationStatus == .notDetermined {
            await MusicKitService.shared.requestAuthorization()
            authStatus = MusicKitService.shared.authorizationStatus
        }

        let settings = IntroGameSettings(
            mode: mode,
            answerMode: answerMode,
            playback: playback,
            questionCount: questionCount,
            introDuration: introDuration,
            rushTimeLimit: rushTimeLimit,
            selectedBrandIds: selectedBrandIds.isEmpty ? nil : selectedBrandIds
        )

        do {
            if mode == .party {
                partySession.settings = settings
                partySession.presetPool = effectivePool
                try await partySession.generateQuestions(database: database)
                if partySession.questions.isEmpty {
                    errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
                } else {
                    navigateToParty = true
                }
            } else {
                session.settings = settings
                session.presetPool = effectivePool
                try await session.generateQuestions(database: database)
                if session.questions.isEmpty {
                    errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
                } else {
                    navigateToGame = true
                }
            }
        } catch {
            errorMessage = "エラー: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - IDSegmentButton

private struct IDSegmentButton: View {
    let primary: String
    let secondary: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(primary)
                    .font(ID.font(22, weight: .black))
                Text(secondary)
                    .font(ID.font(11, weight: .bold))
            }
            .foregroundColor(selected ? ID.menuCardDarkText : ID.menuTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selected ? ID.menuCardDark : ID.menuCardSubtle)
            .clipShape(IDCorner(radius: 16))
        }
        .idPress()
    }
}
