import SwiftUI

/// セトリ行の歌唱者の一覧シート (読むだけのシート)。
///
/// 頭に印字 (`SINGERS · 3 名`) と曲名、その下に刷られた紙 (`ImasCardList(.sheet)`、行の間は切り取り線) に
/// 1 人ずつ並べる。地はシートの下を透かさない紙面 (`ImasPage`)。
/// 以前は OS の `List` に素の行を並べていて、行が間延びし、下のセトリが透けていた。
struct PerformerDetailSheet: View {
    let songTitle: String
    /// 並べる歌唱者。**アイドルと表示名を 1 組で受け取る。**
    /// 以前は `[Idol]` と `[PerformerRow]` を別々に受け取り、シート側が id で
    /// 突き合わせ直していた (2 本が食い違い得る不変条件を人が守る必要があり、
    /// 人数分の線形探索も走っていた)。組むのは呼び出し側の仕事。
    let performers: [ResolvedPerformer]
    /// idol_id → その人の札 (`オリメン` / `初歌唱`)。付けるか・言葉・強さは imas-core
    /// (`SetlistRowMetaRecord.performerNotes`)。札の無い人は入っていない。
    var notesByIdolId: [String: [SetlistRowNoteRecord]] = [:]
    let navigate: (DetailDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var imageService = CustomImageService.shared

    var body: some View {
        NavigationStack {
            ImasPage {
                header
                ImasCardList(performers, style: .sheet) { performer in
                    row(performer)
                }
            }
            .navigationTitle("歌唱者")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(DS.paper)
        .trackScreen("performer_detail")
    }

    /// 頭: 印字 (何の一覧か・何人か) と曲名。
    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            ImasMasthead("SINGERS", "\(performers.count) 名")
            Text(songTitle)
                .imasText(.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ performer: ResolvedPerformer) -> some View {
        Button {
            AppAnalytics.tap("performer_detail.select_idol")
            navigate(.idol(performer.idol))
        } label: {
            // 題は idol.name 固定の `ImasIdolRow` ではなくここで組む。
            // 歌唱者の表示名設定 (CV 名優先など) で主/副が入れ替わるため、
            // 解決済みの `performer.name` をそのまま使う必要がある。
            ImasRow(
                title: performer.name.primary,
                subtitle: performer.name.secondary,
                leading: .avatar(label: performer.idol.shortName, seed: performer.idol.color,
                                imageURL: imageService.imageURL(for: performer.idol.id)),
                trailing: .chevron,
                density: .compact,
                titleLineLimit: 1
            ) {
                if let notes = notesByIdolId[performer.idol.id], !notes.isEmpty {
                    ImasNoteBadges(notes: notes)
                }
            }
        }
        .buttonStyle(.imasRow)
    }
}
