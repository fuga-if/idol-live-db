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

    private var mode: LyricsQuizModeSetting { LyricsQuizModeSetting(rawValue: modeRaw) ?? .title }
    private var canStart: Bool { !isLoading && publishedIds != nil && estimate.isSufficient }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                headerCard
                modeSection
                brandSection
                countRow
                if !isLoading && loadFailed {
                    offlineBanner
                } else if !isLoading && !estimate.isSufficient {
                    insufficientBanner
                }
                Spacer().frame(height: DS.sp3)
                startButton
                JASRACLicenseNotice(placement: .lyrics)
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: DS.sp4)
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
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

    // MARK: - ヘッダ

    private var headerCard: some View {
        HStack(spacing: DS.sp4) {
            Image(systemName: "text.quote")
                .font(.imasScaled(28, weight: .semibold))
                .foregroundStyle(DS.sys)
                .frame(width: 52, height: 52)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("歌詞クイズ")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("歌詞のワンフレーズから、曲名や続きを 4 択で当てよう")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - 形式

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            Text("出題形式").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
            HStack(spacing: DS.sp3) {
                ForEach(LyricsQuizModeSetting.allCases) { option in
                    modeCard(option)
                }
            }
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    private func modeCard(_ option: LyricsQuizModeSetting) -> some View {
        let selected = option == mode
        return Button {
            AppAnalytics.tap("lyrics_quiz_setup.mode_\(option.rawValue)")
            withAnimation(.easeInOut(duration: 0.15)) { modeRaw = option.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: DS.sp2) {
                HStack {
                    Image(systemName: option.systemImage)
                        .font(.imasScaled(16, weight: .semibold))
                        .foregroundStyle(selected ? DS.onSys : DS.sys)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.imasScaled(16, weight: .semibold))
                        .foregroundStyle(selected ? DS.onSys : DS.ink3)
                }
                Text(option.label).font(.imasSubhead.weight(.bold))
                    .foregroundStyle(selected ? DS.onSys : DS.ink)
                Text(option.blurb).font(.imasCaption)
                    .foregroundStyle(selected ? DS.onSys.opacity(0.8) : DS.ink3)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.sp4)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(selected ? DS.sys : DS.fill,
                        in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - ブランド選択

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text("出題ブランド").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                    Text("複数選択可 · 空=全ブランド対象")
                        .font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 0)
                if !selectedBrandIds.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
                    } label: {
                        Text("全てに戻す")
                            .font(.imasCaption.weight(.semibold)).foregroundStyle(DS.sys)
                    }
                    .buttonStyle(.plain)
                }
            }
            let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                BrandIconCell(
                    brandId: nil, label: "全て", iconText: "全", color: nil,
                    isSelected: selectedBrandIds.isEmpty
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
                }
                ForEach(brands) { brand in
                    BrandIconCell(
                        brandId: brand.id, label: brand.shortName,
                        iconText: brand.iconText, color: brand.color,
                        isSelected: selectedBrandIds.contains(brand.id)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if !selectedBrandIds.insert(brand.id).inserted {
                                selectedBrandIds.remove(brand.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - 出題候補数

    private var countRow: some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "music.note.list")
                .font(.imasScaled(15, weight: .semibold)).foregroundStyle(DS.sys)
            if isLoading {
                ProgressView().tint(DS.sys).scaleEffect(0.8)
                Text("歌詞のある曲を確認中…").font(.imasSubhead).foregroundStyle(DS.ink3)
            } else {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(publishedIds == nil ? "出題候補: —" : "出題候補: \(estimate.songCount) 曲")
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("歌詞を掲載している曲から出題します")
                        .font(.imasCaption).foregroundStyle(DS.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.sp4)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    private var insufficientBanner: some View {
        banner(systemImage: "exclamationmark.triangle.fill",
               text: "4 択を出すには歌詞のある曲が最低 \(lyricsQuizMinimumPool()) 曲必要です。ブランドの選択を増やしてください。")
    }

    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            banner(systemImage: "wifi.exclamationmark",
                   text: "歌詞のある曲を確認できませんでした。歌詞クイズは通信が必要です。")
            Button {
                Task { await load() }
            } label: {
                Label("再試行", systemImage: "arrow.clockwise")
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.sys)
            }
            .buttonStyle(.plain)
        }
    }

    private func banner(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            Image(systemName: systemImage)
                .foregroundStyle(DS.warning)
                .font(.imasSubhead)
            Text(text)
                .font(.imasCaption).foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - スタート

    private var startButton: some View {
        Button {
            AppAnalytics.tap("lyrics_quiz_setup.start_\(mode.rawValue)")
            navigateToGame = true
        } label: {
            Label("スタート", systemImage: "play.fill")
                .font(.imasHeadline.weight(.semibold))
                .foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canStart ? DS.sys : DS.fill,
                            in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
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
