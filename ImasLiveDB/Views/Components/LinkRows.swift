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

/// イベント名表示の統一行レイアウト。
///
/// `ImasEventRow` (半券の形) にすると、他画面の行の中に埋め込んで使う本行の用途
/// (メニュー・他実体の行の中の参照など) で形が壊れるため、帯 + 題 + 副題の簡潔な形のまま
/// DS トークンだけで揃える (スペーシングのみ手書きだったものをトークン化)。
struct EventNameRow: View {
    let event: Event
    var subtitle: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: DS.Space.rowGap) {
            BrandColorBar(brandId: event.brandId)
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(eventDisplayName(event.name)).imasText(.rowLabel).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).imasText(.meta)
                }
            }
            Spacer(minLength: DS.Space.gap)
            if showsChevron {
                ImasRowChevron()
            }
        }
        .contentShape(Rectangle())
        .imasCopyable(event.name, label: "ライブ名をコピー", key: "event_name")
    }
}
