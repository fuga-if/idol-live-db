import SwiftUI

/// 自分の投稿累計の内訳ビュー。プロデュースタブ「投稿」タイル → ここに飛ぶ。
/// ローカル LocalContributionLog のカウントを内訳として並べる。
/// 上には、サーバから取った手応え (届いた Good・先週セトリが見られた数) を出す。
/// 個別履歴 (どのライブのセトリ編集か等) は将来の拡張 — 今は累計表示で割り切る。
struct MyContributionsView: View {
    @State private var log = LocalContributionLog.shared
    @State private var feedbackStore = ContributionFeedbackStore.shared

    var body: some View {
        ImasPage {
            ImasStatTile(systemImage: "square.and.pencil", value: "\(log.total)", unit: "件",
                         label: "コミュニティへの投稿累計")

            feedbackSections

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
        .task { await feedbackStore.refresh(force: true) }
        // 開いている間は NEW を見せたまま、閉じたときに既読にする。
        .onDisappear { feedbackStore.markGoodsSeen() }
    }

    /// 届いた Good と、先週セトリが見られた数。ログインしていて取れたときだけ。
    @ViewBuilder
    private var feedbackSections: some View {
        if let feedback = feedbackStore.feedback {
            if feedback.setlistReach.viewers > 0 {
                ImasSection("先週の反響", style: .small,
                            footer: "あなたが入れたセトリの公演ページを見た人の数です (公演ごとに 1 人 1 回)。") {
                    ImasStatGrid(columns: 2) {
                        ImasStatTile(systemImage: "eye.fill", value: "\(feedback.setlistReach.viewers)", unit: "人",
                                     label: "セトリを見た人")
                        ImasStatTile(systemImage: "music.note.list", value: "\(feedback.setlistReach.shows)", unit: "公演",
                                     label: "見られた公演")
                    }
                }
            }
            if !feedback.goods.isEmpty {
                let times = EditFeedFormat.relativeTimes(feedback.goods.map {
                    ($0.batchId, Date(timeIntervalSince1970: TimeInterval($0.latestGoodAt) / 1000))
                })
                ImasSection("届いた Good", style: .small) {
                    ImasCardList {
                        ForEach(Array(feedback.goods.enumerated()), id: \.element.id) { index, good in
                            if index > 0 { ImasRowDivider() }
                            ImasRecordRow(
                                leading: .icon(EditFeedFormat.recordTypeIcon(good.recordType ?? ""), tone: .themed,
                                               seed: good.recordType),
                                title: good.summary ?? EditFeedFormat.recordTypeLabel(good.recordType ?? ""),
                                subtitle: "Good \(good.goodCount) ・ \(times[good.batchId] ?? "")",
                                badges: good.newGoodCount > 0 ? [ImasBadgeSpec(text: "NEW +\(good.newGoodCount)", kind: .new)] : []
                            )
                        }
                    }
                }
            }
        }
    }
}
