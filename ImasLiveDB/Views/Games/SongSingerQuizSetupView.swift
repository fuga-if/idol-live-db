import SwiftUI

/// ソロ曲クイズの出題設定画面。
/// ブランドを絞り込んでからクイズを開始する。設定は AppStorage で次回起動まで保持する。
struct SongSingerQuizSetupView: View {

    /// 永続化: カンマ区切りブランドID文字列（空文字列 = 全ブランド）。
    @AppStorage("songQuizBrandIds") private var brandIdsRaw: String = ""

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    /// 推計: 対象範囲に含まれる (曲, 原唱アイドル) ペア数。
    @State private var estimatedSongs: Int = 0
    /// 推計: 対象範囲に含まれるユニーク歌手数（4 択を組める人数）。
    @State private var estimatedSingers: Int = 0
    @State private var isEstimating = false
    @State private var navigateToGame = false

    /// 4 択を成立させるために必要な最低候補数。
    private let minimumPool = 4

    private var canStart: Bool { isEstimating || (estimatedSongs >= minimumPool && estimatedSingers >= minimumPool) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                headerCard
                brandSection
                countRow
                if !isEstimating && !canStart {
                    insufficientBanner
                }
                Spacer().frame(height: DS.sp3)
                startButton
                Spacer().frame(height: DS.sp4)
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("ソロ曲クイズ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            SongSingerQuizView(selectedBrandIds: selectedBrandIds)
        }
        .task {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            selectedBrandIds = decodeBrandIds(brandIdsRaw)
            await estimatePool()
        }
        .onChange(of: selectedBrandIds) { _, newValue in
            brandIdsRaw = encodeBrandIds(newValue)
            Task { await estimatePool() }
        }
        .trackScreen("song_singer_quiz_setup")
    }

    // MARK: - ヘッダ

    private var headerCard: some View {
        HStack(spacing: DS.sp4) {
            Image(systemName: "music.microphone")
                .font(.imasScaled(28, weight: .semibold))
                .foregroundStyle(DS.sys)
                .frame(width: 52, height: 52)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("ソロ曲クイズ")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("ソロ曲を聴いてその歌手を 4 択で当てよう")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    // MARK: - ブランド選択

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
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
            brandGrid
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }

    private var brandGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
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

    // MARK: - 出題候補数

    private var countRow: some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "music.note.list")
                .font(.imasScaled(15, weight: .semibold)).foregroundStyle(DS.sys)
            if isEstimating {
                ProgressView().tint(DS.sys).scaleEffect(0.8)
                Text("候補を計算中…").font(.imasSubhead).foregroundStyle(DS.ink3)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("出題候補: \(estimatedSongs) 曲 / \(estimatedSingers) 歌手")
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("4択の選択肢は歌手数が基準です")
                        .font(.imasCaption).foregroundStyle(DS.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.sp4)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - 候補不足バナー

    private var insufficientBanner: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.warning)
                .font(.imasSubhead)
            Text("4 択を出すには原唱歌手が最低 4 名必要です。ブランドの選択を増やしてください。")
                .font(.imasCaption).foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - スタートボタン

    private var startButton: some View {
        Button {
            AppAnalytics.tap("song_singer_quiz_setup.start")
            navigateToGame = true
        } label: {
            Label("スタート", systemImage: "play.fill")
                .font(.imasHeadline.weight(.semibold))
                .foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    canStart ? DS.sys : Color(.systemGray4),
                    in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
    }

    // MARK: - Data

    /// 選択ブランドで絞り込んだときの (曲, 原唱歌手) ペア数とユニーク歌手数を計算する。
    /// SongSingerQuizView.load() と同じクエリを実行する。
    private func estimatePool() async {
        isEstimating = true
        defer { isEstimating = false }

        let solos = (try? await AppContainer.shared.songReading.songs(
            filter: SongSearchFilter(songType: "solo"),
            sortOrder: .titleKana,
            ascending: nil
        )) ?? []
        let origMap = (try? await AppContainer.shared.showReading.originalArtistIds(
            songIds: solos.map(\.song.id)
        )) ?? [:]
        let allIdolIds = Set(origMap.values.flatMap { $0 })
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: Array(allIdolIds))) ?? []
        let idolById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })

        // 単一原唱・外部でない・ブランドマッチのみ残す
        let pairs: [(song: Song, singer: Idol)] = solos.compactMap { sw in
            guard let ids = origMap[sw.song.id], ids.count == 1,
                  let singer = idolById[ids.first!], !singer.isExternal else { return nil }
            guard selectedBrandIds.isEmpty || selectedBrandIds.contains(singer.brandId) else { return nil }
            return (sw.song, singer)
        }

        estimatedSongs = pairs.count
        estimatedSingers = Set(pairs.map(\.singer.id)).count
    }

    // MARK: - Helpers

    private func decodeBrandIds(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func encodeBrandIds(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }
}
