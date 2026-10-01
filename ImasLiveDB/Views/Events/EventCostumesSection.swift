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
            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasSectionHeader(title: "衣装 ・ \(total) 着", tight: true)
                    .padding(.horizontal, DS.sp5)
                ImasCardList {
                    ForEach(Array(costumes.shared.enumerated()), id: \.element.costume.id) { index, entry in
                        if index > 0 { ImasRowDivider(inset: DS.sp5) }
                        costumeRow(entry, individual: false)
                    }
                    if !costumes.individual.isEmpty {
                        if !costumes.shared.isEmpty { ImasRowDivider(inset: DS.sp5) }
                        individualToggle
                        if individualExpanded {
                            ForEach(costumes.individual, id: \.costume.id) { entry in
                                ImasRowDivider(inset: DS.sp5)
                                costumeRow(entry, individual: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.sp5)
            }
        }
    }

    /// 個別衣装を畳んだ 1 行。押すと 1 人ずつの衣装が開く。
    private var individualToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { individualExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("個別衣装")
                    .font(.imasScaled(15, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Text("\(costumes.individual.count) 着")
                    .font(.imasScaled(13))
                    .foregroundStyle(DS.ink2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.imasScaled(12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                    .rotationEffect(.degrees(individualExpanded ? 180 : 0))
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("個別衣装 \(costumes.individual.count) 着")
        .accessibilityHint(individualExpanded ? "畳む" : "開く")
    }

    /// 衣装 1 着の行。個別衣装は「誰の衣装か」を名前の上に小さく出す
    /// (39 人ぶん並ぶので、人で探せるようにする)。
    private func costumeRow(_ entry: EventCostumeRecord, individual: Bool) -> some View {
        Button { onOpen(entry.costume) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if individual, let who = entry.costume.attribution {
                        Text(who)
                            .font(.imasScaled(12))
                            .foregroundStyle(DS.ink2)
                    }
                    HStack(spacing: 8) {
                        Text(entry.costume.name)
                            .font(.imasScaled(15, weight: individual ? .regular : .semibold))
                            .foregroundStyle(DS.ink)
                        if !individual, let attribution = entry.costume.attribution {
                            ImasTagChip(text: attribution, kind: .unit, seed: seed, brand: brand)
                        }
                    }
                }
                Spacer(minLength: 8)
                if let worn = entry.wornInLabel {
                    Text(worn)
                        .font(.imasScaled(12))
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.imasScaled(12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
