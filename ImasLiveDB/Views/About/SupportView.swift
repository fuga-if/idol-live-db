import SwiftUI

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    private let githubIssueURL = URL(string: "https://github.com/fuga-if/imas-live-privacy/issues/new")!

    private let faqs: [(q: String, a: String)] = [
        ("データが古い・間違っている",
         "GitHub Issue または コミュニティ機能の「修正提案」からご報告ください。確認後に反映します。"),
        ("ジャケット画像が表示されない",
         "Apple Music のデータベースに登録されていない楽曲は画像が表示されません。また、MusicKit の利用には Apple Music サブスクリプションまたは無料トライアルが必要な場合があります。"),
        ("CloudKit 同期に失敗する",
         "iCloud にサインインしているか、設定 > Apple ID > iCloud で「ImasLiveDB」が有効になっているかご確認ください。"),
        ("セットリストスキャナーが認識しない",
         "設定 > プライバシーとセキュリティ > 音声認識・カメラ で本アプリへのアクセスを許可してください。"),
        ("アプリが公式アプリではないのですか?",
         "はい、本アプリは非公式のファンメイドアプリです。バンダイナムコエンターテインメント等とは一切関係ありません。"),
    ]

    var body: some View {
        List {
            ImasListSection("フィードバック・バグ報告") {
                ImasActionRow(title: "GitHub Issue で報告する", systemImage: "arrow.up.right.square") {
                    AppAnalytics.tap("support.github_issue")
                    openURL(githubIssueURL)
                }
            }

            ImasListSection("よくある質問") {
                ImasProse(blocks: faqs.flatMap { [.heading("Q. \($0.q)"), .paragraph("A. \($0.a)")] })
                    .padding(.horizontal, DS.Space.rowH)
                    .padding(.vertical, DS.Space.rowV)
            }
        }
        .imasForm()
        .navigationTitle("サポート")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("support")
    }
}
