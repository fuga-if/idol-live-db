import SwiftUI

/// アイドル名表示の統一行レイアウト。見た目は DS の `ImasIdolRow`。
struct IdolNameRow: View {
    let idol: Idol
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        ImasIdolRow(idol: idol, subtitle: subtitle, trailing: showsChevron ? .chevron : .none, density: .compact)
    }
}

/// 楽曲タイトル表示の統一行レイアウト。見た目は DS の `ImasSongRow`。
struct SongTitleRow: View {
    let song: Song
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        ImasSongRow(song: song, subtitle: subtitle, trailing: showsChevron ? .chevron : .none, density: .compact)
    }
}

/// ユニット名表示の統一行レイアウト。見た目は DS の `ImasUnitRow`。
struct UnitNameRow: View {
    let unit: Unit
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        ImasUnitRow(unit: unit, subtitle: subtitle, trailing: showsChevron ? .chevron : .none, density: .compact)
    }
}

