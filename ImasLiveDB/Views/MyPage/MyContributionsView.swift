import SwiftUI

/// 自分の投稿累計の内訳ビュー。プロデュースタブ「投稿」タイル → ここに飛ぶ。
/// ローカル LocalContributionLog のカウントを内訳として並べる。
/// 個別履歴 (どのライブのセトリ編集か等) は将来の拡張 — 今は累計表示で割り切る。
struct MyContributionsView: View {
    @State private var log = LocalContributionLog.shared

    var body: some View {
        ImasPage {
            ImasStatTile(systemImage: "square.and.pencil", value: "\(log.total)", unit: "件",
                         label: "コミュニティへの投稿累計")

            ImasSection("内訳", style: .small) {
                ImasStatGrid(columns: 2) {
                    ForEach(LocalContributionLog.Kind.allCases, id: \.rawValue) { kind in
                        ImasStatTile(systemImage: kind.systemImage, value: "\(log.count(of: kind))",
                                     unit: "件", label: kind.label)
                    }
                }
            }

            // セトリ編集・動画追加・タグ追加等、サーバに記録される「編集」の履歴確認・取り消し導線。
            // 投稿履歴(このビュー)と近い機能のため、内訳の直下にリンクとして置く。
            NavigationLink {
                MyEditsView()
            } label: {
                ImasEntryCard(systemImage: "arrow.uturn.backward.circle",
                              title: "自分の編集を確認・取り消す",
                              preview: "ライブ・楽曲・セトリの編集履歴")
            }
            .buttonStyle(.plain)

            ImasNote("セトリ編集・動画追加・タグ追加が累計に含まれます。再インストールするとカウントはリセットされます (端末ローカル記録)。")
        }
        .navigationTitle("マイ投稿")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("my_contributions")
    }
}
