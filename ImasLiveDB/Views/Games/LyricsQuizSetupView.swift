import SwiftUI

/// 歌詞クイズの出題形式 (保存値)。コアの `LyricsQuizMode` と 1:1。
/// rawValue は AppStorage の永続値なので変更しない。
enum LyricsQuizModeSetting: String, CaseIterable, Identifiable {
    case title
    case nextLine

    var id: String { rawValue }

    var core: LyricsQuizMode {
        switch self {
        case .title:    return .title
        case .nextLine: return .nextLine
        }
    }

    var label: String {
        switch self {
        case .title:    return "曲名当て"
        case .nextLine: return "続きはどれ"
        }
    }

    var blurb: String {
        switch self {
        case .title:    return "歌詞の1行から曲名を当てる"
        case .nextLine: return "歌詞の続きのフレーズを当てる"
        }
    }

    var systemImage: String {
        switch self {
        case .title:    return "music.note"
        case .nextLine: return "text.line.first.and.arrowtriangle.forward"
        }
    }
}

/// 同梱 SQLite の曲 → 歌詞クイズの母集団に渡す射影。出題設定画面の見積りとゲーム本体が
/// 同じ母集団を見るよう、変換はこの 1 か所に置く。どの曲に歌詞があるかはサーバの
/// 公開曲 id と突き合わせてコアが決める。
func lyricsQuizSongRefs(_ songs: [SongWithArtists]) -> [LyricsQuizSongRef] {
    songs.map { LyricsQuizSongRef(id: $0.song.id, brandId: $0.song.brandId ?? "") }
}

/// 歌詞クイズの出題設定画面。形式とブランドを選んでから開始する。設定は AppStorage で保持する。
///
/// 母集団は「歌詞を公開している曲」なので、サーバの公開曲一覧 (`GET /lyrics/published`、
/// 本文は含まない) が要る。オフラインでは始められないので、その旨を出して再試行させる。
struct LyricsQuizSetupView: View {

    @AppStorage("lyricsQuizBrandIds") private var brandIdsRaw: String = ""
    @AppStorage("lyricsQuizMode") private var modeRaw: String = LyricsQuizModeSetting.title.rawValue

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    @State private var songs: [SongWithArtists] = []
    @State private var publishedIds: [String]?
    @State private var loadFailed = false
    @State private var estimate = LyricsQuizPoolEstimate(songCount: 0, isSufficient: false)
    @State private var isLoading = true
    @State private var navigateToGame = false

    private var mode: LyricsQuizModeSetting {
        get { LyricsQuizModeSetting(rawValue: modeRaw) ?? .title }
        nonmutating set { modeRaw = newValue.rawValue }
    }
    private var canStart: Bool { !isLoading && publishedIds != nil && estimate.isSufficient }

    var body: some View {
        ImasPage {
            ImasSetupHeader(systemImage: "text.quote", title: "歌詞クイズ",
                            message: "歌詞のワンフレーズから、曲名や続きを 4 択で当てよう")
            modeSection
            ImasSection("出題ブランド", style: .small, footer: "複数選択可 · 空=全ブランド対象",
                       actionTitle: selectedBrandIds.isEmpty ? nil : "全てに戻す",
                       onAction: selectedBrandIds.isEmpty ? nil : {
                           withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
                       }) {
                ImasBrandPicker(brands: brands, selection: $selectedBrandIds)
            }
            ImasCandidateCount(count: publishedIds == nil ? nil : Int(estimate.songCount),
                               unit: "曲", label: "出題候補", note: "歌詞を掲載している曲から出題します",
                               isLoading: isLoading, loadingText: "歌詞のある曲を確認中…")
            if !isLoading && loadFailed {
                ImasNotice(kind: .error, message: "歌詞のある曲を確認できませんでした。歌詞クイズは通信が必要です。",
                           actionTitle: "再試行", actionSystemImage: "arrow.clockwise") { Task { await load() } }
            } else if !isLoading && !estimate.isSufficient {
                ImasNotice(kind: .warning,
                           message: "4 択を出すには歌詞のある曲が最低 \(lyricsQuizMinimumPool()) 曲必要です。ブランドの選択を増やしてください。")
            }
            ImasButton(title: "スタート", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("lyrics_quiz_setup.start_\(mode.rawValue)")
                navigateToGame = true
            }
            .disabled(!canStart)
            JASRACLicenseNotice(placement: .lyrics)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("歌詞クイズ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            LyricsQuizView(mode: mode.core, songs: songs, publishedSongIds: publishedIds ?? [],
                           selectedBrandIds: selectedBrandIds)
        }
        .task {
            selectedBrandIds = Set(quizBrandIdsDecode(raw: brandIdsRaw))
            await load()
        }
        .onChange(of: selectedBrandIds) { _, newValue in
            brandIdsRaw = quizBrandIdsEncode(brandIds: Array(newValue))
            refreshEstimate()
        }
        .trackScreen("lyrics_quiz_setup")
    }

    // MARK: - 形式

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.header) {
            ImasSectionHeader(title: "出題形式", tight: true)
            ImasChoiceCards(
                choices: LyricsQuizModeSetting.allCases.map {
                    .init(value: $0, title: $0.label, systemImage: $0.systemImage, subtitle: $0.blurb)
                },
                selection: Binding(
                    get: { mode },
                    set: { newValue in
                        AppAnalytics.tap("lyrics_quiz_setup.mode_\(newValue.rawValue)")
                        mode = newValue
                    }
                )
            )
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        loadFailed = false
        if brands.isEmpty {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        }
        if songs.isEmpty {
            songs = (try? await AppContainer.shared.songReading.songs(
                filter: SongSearchFilter(), sortOrder: .titleKana, ascending: nil)) ?? []
        }
        do {
            publishedIds = try await AppContainer.shared.lyricsQuizReading.publishedSongIds()
        } catch {
            publishedIds = nil
            loadFailed = true
        }
        refreshEstimate()
    }

    private func refreshEstimate() {
        estimate = lyricsQuizPoolEstimate(songs: lyricsQuizSongRefs(songs),
                                          publishedSongIds: publishedIds ?? [],
                                          selectedBrandIds: Array(selectedBrandIds))
    }
}
