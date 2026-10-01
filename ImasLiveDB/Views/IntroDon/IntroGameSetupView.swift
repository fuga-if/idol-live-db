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

    /// 遷移中か。子が dismiss() したときに route を倒すための橋渡し。
    private var isPushingRoute: Binding<Bool> {
        Binding(
            get: { pushedRoute != nil },
            set: { if !$0 { pushedRoute = nil } }
        )
    }

    /// 実際に使う出題範囲 (アプリ内で選び直したものを優先)。
    private var effectivePool: [Song]? { pickedPool ?? presetPool }
    private var effectiveLabel: String? { pickedLabel ?? presetLabel }

    @State private var session = IntroGameSession()
    @State private var partySession = IntroPartySession()
    /// 結果画面の「ホームに戻る」を Game 経由で受け取るシグナル。
    @State private var exitSignal = IntroDonExitSignal()
    @Environment(\.dismiss) private var dismiss
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
    /// 設定画面から進む先 (navigationDestination は下の 1 つだけで捌く)。
    private enum PushedRoute { case game, songFilter, party }
    @State private var pushedRoute: PushedRoute? = nil
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
        ImasPage {
            // ① モード (先に決める)
            ImasSectionHeader(title: "モード", tight: true)
            modeSection

            // ② 出題範囲: プリセット(曲一覧の絞り込み) があればそれを表示、無ければブランド選択。
            ImasSectionHeader(title: "出題範囲", count: effectivePool == nil ? "ブランドで絞る" : nil, tight: true)
            if let pool = effectivePool {
                presetRangeCard(count: IntroGameSession.playable(pool).count)
                refineButton(title: "出題範囲を変更")
            } else {
                ImasBrandPicker(brands: brands, selection: $selectedBrandIds)
                refineButton(title: "タグ・担当・検索で絞り込んで出題")
            }

            // ③ モード別の設定 (必要な項目だけ出す)
            modeSpecificSection

            // ④ 詳細設定 (折りたたみ): 再生方式・難易度
            advancedSection

            if authStatus != .authorized {
                ImasNotice(kind: .warning, message: "Apple Music が未認証です",
                           actionTitle: "Apple Music を許可する") {
                    AppAnalytics.tap("intro_game_setup.music_auth")
                    Task {
                        await MusicKitService.shared.requestAuthorization(includingMediaLibrary: true)
                        authStatus = MusicKitService.shared.authorizationStatus
                    }
                }
            }

            if let err = errorMessage {
                ImasNotice(kind: .error, message: err)
            }

            ImasButton(title: isLoading ? "問題を生成中..." : "スタート",
                      systemImage: isLoading ? nil : "play.fill",
                      role: .primary, size: .large, isLoading: isLoading) {
                AppAnalytics.tap("intro_game_setup.start")
                Task { await startGame() }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        // **遷移先はここ 1 つだけ。** 同じ View に navigationDestination(isPresented:) を
        // 複数重ねるのは Apple が非サポートとしている書き方で、どれが使われるか保証がない
        // (ゲーム / 曲フィルター / パーティの 3 つを並べていた)。**ここに 2 つ目を足さず、
        // PushedRoute に case を足すこと。**
        .navigationDestination(isPresented: isPushingRoute) {
            switch pushedRoute {
            case .game:
                IntroGameView(session: session, exitSignal: exitSignal)
            case .songFilter:
                // 曲一覧でタグ/担当/検索などで絞り込み →「この範囲で出題」で設定に戻りプール反映。
                SongListView(
                    selectionMode: true,
                    onSelectPool: { pool, label in
                        pickedPool = pool
                        pickedLabel = label
                        pushedRoute = nil
                    }
                )
                .environment(database)
            case .party:
                IntroPartyGameView(session: partySession)
            case nil:
                EmptyView()
            }
        }
        // 「ホームに戻る」: Game が自分を pop してここが見えるようになった後に届く。
        // (隠れている間は SwiftUI が onChange を走らせないので、Game 側で拾わせない)
        .onChange(of: exitSignal.exitToHomeToken) { _, _ in
            dismiss()
        }
        .task {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        }
        .trackScreen("intro_game_setup")
    }

    // MARK: - Count / Duration Sections

    private var countSection: some View {
        ImasChoiceCards(
            choices: questionCounts.map { .init(value: $0, title: "\($0)", subtitle: "問") },
            selection: Binding(get: { questionCount }, set: { questionCount = $0 }),
            style: .numeral
        )
    }

    private var durationSection: some View {
        VStack(spacing: DS.Space.gapLoose) {
            ImasChoiceCards(
                choices: durations.map { .init(value: $0.value, title: $0.label, subtitle: $0.sub) },
                selection: Binding(get: { introDuration }, set: { introDuration = $0 }),
                style: .numeral
            )

            // 細かく秒数を決めるスライダー (0.2〜10秒)。超イントロ(1秒未満)も自由に。
            VStack(spacing: DS.Space.gap) {
                HStack {
                    Text(introDuration < 1.0 ? "超イントロ" : "再生時間")
                        .imasText(.sectionLabel, color: introDuration < 1.0 ? DS.favorite : DS.ink2)
                    Spacer()
                    Text(String(format: "%.1f秒", introDuration))
                        .imasText(.value)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { introDuration },
                    // 0.1 刻みへ丸めてから入れる。浮動小数の誤差が残ると、プリセット値
                    // (例: 5.0) ぴったりに乗っても札の選択表示 (`==` 比較) と噛み合わなくなる。
                    set: { introDuration = (($0 * 10).rounded()) / 10 }
                ), in: 0.2...10.0, step: 0.1)
                    .tint(DS.favorite)
            }
        }
    }

    /// タグ・担当・検索で細かく絞って出題したい時に曲一覧へ飛ぶボタン。
    private func refineButton(title: String) -> some View {
        Button {
            AppAnalytics.tap("intro_game_setup.refine")
            pushedRoute = .songFilter
        } label: {
            ImasNavRow(title: title, systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.imasRow)
    }

    /// 出題範囲: 曲一覧の絞り込みプリセットの表示カード。
    private func presetRangeCard(count: Int) -> some View {
        ImasCard(padding: 0) {
            ImasRow(title: effectiveLabel ?? "曲一覧の絞り込み", subtitle: "\(count)曲から出題",
                    leading: .icon("line.3.horizontal.decrease.circle.fill", tone: .themed))
        }
    }

    // MARK: - Section layout helpers

    /// 見出し付きセクション (見出し + 中身)。
    @ViewBuilder
    private func labeledSection<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        ImasSectionHeader(title: title, tight: true)
        content()
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
            allSongsNote
        case .party:
            labeledSection("ラウンド数") { countSection }
        }
    }

    private var allSongsNote: some View {
        ImasNotice(kind: .info, message: "選択した出題範囲の全曲を出し切るまで挑戦。タイムと正答率を競います。",
                   systemImage: "infinity")
    }

    /// ④ 詳細設定 (折りたたみ): 再生方式・難易度。
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.imasStandard) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("詳細設定").imasText(.sectionLabel)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.imasCaption.weight(.bold))
                        .foregroundStyle(DS.ink3)
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    advancedBlock("再生方式") { playbackSection }
                    if mode == .normal || mode == .party {
                        advancedBlock("難易度 (イントロ再生時間)") { durationSection }
                    }
                }
                .padding(.top, DS.Space.gapLoose)
            }
        }
    }

    @ViewBuilder
    private func advancedBlock<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.header) {
            ImasSectionHeader(title: title, tight: true)
            content()
        }
    }

    // MARK: - Mode / Answer Mode

    private var modeSection: some View {
        ImasChoiceCards(
            choices: [
                .init(value: IntroGameMode.normal, title: "ノーマル", systemImage: "list.number", subtitle: "決めた問題数で挑戦"),
                .init(value: .rush, title: "ラッシュ", systemImage: "timer", subtitle: "制限時間内に何問正解できるか"),
                .init(value: .allSongs, title: "全曲チャレンジ", systemImage: "infinity", subtitle: "全曲出し切るまで・タイムと正答率を競う"),
                .init(value: .party, title: "パーティ対戦", systemImage: "person.2.fill", subtitle: "1台2人・分割画面で早押し"),
            ],
            selection: Binding(get: { mode }, set: { mode = $0 }),
            style: .row
        )
    }

    private var answerModeSection: some View {
        ImasChoiceCards(
            choices: [
                .init(value: IntroAnswerMode.choices, title: "4択", systemImage: "square.grid.2x2.fill", subtitle: "タップで回答"),
                .init(value: .voice, title: "音声判定", systemImage: "mic.fill", subtitle: "声で曲名を回答"),
            ],
            selection: Binding(get: { answerMode }, set: { answerMode = $0 })
        )
    }

    private var playbackSection: some View {
        ImasChoiceCards(
            choices: [
                .init(value: IntroPlaybackMode.full, title: "フル再生", systemImage: "music.note", subtitle: "実イントロ(要サブスク)"),
                .init(value: .preview, title: "プレビュー", systemImage: "bolt.fill", subtitle: "30秒・サクサク"),
            ],
            selection: Binding(get: { playback }, set: { playbackRaw = $0.rawValue })
        )
    }

    private var rushTimeSection: some View {
        ImasChoiceCards(
            choices: rushTimes.map { .init(value: $0.value, title: $0.label.replacingOccurrences(of: "秒", with: ""), subtitle: "秒") },
            selection: Binding(get: { rushTimeLimit }, set: { rushTimeLimit = $0 }),
            style: .numeral
        )
    }

    // MARK: - Start

    private func startGame() async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true

        if MusicKitService.shared.authorizationStatus == .notDetermined {
            await MusicKitService.shared.requestAuthorization(includingMediaLibrary: true)
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
                    pushedRoute = .party
                }
            } else {
                session.settings = settings
                session.presetPool = effectivePool
                try await session.generateQuestions(database: database)
                if session.questions.isEmpty {
                    errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
                } else {
                    pushedRoute = .game
                }
            }
        } catch {
            errorMessage = "エラー: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
