import SwiftUI

/// ソロ曲クイズの出題設定画面。
/// ブランドを絞り込んでからクイズを開始する。設定は AppStorage で次回起動まで保持する。
///
/// 候補数の見積りと「4 択を組めるか」の判定は imas-core の `domain/quiz_generation.rs` が
/// ゲーム本体と共有する (曲数と歌手数の両方を見る条件が 1 か所にあるので、
/// 「不足表示なのにゲームだけ始まって全問 2 択」というズレが起きない)。
struct SongSingerQuizSetupView: View {

    /// 永続化: カンマ区切りブランドID文字列（空文字列 = 全ブランド）。
    @AppStorage("songQuizBrandIds") private var brandIdsRaw: String = ""

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    /// 推計: 対象範囲の (曲, 原唱アイドル) ペア数とユニーク歌手数、4 択を組めるか
    /// (コアがゲーム本体と同じ母集団条件で数えた結果)。
    @State private var estimate = SongSingerQuizPoolEstimate(songCount: 0, singerCount: 0, isSufficient: false)
    @State private var isEstimating = false
    @State private var navigateToGame = false

    private var canStart: Bool { isEstimating || estimate.isSufficient }

    var body: some View {
        ImasPage {
            ImasSetupHeader(systemImage: "music.microphone", title: "ソロ曲クイズ",
                            message: "ソロ曲を聴いてその歌手を 4 択で当てよう")
            ImasSection("出題ブランド", style: .small, footer: "複数選択可 · 空=全ブランド対象",
                       actionTitle: selectedBrandIds.isEmpty ? nil : "全てに戻す",
                       onAction: selectedBrandIds.isEmpty ? nil : {
                           withAnimation(.easeInOut(duration: 0.15)) { selectedBrandIds = [] }
                       }) {
                ImasBrandPicker(brands: brands, selection: $selectedBrandIds)
            }
            ImasCandidateCount(count: Int(estimate.songCount), unit: "曲", label: "出題候補",
                               secondary: .init(count: Int(estimate.singerCount), unit: "歌手"),
                               note: "4択の選択肢は歌手数が基準です",
                               isLoading: isEstimating, loadingText: "候補を計算中…")
            if !isEstimating && !canStart {
                ImasNotice(kind: .warning,
                           message: "4 択を出すには原唱歌手が最低 4 名必要です。ブランドの選択を増やしてください。")
            }
            ImasButton(title: "スタート", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("song_singer_quiz_setup.start")
                navigateToGame = true
            }
            .disabled(!canStart)
        }
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

    // MARK: - Data

    /// 選択ブランドで絞り込んだときの (曲, 原唱歌手) ペア数とユニーク歌手数を計算する。
    /// SongSingerQuizView.load() と同じクエリを実行し、絞り込み (単一原唱・外部演者除外・
    /// ブランド一致) はコアの母集団条件に任せる。
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

        estimate = songSingerQuizPoolEstimate(
            rows: songQuizOriginalArtistRows(solos: solos, originalArtistIds: origMap),
            singers: songQuizSingerRefs(idols),
            selectedBrandIds: Array(selectedBrandIds))
    }

    // MARK: - Helpers

    private func decodeBrandIds(_ raw: String) -> Set<String> {
        Set(quizBrandIdsDecode(raw: raw))
    }

    private func encodeBrandIds(_ ids: Set<String>) -> String {
        quizBrandIdsEncode(brandIds: Array(ids))
    }
}
