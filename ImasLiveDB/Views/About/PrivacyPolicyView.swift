import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ImasPage {
            ImasProse(blocks: [
                .heading("アプリの概要"),
                .paragraph("本アプリ（ImasLiveDB）は、アイドルマスターシリーズのライブ・セットリスト情報を管理・閲覧するための非公式ファンメイドアプリです。株式会社バンダイナムコエンターテインメントをはじめとする権利者とは一切関係ありません。"),

                .heading("収集するデータ"),
                .bullets([
                    "端末識別子（UUID）: Keychain に保存される匿名の識別子です。個人情報と紐付けることはありません。",
                    "アプリ設定: お気に入りブランドなどの設定は UserDefaults に端末内のみ保存されます。",
                    "CloudKit 投稿内容: コミュニティ機能を利用する場合、Apple ID による認証が必要です。投稿したセットリスト・修正提案などのコンテンツは CloudKit Public Database に保存・公開されます。",
                ]),

                .heading("使用する Apple フレームワーク"),
                .bullets([
                    "CloudKit: コミュニティデータの同期・投稿",
                    "MusicKit: Apple Music からのジャケット画像取得",
                    "Speech（音声認識）: セットリストスキャン機能",
                    "Vision: OCR によるセットリスト読み取り",
                ]),

                .heading("サードパーティサービス"),
                .bullets([
                    "Cloudflare Workers: アプリの API 通信先として利用しています。",
                    "Apple Music: ジャケット画像の取得に MusicKit API を利用しています（正式な Apple のサービスです）。",
                ]),

                .heading("データの共有"),
                .paragraph("コミュニティ機能で投稿したコンテンツ（セットリスト報告・修正提案など）は CloudKit Public Database を通じて他のユーザーに公開されます。投稿内容に個人情報を含めないようご注意ください。"),

                .heading("ユーザーの権利"),
                .paragraph("投稿データの削除を希望される場合は、GitHub Issue にてご連絡ください。対応いたします。"),

                .heading("連絡先"),
                .paragraph("プライバシーに関するお問い合わせ・データ削除依頼は下記 GitHub Issue からお願いします。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"),

                .note("最終更新日: 2026年4月23日"),
            ])
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("privacy_policy")
    }
}
