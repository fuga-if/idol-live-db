import SwiftUI

/// アイドル当てクイズの出題設定画面。
/// ブランドを絞り込んでからクイズを開始する。設定は AppStorage で次回起動まで保持する。
///
/// 候補数の見積りと「4 択を組めるか」の判定は imas-core の `domain/quiz_generation.rs` が
/// ゲーム本体と共有する (別条件にすると「開始できるのに候補不足」というズレが起きる)。
/// 保存文字列とブランド id 列の変換規則もコア側。
struct IdolQuizSetupView: View {

    /// 永続化: カンマ区切りブランドID文字列（空文字列 = 全ブランド）。
    @AppStorage("idolQuizBrandIds") private var brandIdsRaw: String = ""

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    /// 出題候補数と「4 択を組めるか」(コアが同じ母集団条件で数えた結果)。
    @State private var estimate = IdolQuizPoolEstimate(count: 0, isSufficient: false)
    @State private var isEstimating = false
    @State private var navigateToGame = false

    private var estimatedCount: Int { Int(estimate.count) }

    /// スタート可能かどうか（推計中は暫定的に許可して二重ロードを防ぐ）。
    private var canStart: Bool { isEstimating || estimate.isSufficient }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                headerCard
                brandSection
                countRow
                if !isEstimating && !estimate.isSufficient {
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
        .navigationTitle("アイドル当てクイズ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            IdolQuizView(selectedBrandIds: selectedBrandIds)
        }
        .task {
            // ブランド一覧の取得と、永続化データの復元を同時に実行。
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            selectedBrandIds = decodeBrandIds(brandIdsRaw)
            await estimatePool()
        }
        .onChange(of: selectedBrandIds) { _, newValue in
            // 変更のたびに AppStorage へ書き戻して候補数を再計算する。
            brandIdsRaw = encodeBrandIds(newValue)
            Task { await estimatePool() }
        }
        .trackScreen("idol_quiz_setup")
    }

    // MARK: - ヘッダ

    private var headerCard: some View {
        HStack(spacing: DS.sp4) {
            Image(systemName: "person.fill.questionmark")
                .font(.imasScaled(28, weight: .semibold))
                .foregroundStyle(DS.sys)
                .frame(width: 52, height: 52)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("アイドル当てクイズ")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("プロフィールのヒントを手がかりに誰かを 4 択で当てよう")
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
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text("出題ブランド").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                    Text("複数選択可 · 空=全ブランド対象")
                        .font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 0)
                if !selectedBrandIds.isEmpty {
                    // リセットボタン: 全ブランドに戻す
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
            Image(systemName: "person.3.fill")
                .font(.imasScaled(15, weight: .semibold)).foregroundStyle(DS.sys)
            if isEstimating {
                ProgressView().tint(DS.sys).scaleEffect(0.8)
                Text("候補を計算中…").font(.imasSubhead).foregroundStyle(DS.ink3)
            } else {
                Text("出題候補: \(estimatedCount) 名")
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
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
            Text("4 択を出すにはアイドルが最低 4 名必要です。ブランドの選択を増やしてください。")
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
            AppAnalytics.tap("idol_quiz_setup.start")
            navigateToGame = true
        } label: {
            Label("スタート", systemImage: "play.fill")
                .font(.imasHeadline.weight(.semibold))
                .foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    canStart ? DS.sys : DS.fill,
                    in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
    }

    // MARK: - Data

    /// 選択ブランドで絞り込んだときの出題候補アイドル数を計算する。
    /// IdolQuizView の出題生成 (`idolQuizSession`) と同じ母集団条件をコアが持つので、
    /// ここでの見積りと実際の出題プールは必ず一致する
    /// (以前は facts (プロフィール事実3件以上) チェックを省いた近似値だったため、
    /// 見積り上は開始可能でも実際は候補不足で始まってしまうことがあった)。
    private func estimatePool() async {
        isEstimating = true
        defer { isEstimating = false }
        let all = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        estimate = idolQuizPoolEstimate(idols: idolQuizRefs(all), selectedBrandIds: Array(selectedBrandIds))
    }

    // MARK: - Helpers

    private func decodeBrandIds(_ raw: String) -> Set<String> {
        Set(quizBrandIdsDecode(raw: raw))
    }

    private func encodeBrandIds(_ ids: Set<String>) -> String {
        quizBrandIdsEncode(brandIds: Array(ids))
    }
}
