import SwiftUI

/// メンバーカラー合わせ。出題対象ブランドをトグルで選び、難易度・問題数を決めて
/// 全N問のセッションを遊ぶ。各問は色チップをドラッグ&ドロップ(タップ割当も可)で紐づけ、
/// 判定で正誤＋正解色を表示。最後に正答率を出す。判定前は本人の色を見せない
/// (アバターは画像があれば画像・無ければ中立モノグラムで、色をネタバレしない)。
struct ColorMatchGameView: View {
    @Environment(AppDatabase.self) private var database
    @State private var imageService = CustomImageService.shared

    @State private var brandPools: [(brand: Brand, members: [Idol])] = []
    @State private var allColored: [Idol] = []

    // 設定
    @State private var selectedBrandIds: Set<String> = []
    /// 難度: 0=やさしい(色を散らす) / 1=ふつう(ランダム) / 2=むずい(最も近い色・人数増)
    @State private var difficulty = 1
    @State private var questionCount = 5
    private let levelLabels = ["やさしい", "ふつう", "むずい"]
    private let levelCounts = [4, 5, 6]
    private let questionCountOptions = [5, 10]

    // セッション状態
    @State private var scopePool: [Idol] = []
    @State private var inGame = false
    @State private var sessionDone = false
    @State private var roundIndex = 0          // 0-based
    @State private var totalCorrect = 0
    @State private var totalAnswered = 0

