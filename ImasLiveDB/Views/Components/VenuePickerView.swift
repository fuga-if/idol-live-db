import SwiftUI

/// 会場を 1 つ選ぶピッカー。
///
/// 会場は **ID で選ぶ**。名前で持つと改名 (武蔵野の森総合スポーツプラザ →
/// 京王アリーナTOKYO) や表記揺れで絞り込みが外れてしまうため。
/// 検索は現行名に加えて **旧名・別名** も対象にするので、「武蔵野の森」でも
/// 「京王アリーナ」でも同じ会場に辿り着ける。
struct VenuePickerView: View {
    let directory: VenueDirectory
    /// 選択中の venue_id。nil = 未選択。
    @Binding var selected: String?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// 都道府県ごとにまとめる。会場は 245 件あるので、地域で塊にしないと探せない。
    /// 都道府県が未確定の会場 (海外・非公開) は末尾の「その他」に寄せる。
    private var grouped: [(area: String, venues: [Venue])] {
        let filtered = filteredVenues
        var byArea: [String: [Venue]] = [:]
        for v in filtered {
            byArea[v.prefecture ?? "その他", default: []].append(v)
        }
        return byArea
            .map { (area: $0.key, venues: $0.value) }
            .sorted { lhs, rhs in
                if lhs.area == "その他" { return false }
                if rhs.area == "その他" { return true }
                // 公演数の多い地域を上に (sort_order は公演数順で振ってある)
                let l = lhs.venues.map(\.sortOrder).min() ?? 0
                let r = rhs.venues.map(\.sortOrder).min() ?? 0
                return l < r
            }
    }

    /// 絞り込み用の索引。会場一覧は開いている間変わらないので 1 回だけ組む。
    ///
    /// 綴りは現行名・**読み**・都道府県・別名 (旧名/通称)。
    /// 以前は `localizedCaseInsensitiveContains` を並べていて、`venues.name_kana` を
    /// 持っているのに読みで引けなかった (「ぶどうかん」で日本武道館が出ない)。
    /// 照合規則はコア (`domain/text_search_index.rs`) に一任する。
    @State private var catalog: TextSearchCatalog?

    private func makeCatalog() -> TextSearchCatalog {
        TextSearchCatalog(fieldsPerItem: directory.venues.map { v in
            // 旧名でも引けるようにする (「武蔵野の森」→ 京王アリーナTOKYO)
            [v.name, v.nameKana, v.prefecture] + v.aliasList
        })
    }

    private var filteredVenues: [Venue] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return directory.venues }
        // 索引が無い間は絞り込まない (黙って 0 件にする方が悪い)。
        guard let catalog else { return directory.venues }
        return catalog.filter(directory.venues, needle: q)
    }

    var body: some View {
        List {
            Section {
                row(label: "選択なし", venue: nil, muted: true)
            }

            if filteredVenues.isEmpty {
                ImasEmptyState(
                    systemImage: "magnifyingglass",
                    title: "見つかりません",
                    message: "「\(searchText)」に一致する会場がありません"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(grouped, id: \.area) { group in
                    Section(group.area) {
                        ForEach(group.venues) { venue in
                            row(label: venue.name, venue: venue, muted: false)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .searchable(text: $searchText, prompt: "会場名・旧名・地域で検索")
        .navigationTitle("会場")
        .navigationBarTitleDisplayMode(.inline)
        .task { catalog = makeCatalog() }
    }

    @ViewBuilder
    private func row(label: String, venue: Venue?, muted: Bool) -> some View {
        let id = venue?.id
        Button {
            selected = id
            dismiss()
        } label: {
            HStack(spacing: DS.sp3) {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(label)
                        .font(.imasSubhead)
                        .foregroundStyle(muted ? DS.ink2 : DS.ink)
                        .lineLimit(2)
                    if let venue, let sub = subtitle(for: venue) {
                        Text(sub)
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.sp3)
                if selected == id {
                    Image(systemName: "checkmark")
                        .font(.imasScaled(14, weight: .semibold))
                        .foregroundStyle(DS.sys)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
        .accessibilityAddTraits(selected == id ? .isSelected : [])
    }

    /// キャパと旧名を副題に出す。キャパは出典が取れた会場だけ入っているので nil もある。
    private func subtitle(for venue: Venue) -> String? {
        var parts: [String] = []
        if let cap = venue.capacityLabel { parts.append(cap) }
        if let former = venue.aliasList.first { parts.append("旧: \(former)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }
}
