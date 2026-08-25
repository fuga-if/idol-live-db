import SwiftUI

/// メンバーカラー合わせ。出題対象ブランドをトグルで選び、難易度・問題数を決めて
/// 全N問のセッションを遊ぶ。各問は色チップをドラッグ&ドロップ(タップ割当も可)で紐づけ、
/// 判定で正誤＋正解色を表示。最後に正答率を出す。判定前は本人の色を見せない
/// (アバターは画像があれば画像・無ければ中立モノグラムで、色をネタバレしない)。
///
/// 出題母集団の決定 (外部演者・コラボ枠・色未設定の除外、色の一意化、ブランド 4 人閾値)、
/// 難易度ごとの出題の作り方、答え合わせ、正答率は imas-core の `domain/color_match.rs` にあり、
/// Android と同じ実装を共有する。この画面が担うのは描画・ドラッグ操作・シード調達だけ。
struct ColorMatchGameView: View {
    @Environment(AppDatabase.self) private var database
    @State private var imageService = CustomImageService.shared

    /// 画面ロード時に 1 回だけ組む母集団一式 (コア)。
    @State private var pools = ColorMatchPools(allColored: [], brandPools: [], selectableBrandIds: [])
    /// 名前・ニックネーム等の表示情報を引くための対応表 (コアは id と色しか返さない)。
    @State private var idolById: [String: Idol] = [:]
    @State private var brands: [Brand] = []

    // 設定
    @State private var selectedBrandIds: Set<String> = []
    /// 難度: 0=やさしい(色を散らす) / 1=ふつう(ランダム) / 2=むずい(最も近い色・人数増)。
    /// セグメントの index はコアの `ColorMatchDifficulty` の並びにそのまま対応する。
    @State private var difficulty = 1
    @State private var questionCount = 5
    private let levelLabels = ["やさしい", "ふつう", "むずい"]
    private let questionCountOptions = [5, 10]
    /// 「合わせる」が成立する最低人数。コアの `MIN_POOL_SIZE` (=2) と同値だが、
    /// 開始ボタンを塞ぐ判定は呼び出し側の責務なので定数だけここに置く。
    private let minimumPool = 2

    // セッション状態
    /// 選択ブランドから引いた出題母集団 (ブランドを切り替えた時だけ引き直す)。
    @State private var pool: [ColorMatchIdol] = []
    /// 1 ゲーム分の出題 (「はじめる」1 回でコアがまとめて生成)。
    @State private var rounds: [ColorMatchRound] = []
    @State private var inGame = false
    @State private var sessionDone = false
    @State private var roundIndex = 0          // 0-based
    @State private var totalCorrect = 0
    @State private var totalAnswered = 0
    @State private var accuracyPercent = 0

    // 1問の状態
    @State private var assignments: [String: String] = [:]
    @State private var selectedHex: String?
    @State private var dropTargetId: String?
    /// 答え合わせの結果 (nil = まだ判定していない)。行の正誤・正解色の表示文字列も含む。
    @State private var judgement: ColorMatchJudgement?
    @State private var isLoading = true

    /// 現在の問題 (出題メンバーと色チップの並び)。
    private var round: ColorMatchRound {
        rounds.indices.contains(roundIndex) ? rounds[roundIndex] : ColorMatchRound(members: [], palette: [])
    }