    // 1問の状態
    @State private var members: [Idol] = []
    @State private var palette: [String] = []
    @State private var assignments: [String: String] = [:]
    @State private var selectedHex: String?
    @State private var dropTargetId: String?
    @State private var judged = false
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                if isLoading {
                    ProgressView().tint(DS.sys).frame(maxWidth: .infinity).padding(.top, DS.sp9)
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 2), spacing: DS.sp3) {
                    ForEach(brandPools, id: \.brand.id) { pool in
                        brandToggle(pool)
                    }
                }
            }

            let canStart = effectivePool.count >= 2
            primaryButton("はじめる（全\(questionCount)問）") { AppAnalytics.tap("color_match_game.start"); startSession() }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.5)
        }
    }

    private func brandToggle(_ pool: (brand: Brand, members: [Idol])) -> some View {
        let on = selectedBrandIds.contains(pool.brand.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if on { selectedBrandIds.remove(pool.brand.id) } else { selectedBrandIds.insert(pool.brand.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.sp3) {
                HStack {
                    Text(pool.brand.shortName).font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                    Spacer(minLength: 0)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? DS.sys : DS.ink3)
                }
                HStack(spacing: 4) {
                    ForEach(Array(pool.members.prefix(6)), id: \.id) { m in
                        Circle().fill(Color(hexString: m.color)).frame(width: 11, height: 11)
                    }
                }
                Text("\(pool.members.count)人").font(.imasCaption).foregroundStyle(DS.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.sp4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                    .strokeBorder(on ? DS.sys : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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
            ForEach(palette, id: \.self) { hex in
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
            ForEach(Array(members.enumerated()), id: \.element.id) { idx, idol in
                if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                memberRow(idol)
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ idol: Idol) -> some View {
        let assigned = assignments[idol.id]
        let correct = judged && assigned != nil && sameColor(assigned!, idol.color)
        let slotRing: Color = judged ? (correct ? DS.success : DS.danger) : (dropTargetId == idol.id ? DS.ink : .white.opacity(0.4))
        HStack(spacing: DS.sp3) {
            // アイドル本人 (色はネタバレしないよう中立アバター: 画像があれば画像)
            ImasAvatar(label: idol.shortName, seed: nil, size: 44,
                       imageURL: imageService.imageURL(for: idol.id))

            VStack(alignment: .leading, spacing: 1) {
                Text(idol.name).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                if isCrossBrand, let b = brandShort(idol.brandId) {
                    Text(b).font(.imasCaption).foregroundStyle(DS.ink3)
                }
                if judged {
                    // 答え合わせでは本人のメンバーカラーを色見本 + HEX コードで明示する。
                    HStack(spacing: 5) {
                        Text(correct ? "メンバーカラー" : "正解").font(.imasCaption).foregroundStyle(DS.ink3)
                        Circle().fill(Color(hexString: idol.color)).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(DS.sep, lineWidth: 0.5))
                        Text(hexLabel(idol.color)).font(.imasDisplay(11, weight: .semibold)).foregroundStyle(DS.ink2)
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
        .padding(.horizontal, DS.sp5).padding(.vertical, 12)
        .background(dropTargetId == idol.id ? DS.fill : DS.surface)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard !judged, let hex = items.first else { return false }
            assign(hex, to: idol.id); return true
        } isTargeted: { hovering in
            dropTargetId = hovering ? idol.id : (dropTargetId == idol.id ? nil : dropTargetId)
        }
        .onTapGesture {
            guard !judged else { return }
            if assignments[idol.id] != nil { assignments[idol.id] = nil }
            else if let sel = selectedHex { assign(sel, to: idol.id); selectedHex = nil }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if judged {
            VStack(spacing: DS.sp3) {
                Text("\(scoreCount()) / \(members.count) 正解")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                primaryButton(roundIndex + 1 < questionCount ? "次へ（第\(roundIndex + 2)問）" : "結果を見る") {
                    advance()
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            let ready = assignments.count == members.count
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
        let rate = totalAnswered > 0 ? Int((Double(totalCorrect) / Double(totalAnswered) * 100).rounded()) : 0
        return VStack(spacing: DS.sp5) {
            Spacer().frame(height: DS.sp6)
            Image(systemName: rate >= 80 ? "trophy.fill" : "checkmark.seal.fill")
                .font(.imasScaled( 52, weight: .semibold))
                .foregroundStyle(rate >= 80 ? DS.favorite : DS.sys)
            Text("正答率 \(rate)%")
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

    /// 正規化したメンバーカラーで重複を除き、各色につき最初の 1 人だけ残す (色の無い人は除外)。
    private static func uniqueByColor<S: Sequence>(_ idols: S) -> [Idol] where S.Element == Idol {
        var seen = Set<String>(); var result: [Idol] = []
        for idol in idols {
            let hex = ColorMath.normalizedHex(idol.color ?? "") ?? ""
            if hex.isEmpty || seen.contains(hex) { continue }
            seen.insert(hex); result.append(idol)
        }
        return result
    }

    /// 選択ブランド → 出題母集団 (未選択は全ブランド)。色は一意。
    private var effectivePool: [Idol] {
        if selectedBrandIds.isEmpty { return allColored }
        let members = brandPools
            .filter { selectedBrandIds.contains($0.brand.id) }
            .flatMap { $0.members }
        return Self.uniqueByColor(members)
    }

    private var isCrossBrand: Bool { selectedBrandIds.count != 1 }

    private func brandShort(_ id: String) -> String? {
        brandPools.first { $0.brand.id == id }?.brand.shortName
    }

    private func startSession() {
        let pool = effectivePool
        guard pool.count >= 2 else { return }
        scopePool = pool
        roundIndex = 0; totalCorrect = 0; totalAnswered = 0
        sessionDone = false; inGame = true
        startRound()
    }

    private func resetToSetup() {
        inGame = false; sessionDone = false
    }

    private func judge() {
        judged = true
        totalCorrect += scoreCount()
        totalAnswered += members.count
    }

    private func advance() {
        if roundIndex + 1 < questionCount {
            roundIndex += 1
            startRound()
        } else {
            sessionDone = true
            GameProgressStore.shared.recordResult(.colorMatch, score: totalCorrect, outOf: totalAnswered)
        }
    }

    /// スコープから難度に応じてメンバーを選び1問出題する。
    private func startRound() {
        judged = false; assignments = [:]; selectedHex = nil; dropTargetId = nil
        let n = min(levelCounts[difficulty], scopePool.count)
        guard n >= 2, let anchor = scopePool.randomElement() else { members = []; palette = []; return }
        let rest = scopePool.filter { $0.id != anchor.id }
        var chosen: [Idol]
        switch difficulty {
        case 2: // むずい: アンカーに最も近い色
            chosen = [anchor] + rest.sorted { colorDistance(anchor.color, $0.color) < colorDistance(anchor.color, $1.color) }.prefix(n - 1)
        case 0: // やさしい: 互いになるべく離れた色 (farthest-point sampling)
            chosen = [anchor]
            var left = rest
            while chosen.count < n, !left.isEmpty {
                let best = left.max { minDistance($0, to: chosen) < minDistance($1, to: chosen) }!
                chosen.append(best); left.removeAll { $0.id == best.id }
            }
        default: // ふつう: ランダム混在
            chosen = [anchor] + rest.shuffled().prefix(n - 1)
        }
        members = chosen.shuffled()
        palette = members.map { $0.color ?? "" }.shuffled()
    }

    private func minDistance(_ idol: Idol, to set: [Idol]) -> Double {
        set.map { colorDistance(idol.color, $0.color) }.min() ?? .greatestFiniteMagnitude
    }

    private func assign(_ hex: String, to idolId: String) {
        for (k, v) in assignments where v == hex && k != idolId { assignments[k] = nil }
        assignments[idolId] = hex
        dropTargetId = nil
    }

    private func scoreCount() -> Int {
        members.filter { idol in assignments[idol.id].map { sameColor($0, idol.color) } ?? false }.count
    }

    private func sameColor(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return ColorMath.normalizedHex(a) == ColorMath.normalizedHex(b)
    }

    /// メンバーカラーを `#F5C900` 形式 (大文字 6 桁) で表示する文字列に整える。
    private func hexLabel(_ hex: String?) -> String {
        guard let h = hex, let norm = ColorMath.normalizedHex(h) else { return "—" }
        return "#" + norm.uppercased()
    }

    /// 知覚的な色距離 (redmean 近似)。小さいほど似ている。
    private func colorDistance(_ a: String?, _ b: String?) -> Double {
        guard let a, let b, ColorMath.normalizedHex(a) != nil, ColorMath.normalizedHex(b) != nil else { return .greatestFiniteMagnitude }
        let x = ColorMath.hexToRgb(a), y = ColorMath.hexToRgb(b)
        let rmean = (x.r + y.r) / 2
        let dr = x.r - y.r, dg = x.g - y.g, db = x.b - y.b
        return ((2 + rmean / 256) * dr * dr) + (4 * dg * dg) + ((2 + (255 - rmean) / 256) * db * db)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        let brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        let brandById = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0) })
        // 'other' (ラブライブ/.KR 等の非アイマス・コラボ枠) はメンバーカラー合わせから除外。
        let colored = all.filter { !$0.isExternal && $0.brandId != "other" && ($0.color?.isEmpty == false) }

        // 全体プール: 色が一意 (重複色は最初の1人だけ)
        allColored = Self.uniqueByColor(colored)

        var byBrand: [String: [Idol]] = [:]
        for idol in colored { byBrand[idol.brandId, default: []].append(idol) }
        brandPools = byBrand.compactMap { brandId, list in
            guard let brand = brandById[brandId] else { return nil }
            let uniq = Self.uniqueByColor(list.sorted { $0.sortOrder < $1.sortOrder })
            return uniq.count >= 4 ? (brand, uniq) : nil
        }
        .sorted { $0.brand.sortOrder < $1.brand.sortOrder }
    }
}
