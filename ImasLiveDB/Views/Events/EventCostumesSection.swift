import SwiftUI

/// イベント詳細「情報」タブの衣装セクション。
///
/// **行は衣装単位。** 着た公演は `DAY1・DAY2` の短い 1 行で添え、行を押すと
/// イベントをまたいだ着用公演の一覧 (`CostumeShowsView`) へ進む。
/// 説明文や出典は出さない (名前と「誰の衣装か」だけで見分ける)。
///
/// 共通・個別の分け方と「どの公演で着たか」の 1 行は imas-core が決めている。
/// 個別衣装は数十着になるので 1 行に畳み、開いたときだけ並べる。
struct EventCostumesSection: View {
    let costumes: EventCostumesRecord
    var seed: String? = nil
    var brand: String? = nil
    let onOpen: (CostumeRecord) -> Void

    @State private var individualExpanded = false

    private var total: Int { costumes.shared.count + costumes.individual.count }

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                ImasSectionHeader("衣装", count: "\(total) 着", style: .small)
                    .padding(.horizontal, DS.Space.screen)
                ImasCardList {
                    ForEach(Array(costumes.shared.enumerated()), id: \.element.costume.id) { index, entry in
                        if index > 0 { ImasRowDivider(inset: DS.Space.screen) }
                        costumeRow(entry, individual: false)
                    }
                    if !costumes.individual.isEmpty {
                        if !costumes.shared.isEmpty { ImasRowDivider(inset: DS.Space.screen) }
                        ImasDisclosureRow(title: "個別衣装", count: "\(costumes.individual.count) 着",
                                         isExpanded: $individualExpanded)
                        if individualExpanded {
                            ForEach(costumes.individual, id: \.costume.id) { entry in
                                ImasRowDivider(inset: DS.Space.screen)
                                costumeRow(entry, individual: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screen)
            }
        }
    }

    /// 衣装 1 着の行。個別衣装は「誰の衣装か」を副題に出す
    /// (39 人ぶん並ぶので、人で探せるようにする)。
    private func costumeRow(_ entry: EventCostumeRecord, individual: Bool) -> some View {
        Button { onOpen(entry.costume) } label: {
            ImasRow(
                title: entry.costume.name,
                subtitle: individual ? entry.costume.attribution : nil,
                trailing: .custom(AnyView(
                    HStack(spacing: DS.Space.gap) {
                        if let worn = entry.wornInLabel {
                            Text(worn).imasText(.meta).lineLimit(1)
                        }
                        ImasRowChevron()
                    }
                )),
                density: .compact,
                titleRole: .rowLabel
            ) {
                if !individual, let attribution = entry.costume.attribution {
                    ImasBadge(text: attribution, kind: .unit, seed: seed, brand: brand)
                }
            }
        }
        .buttonStyle(.imasRow)
    }
}