    private var judged: Bool { judgement != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                if isLoading {
                    ImasInlineLoading(tint: DS.sys)
                } else if sessionDone {
                    resultView
                } else if !inGame {
                    setup
                } else {
                    instruction
                    paletteRow
                    memberList
                    footer
                }
            }
            .padding(DS.sp5)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("メンバーカラー合わせ")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // 母集団の引き直しはブランドを切り替えたときだけ (描画のたびには呼ばない)。
        .onChange(of: selectedBrandIds) { _, _ in refreshPool() }
        .trackScreen("color_match_game")
    }

    // MARK: - 設定画面

    private var setup: some View {
        VStack(alignment: .leading, spacing: DS.sp5) {
            Text("出題ブランドを選んで、似た色のメンバーの色を当てよう。")
                .font(.imasFootnote).foregroundStyle(DS.ink2)

            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasSectionHeader(title: "難易度", tight: true)
                ImasSegmented(labels: levelLabels, selection: $difficulty)
            }

            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasSectionHeader(title: "問題数", tight: true)
                ImasSegmented(labels: questionCountOptions.map { "\($0)問" },
                              selection: Binding(
                                get: { questionCountOptions.firstIndex(of: questionCount) ?? 0 },
                                set: { questionCount = questionCountOptions[$0] }))
            }

            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "出題ブランド", tight: true)
                Text("未選択なら全ブランドから出題")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                brandGrid
            }

            let canStart = pool.count >= minimumPool
            primaryButton("はじめる（全\(questionCount)問）") { AppAnalytics.tap("color_match_game.start"); startSession() }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.5)
        }
    }

    /// 他のクイズ (アイドル当て・ソロ曲) と共通の BrandIconCell 丸アイコングリッド。
    /// メンバーカラーチップを並べるとそれ自体が問題のヒント(版権キャラの色)になり得るため、
    /// 共通UIに揃えてヒント漏れも防ぐ。
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

    // MARK: - ゲーム

    private var instruction: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(judged ? "答え合わせ" : "色をドラッグ、またはタップで割当")
                    .font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                Text("第\(roundIndex + 1)問 / 全\(questionCount)問 ・ \(levelLabels[difficulty])")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            Spacer()
            Button { resetToSetup() } label: {
                Text("やめる").font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink2)
            }.buttonStyle(.plain)
        }
    }

    private var paletteRow: some View {
        FlowLayout(spacing: DS.sp3) {
            ForEach(round.palette, id: \.self) { hex in
                let used = assignments.values.contains(hex)
                Circle()
                    .fill(Color(hexString: hex))
                    .frame(width: 46, height: 46)
                    .overlay(Circle().strokeBorder(selectedHex == hex ? DS.ink : .white.opacity(0.5),
                                                   lineWidth: selectedHex == hex ? 3 : 1))
                    .overlay(used ? Image(systemName: "checkmark").font(.imasScaled( 14, weight: .bold)).foregroundStyle(.white) : nil)
                    .opacity(used ? 0.4 : 1)
                    .draggable(hex) { Circle().fill(Color(hexString: hex)).frame(width: 46, height: 46) }
                    .onTapGesture {
                        guard !judged else { return }
                        selectedHex = (selectedHex == hex) ? nil : hex
                    }
            }
        }
    }

    private var memberList: some View {
        ImasListContainer {
            ForEach(Array(round.members.enumerated()), id: \.element.id) { idx, member in
                if idx > 0 { ImasRowDivider(inset: DS.sp5) }
                memberRow(member, at: idx)
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: ColorMatchIdol, at position: Int) -> some View {
        let idol = idolById[member.id]
        let assigned = assignments[member.id]
        // 行の正誤はコアの答え合わせ結果をそのまま使う (画面側で色を比べ直さない)。
        let correct = judgement.map { $0.correct.indices.contains(position) && $0.correct[position] } ?? false
        let slotRing: Color = judged ? (correct ? DS.success : DS.danger) : (dropTargetId == member.id ? DS.ink : .white.opacity(0.4))
        HStack(spacing: DS.sp3) {
            // アイドル本人 (色はネタバレしないよう中立アバター: 画像があれば画像)
            ImasAvatar(label: idol?.shortName ?? "", seed: nil, size: 44,
                       imageURL: imageService.imageURL(for: member.id))

            VStack(alignment: .leading, spacing: 1) {
                Text(idol?.name ?? "").font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                if isCrossBrand, let b = idol.flatMap({ brandShort($0.brandId) }) {
                    Text(b).font(.imasCaption).foregroundStyle(DS.ink3)
                }
                if let judgement, judgement.correctHexLabels.indices.contains(position) {
                    // 答え合わせでは本人のメンバーカラーを色見本 + HEX コードで明示する。
                    HStack(spacing: 5) {
                        Text(correct ? "メンバーカラー" : "正解").font(.imasCaption).foregroundStyle(DS.ink3)
                        Circle().fill(Color(hexString: member.color)).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(DS.sep, lineWidth: 0.5))
                        Text(judgement.correctHexLabels[position]).font(.imasDisplay(11, weight: .semibold)).foregroundStyle(DS.ink2)
                    }
                }
            }
            Spacer(minLength: 0)

            // 割り当てた色スロット (ドロップ/タップ対象)
            ZStack {
                Circle().fill(assigned.map { Color(hexString: $0) } ?? DS.fill).frame(width: 40, height: 40)
                if assigned == nil && !judged {
                    Image(systemName: "questionmark").font(.imasScaled( 14, weight: .bold)).foregroundStyle(DS.ink3)
                }
            }
            .overlay(Circle().strokeBorder(slotRing, lineWidth: 2.5))
            if judged {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(correct ? DS.success : DS.danger)
            }
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, DS.sp4)
        .background(dropTargetId == member.id ? DS.fill : DS.surface)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard !judged, let hex = items.first else { return false }
            assign(hex, to: member.id); return true
        } isTargeted: { hovering in
            dropTargetId = hovering ? member.id : (dropTargetId == member.id ? nil : dropTargetId)
        }
        .onTapGesture {
            guard !judged else { return }
            if assignments[member.id] != nil { assignments[member.id] = nil }
            else if let sel = selectedHex { assign(sel, to: member.id); selectedHex = nil }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let judgement {
            VStack(spacing: DS.sp3) {
                Text("\(judgement.score) / \(judgement.outOf) 正解")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                primaryButton(roundIndex + 1 < questionCount ? "次へ（第\(roundIndex + 2)問）" : "結果を見る") {
                    advance()
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            let ready = assignments.count == round.members.count
            Button { AppAnalytics.tap("color_match_game.judge"); judge() } label: {
                Text("判定する")
                    .font(.imasHeadline.weight(.semibold))
                    .foregroundStyle(ready ? DS.onSys : DS.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(ready ? AnyShapeStyle(DS.sys) : AnyShapeStyle(DS.fill),
                                in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
        }
    }

    // MARK: - 結果

    private var resultView: some View {
        VStack(spacing: DS.sp5) {
            Spacer().frame(height: DS.sp6)
            Image(systemName: accuracyPercent >= 80 ? "trophy.fill" : "checkmark.seal.fill")
                .font(.imasScaled( 52, weight: .semibold))
                .foregroundStyle(accuracyPercent >= 80 ? DS.favorite : DS.sys)
            Text("正答率 \(accuracyPercent)%")
                .font(.imasDisplay(34, weight: .bold)).foregroundStyle(DS.ink)
            Text("\(totalCorrect) / \(totalAnswered) 正解（全\(questionCount)問）")
                .font(.imasSubhead).foregroundStyle(DS.ink2)

            VStack(spacing: DS.sp3) {
                primaryButton("もう一度") { startSession() }
                Button { resetToSetup() } label: {
                    Text("設定を変える").font(.imasHeadline.weight(.semibold)).foregroundStyle(DS.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.top, DS.sp4)
        }
        .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.imasHeadline.weight(.semibold)).foregroundStyle(DS.onSys)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(DS.sys, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: - Logic

    /// セグメントの index → コアの難易度 (並びは `ColorMatchDifficulty` と同順)。
    private var coreDifficulty: ColorMatchDifficulty {
        switch difficulty {
        case 0:  return .easy
        case 2:  return .hard
        default: return .normal
        }
    }

    /// ブランドが複数混ざるときだけ行にブランド名を添える (誰の色か絞りにくくなるため)。
    private var isCrossBrand: Bool { selectedBrandIds.count != 1 }

    private func brandShort(_ id: String) -> String? {
        // 出題母集団に載っているブランド (メンバー 4 人以上) だけ名前を添える。
        // 一覧に出るだけのブランドまで名乗らせない原本の挙動を保つ。
        guard pools.brandPools.contains(where: { $0.brandId == id }) else { return nil }
        return brands.first { $0.id == id }?.shortName
    }

    /// 選択ブランド → 出題母集団 (未選択は全ブランド)。色の一意化はコア側。
    private func refreshPool() {
        pool = colorMatchEffectivePool(pools: pools, selectedBrandIds: Array(selectedBrandIds))
    }

    /// 「はじめる」1 回で全問まとめて生成する (問題ごとに FFI を呼ばない)。
    private func startSession() {
        guard pool.count >= minimumPool else { return }
        var generator = SystemRandomNumberGenerator()
        rounds = colorMatchStartGame(pool: pool, difficulty: coreDifficulty,
                                     questionCount: UInt32(clamping: questionCount),
                                     seed: generator.next())
        roundIndex = 0; totalCorrect = 0; totalAnswered = 0; accuracyPercent = 0
        sessionDone = false; inGame = true
        startRound()
    }

    private func resetToSetup() {
        inGame = false; sessionDone = false
    }

    /// 1 問の答え合わせ。行の正誤・正解数・正解色の表示文字列はコアが一括で返す。
    private func judge() {
        let result = colorMatchJudgeRound(
            members: round.members,
            assignments: assignments.map { ColorMatchAssignment(idolId: $0.key, hex: $0.value) })
        judgement = result
        totalCorrect += Int(result.score)
        totalAnswered += Int(result.outOf)
    }

    private func advance() {
        if roundIndex + 1 < questionCount {
            roundIndex += 1
            startRound()
        } else {
            accuracyPercent = Int(colorMatchAccuracyPercent(totalCorrect: UInt32(clamping: totalCorrect),
                                                            totalAnswered: UInt32(clamping: totalAnswered)))
            sessionDone = true
            GameProgressStore.shared.recordResult(.colorMatch, score: totalCorrect, outOf: totalAnswered)
        }
    }

    /// 1 問ぶんの解答状態を戻す (出題自体は `startSession` で生成済み)。
    private func startRound() {
        judgement = nil; assignments = [:]; selectedHex = nil; dropTargetId = nil
    }

    private func assign(_ hex: String, to idolId: String) {
        for (k, v) in assignments where v == hex && k != idolId { assignments[k] = nil }
        assignments[idolId] = hex
        dropTargetId = nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        let allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        idolById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 除外 ('other' やコラボ枠・外部演者・色未設定)、色の一意化、ブランドごとの
        // 出題可否 (4 人以上) はコアがまとめて判断する。
        pools = colorMatchBuildPools(
            idols: all.map {
                ColorMatchIdolSource(id: $0.id, brandId: $0.brandId, color: $0.color,
                                     isExternal: $0.isExternal, sortOrder: Int32(clamping: $0.sortOrder))
            },
            brands: allBrands.map { ColorMatchBrandRef(id: $0.id, sortOrder: Int32(clamping: $0.sortOrder)) })
        // 出題ブランド選択に並べるのはコアが選抜したブランド ('other' 等は出さない)。
        let selectable = Set(pools.selectableBrandIds)
        brands = allBrands.filter { selectable.contains($0.id) }
        refreshPool()
    }
}
