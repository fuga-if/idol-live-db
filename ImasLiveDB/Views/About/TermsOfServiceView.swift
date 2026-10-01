import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        ImasPage {
            ImasProse(blocks: [
                .heading("免責・権利表記"),
                .paragraph("本アプリは非公式のファン制作アプリです。株式会社バンダイナムコエンターテインメント、株式会社バンダイナムコミュージックライブ、その他アイドルマスターシリーズに関わる権利者とは一切関係ありません。"),

                .heading("知的財産権"),
                .paragraph("アイドルマスターシリーズおよび関連するキャラクター・楽曲・ロゴ・イラスト等の著作権・商標権はすべて各権利者に帰属します。本アプリはこれらを無断で使用・複製・配布しません。"),

                .heading("使用している素材について"),
                .bullets([
                    "ジャケット画像: Apple Music の正式 API（MusicKit）経由で取得したもののみを表示しています。",
                    "歌詞: 使用していません。",
                    "キャラクターイラスト: 使用していません。",
                    "公式ロゴ: 使用していません。",
                ]),

                .heading("ユーザー投稿コンテンツ"),
                .paragraph("コミュニティ機能への投稿(セットリスト情報・修正提案など)は、ユーザー自身の責任において行ってください。投稿コンテンツに起因する問題について、開発者は責任を負いません。"),

                .heading("投稿コンテンツのライセンス"),
                .paragraph("ユーザーが投稿したコンテンツは CloudKit Public Database に保存され、本アプリを利用する他のユーザーに公開されます。投稿することで、当該コンテンツをアプリ内で表示・利用することに同意したものとみなします。"),

                .heading("禁止事項"),
                .paragraph("以下の行為を禁止します。"),
                .bullets([
                    "他者の著作権・商標権・プライバシーを侵害するコンテンツの投稿",
                    "他のユーザーへの嫌がらせ・誹謗中傷",
                    "スパムや虚偽情報の投稿",
                    "本アプリのシステムへの不正アクセス・改ざん",
                ]),

                .heading("サービスの変更・停止"),
                .paragraph("開発者は予告なくアプリの機能変更・サービス停止を行う場合があります。これによって生じた損害について開発者は責任を負いません。"),

                .heading("連絡先"),
                .paragraph("ご意見・不具合報告は GitHub Issue にてご連絡ください。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"),

                .note("最終更新日: 2026年4月23日"),
            ])
        }
        .navigationTitle("利用規約")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("terms_of_service")
    }
}
