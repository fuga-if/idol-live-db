import SwiftUI

// =============================================================================
// 料金表 (docs/DESIGN_SYSTEM.md §6.7 電光掲示板と同じ配色)
//
// セトリ・公演詳細のチケット価格。`ImasBoard` と同じ暗い板に、
// 「種類 … ¥ 細長い数字」の行を縦に並べる。価格帯 (複数券種) は内訳行を薄く従える。
// 金額は imas-core が整形済みの文字列 (`formatYen` / `TicketPriceRange.label`) をそのまま置く。
// =============================================================================

/// 料金表。暗い板に券種と金額を並べる。
struct ImasPriceList: View {
    struct Row: Identifiable {
        let id: String
        /// 券種・名前 (「一般指定席」「ERISA」)。
        let label: String
        /// 金額。コアが整形済みの文字列 (「¥9,800」「¥5,500〜¥13,200」)。
        let amount: String
        /// 薄く添える注記 (「推定含む」)。
        var note: String? = nil
        /// 価格帯の内訳行 (少し下げて小さく出す)。
        var indented: Bool = false
        /// 長押しで「〈券種〉をコピー」を出す。
        var copyable: Bool = true
    }

    var title: String? = nil
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).imasText(.imprint, color: DS.boardDim)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                Rectangle().fill(DS.boardLine).frame(height: 1)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle().fill(DS.boardLine).frame(height: 1)
                        .padding(.leading, row.indented ? 28 : 14)
                }
                rowView(row)
            }
        }
        .background(DS.board, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(row.indented ? .imasFootnote : .imasSubhead.weight(.semibold))
                    .foregroundStyle(row.indented ? DS.boardDim : DS.boardInk)
                    .lineLimit(2)
                if let note = row.note {
                    Text(note).font(.imasCaption2).foregroundStyle(DS.boardDim)
                }
            }
            Spacer(minLength: DS.Space.gap)
            Text(row.amount)
                .font(row.indented ? ImasNumeralSize.small.font : ImasNumeralSize.medium.font)
                .foregroundStyle(DS.boardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.leading, row.indented ? 28 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, row.indented ? 10 : 12)
        .accessibilityElement(children: .combine)
        .imasCopyable(row.copyable ? [CopyItem("\(row.label)をコピー", row.amount, key: "labeled_row")] : [])
    }
}
