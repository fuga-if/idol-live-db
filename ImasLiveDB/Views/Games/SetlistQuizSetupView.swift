import SwiftUI

/// セトリ当てクイズの出題設定画面。
/// ブランドを絞り込んでからクイズを開始する。設定は AppStorage で次回起動まで保持する。
///
/// 出題できる公演数の見積りはゲーム本体と同じ条件で imas-core の `domain/setlist_quiz.rs` が数える。
struct SetlistQuizSetupView: View {

    /// 永続化: カンマ区切りブランドID文字列（空文字列 = 全ブランド）。
    @AppStorage("setlistQuizBrandIds") private var brandIdsRaw: String = ""

    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    /// 出題できる公演数 (コアがゲーム本体と同じ条件で数えた結果)。
    @State private var estimate = SetlistQuizPoolEstimate(showCount: 0, isSufficient: false)
    @State private var isEstimating = false
    @State private var navigateToGame = false

    private var canStart: Bool { isEstimating || estimate.isSufficient }

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
        .navigationTitle("セトリ当て")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            SetlistQuizView(selectedBrandIds: selectedBrandIds)
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
        .trackScreen("setlist_quiz_setup")
    }

    // MARK: - ヘッダ

    private var headerCard: some View {
        HStack(spacing: DS.sp4) {
            Image(systemName: "list.number")
                .font(.imasScaled(28, weight: .semibold))
                .foregroundStyle(DS.sys)
                .frame(width: 52, height: 52)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text("セトリ当て")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("公演のセトリの空欄に入る曲を 4 択で当てよう")
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
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text("出題候補: \(estimate.showCount) 公演")
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("セトリが 6 曲以上ある公演から出します")
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
            Text("このブランドには出題できる公演がありません。ブランドの選択を増やしてください。")
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
            AppAnalytics.tap("setlist_quiz_setup.start")
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

    private func estimatePool() async {
        isEstimating = true
        defer { isEstimating = false }
        if let e = try? await AppContainer.shared.setlistQuizReading.poolEstimate(brandIds: Array(selectedBrandIds)) {
            estimate = e
        }
    }

    // MARK: - Helpers

    private func decodeBrandIds(_ raw: String) -> Set<String> {
        Set(quizBrandIdsDecode(raw: raw))
    }

    private func encodeBrandIds(_ ids: Set<String>) -> String {
        quizBrandIdsEncode(brandIds: Array(ids))
    }
}
