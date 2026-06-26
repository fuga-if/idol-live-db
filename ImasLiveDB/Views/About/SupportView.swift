import SwiftUI

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    private let githubIssueURL = URL(string: "https://github.com/fuga-if/imas-live-privacy/issues/new")!

    var body: some View {
        List {
            Section("フィードバック・バグ報告") {
                Button {
                    AppAnalytics.tap("support.github_issue")
                    openURL(githubIssueURL)
                } label: {
                    Label("GitHub Issue で報告する", systemImage: "arrow.up.right.square")
                }
            }

            Section("よくある質問") {
                faqItem(
                    question: "データが古い・間違っている",
                    answer: "GitHub Issue または コミュニティ機能の「修正提案」からご報告ください。確認後に反映します。"
                )

                faqItem(
                    question: "ジャケット画像が表示されない",
                    answer: "Apple Music のデータベースに登録されていない楽曲は画像が表示されません。また、MusicKit の利用には Apple Music サブスクリプションまたは無料トライアルが必要な場合があります。"
                )

                faqItem(
                    question: "CloudKit 同期に失敗する",
                    answer: "iCloud にサインインしているか、設定 > Apple ID > iCloud で「ImasLiveDB」が有効になっているかご確認ください。"
                )

                faqItem(
                    question: "セットリストスキャナーが認識しない",
                    answer: "設定 > プライバシーとセキュリティ > 音声認識・カメラ で本アプリへのアクセスを許可してください。"
                )

                faqItem(
                    question: "アプリが公式アプリではないのですか?",
                    answer: "はい、本アプリは非公式のファンメイドアプリです。バンダイナムコエンターテインメント等とは一切関係ありません。"
                )
            }
        }
        .navigationTitle("サポート")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("support")
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Q. \(question)")
                .font(.imasSubhead)
                .fontWeight(.semibold)
            Text("A. \(answer)")
                .font(.imasSubhead)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
