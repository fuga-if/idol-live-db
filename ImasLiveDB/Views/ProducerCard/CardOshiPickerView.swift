import SwiftUI

/// アプリの担当から、名刺に載せる担当を選ぶ画面 (P名刺の編集から push で開く)。保存先は呼び出し側に任せる
/// (`onChange` に idol id の並びを渡す。nil はおまかせに戻した)。
///
/// 上は名刺に載せる担当 (選んだ順。引いて並べ替え、左に引くと外す)、下はアプリの担当すべて (押すと載せる / 外す)。
/// 1 人だけ選べば名刺の担当はその 1 人になる (「担当を大きく」は 1 人の大きな画像、他のデザインは判子 1 つ)。
/// 上限・まだ選んでいないときの既定 (ブランドごとに 1 人)・担当から外れた人を抜く・最後の 1 人を外さないのはコア
/// (`producerCardOshiPicks` / `producerCardOshiToggle` / `producerCardOshiNormalize`)。
struct CardOshiPickerView: View {
    /// 担当の名前とブランド (アプリの並び)。
    let oshi: [CardOshiEntry]
    /// 担当のアイドル (行に写真か判子を出す)。
    let idols: [String: Idol]
    let brands: [String: Brand]
    /// 選び直したとき (idol id、載せる順。nil はおまかせ)。
    let onChange: ([String]?) -> Void

    @State private var current: [String]?

    init(chosen: [String]?, oshi: [CardOshiEntry], idols: [String: Idol], brands: [String: Brand],
         onChange: @escaping ([String]?) -> Void) {
        self.oshi = oshi
        self.idols = idols
        self.brands = brands
        self.onChange = onChange
        _current = State(initialValue: chosen)
    }

    var body: some View {
        Group {
            if oshi.isEmpty {
                ImasPage {
                    ImasCard {
                        ImasEmptyState(
                            systemImage: "heart",
                            title: "担当がいません",
                            message: "アイドル詳細で「担当」を付けると、ここから名刺に載せる担当を選べます。"
                        )
                    }
                }
            } else {
                list(producerCardOshiPicks(chosen: current, oshi: oshi))
            }
        }
        .navigationTitle("名刺に載せる担当")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("card_oshi_picker")
    }

    private func list(_ picks: CardOshiPicks) -> some View {
        let pickedIds = Set(picks.picked.map(\.idolId))
        return List {
            ImasListSection("名刺に載せる担当", count: "\(picks.picked.count) / \(picks.max)",
                            footer: picks.chosenByHand
                                ? "載せる順に並びます。引いて並べ替え、左に引くと外します (1 人は残します)。"
                                : "まだ選んでいないので、ブランドごとに 1 人ずつ載せています。選ぶとその人だけ・その順になります。") {
                ForEach(picks.picked, id: \.idolId) { entry in
                    row(entry)
                        .imasSwipe(trailing: picks.single ? [] : [
                            ImasSwipeAction(.delete, title: "外す") { toggle(entry.idolId) },
                        ])
                }
                .onMove { from, to in
                    var ids = picks.picked.map(\.idolId)
                    ids.move(fromOffsets: from, toOffset: to)
                    // 同じ位置で離しただけなら選んだことにしない (おまかせのままにする)。
                    guard ids != picks.picked.map(\.idolId) else { return }
                    set(producerCardOshiNormalize(ids: ids, oshi: oshi))
                }
                if picks.chosenByHand {
                    Button { reset() } label: {
                        Label("おまかせに戻す", systemImage: "arrow.uturn.backward")
                            .imasText(.rowLabel, color: DS.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            ImasListSection("アプリの担当", count: "\(picks.oshi.count)人",
                            footer: picks.full ? "名刺に載せられるのは \(picks.max) 人までです。足すときは先にどれかを外してください。" : nil) {
                ForEach(picks.oshi, id: \.idolId) { entry in
                    let isPicked = pickedIds.contains(entry.idolId)
                    let locked = (picks.full && !isPicked) || (picks.single && isPicked)
                    // 行は Button で包まない (包むと行の余白の指定が List に届かず、上の区画の行とずれる)。
                    row(entry, trailing: .custom(AnyView(ImasSelectionMark(isSelected: isPicked))))
                        .contentShape(Rectangle())
                        .onTapGesture { if !locked { toggle(entry.idolId) } }
                        .opacity(locked && !isPicked ? 0.45 : 1)
                        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .imasForm()
    }

    @ViewBuilder
    private func row(_ entry: CardOshiEntry, trailing: ImasRowTrailing = .none) -> some View {
        if let idol = idols[entry.idolId] {
            ImasIdolRow(idol: idol, subtitle: entry.brandLabel.isEmpty ? nil : entry.brandLabel,
                        brand: brands[idol.brandId]?.color, isPick: true, trailing: trailing, density: .compact)
        }
    }

    private func toggle(_ id: String) {
        AppAnalytics.tap("card_oshi_picker.toggle")
        set(producerCardOshiToggle(chosen: current, oshi: oshi, idolId: id))
    }

    private func reset() {
        AppAnalytics.tap("card_oshi_picker.reset")
        current = nil
        onChange(nil)
    }

    private func set(_ ids: [String]) {
        guard ids != current else { return }
        current = ids
        onChange(ids)
    }
}
