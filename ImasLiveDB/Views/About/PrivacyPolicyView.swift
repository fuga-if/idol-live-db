import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    policySection(
                        title: "アプリの概要",
                        content: "本アプリ（ImasLiveDB）は、アイドルマスターシリーズのライブ・セットリスト情報を管理・閲覧するための非公式ファンメイドアプリです。株式会社バンダイナムコエンターテインメントをはじめとする権利者とは一切関係ありません。"
                    )

                    policySection(
                        title: "収集するデータ",
                        content: """
• 端末識別子（UUID）: Keychain に保存される匿名の識別子です。個人情報と紐付けることはありません。
• アプリ設定: お気に入りブランドなどの設定は UserDefaults に端末内のみ保存されます。
• CloudKit 投稿内容: コミュニティ機能を利用する場合、Apple ID による認証が必要です。投稿したセットリスト・修正提案などのコンテンツは CloudKit Public Database に保存・公開されます。
"""
                    )

                    policySection(
                        title: "使用する Apple フレームワーク",
                        content: """
• CloudKit: コミュニティデータの同期・投稿
• MusicKit: Apple Music からのジャケット画像取得
• Speech（音声認識）: セットリストスキャン機能
• Vision: OCR によるセットリスト読み取り
"""
                    )

                    policySection(
                        title: "サードパーティサービス",
                        content: """
• Cloudflare Workers: アプリの API 通信先として利用しています。
• Apple Music: ジャケット画像の取得に MusicKit API を利用しています（正式な Apple のサービスです）。
"""
                    )

                    policySection(
                        title: "データの共有",
                        content: "コミュニティ機能で投稿したコンテンツ（セットリスト報告・修正提案など）は CloudKit Public Database を通じて他のユーザーに公開されます。投稿内容に個人情報を含めないようご注意ください。"
                    )

                    policySection(
                        title: "ユーザーの権利",
                        content: "投稿データの削除を希望される場合は、GitHub Issue にてご連絡ください。対応いたします。"
                    )

                    policySection(
                        title: "連絡先",
                        content: "プライバシーに関するお問い合わせ・データ削除依頼は下記 GitHub Issue からお願いします。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"
                    )
                }

                Text("最終更新日: 2026年4月23日")
                    .font(.imasCaption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("privacy_policy")
    }

    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.imasHeadline)
            Text(content)
                .font(.imasSubhead)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
