import SwiftUI
import StoreKit

struct AboutView: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            ImasListSection {
                VStack(spacing: DS.Space.gap) {
                    ImasIconTile(systemImage: "music.mic.circle.fill", size: .s56, tone: .solid)
                    Text("ImasLiveDB").imasText(.sectionTitle)
                    Text("非公式ファンメイドアプリ").imasText(.rowSubtitle)
                    Text("ver. \(appVersion) (\(buildNumber))").imasText(.meta)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.gapLoose)
            }

            ImasListSection("開発者") {
                ImasValueRow(key: "開発者", value: "fuga-if")
                Link(destination: URL(string: "https://github.com/fuga-if")!) {
                    ImasNavRow(title: "GitHub プロフィール", systemImage: "arrow.up.right.square")
                }
            }

            ImasListSection(footer: "サーバー運用費等の足しにさせていただきます。任意のご支援です。") {
                Link(destination: URL(string: "https://ko-fi.com/fugaapp")!) {
                    ImasNavRow(title: "開発をサポートする", systemImage: "heart.fill")
                }
            }

            ImasListSection(
                "データ提供",
                footer: "各情報源のデータはそのままの複製ではなく、独自の集計・整形を加えて利用しています。"
            ) {
                ossCredit(
                    name: "アイマスDB",
                    license: "楽曲・ライブ等のデータ参照元",
                    url: "https://imas-db.jp/"
                )
                ossCredit(
                    name: "music765plus",
                    license: "楽曲・ライブセトリのデータ参照元",
                    url: "https://music765plus.com/"
                )
                ossCredit(
                    name: "im@sparql",
                    license: "アイドルのプロフィール (CV・カラー等)",
                    url: "https://sparql.crssnky.xyz/imas/"
                )
                ossCredit(
                    name: "imas-palette",
                    license: "アイドルのイメージカラー",
                    url: "https://github.com/arrow2nd/imas-palette"
                )
            }

            ImasListSection("ライセンス情報") {
                // 許諾条件で掲示が要る。歌詞タブを畳んでも消さないこと
                // (許諾期間中は掲載し続けるのが条件)。
                JASRACLicenseNotice(placement: .about)
                ossCredit(name: "GRDB.swift", license: "MIT License", url: "https://github.com/groue/GRDB.swift")
                ossCredit(name: "Nuke", license: "MIT License", url: "https://github.com/kean/Nuke")
                ossCredit(name: "Spotify iOS SDK", license: "Spotify Developer Terms", url: "https://github.com/spotify/ios-sdk")
                ossCredit(name: "MPMessagePack (Spotify iOS SDK に同梱)", license: "MIT License", url: "https://github.com/gabriel/MPMessagePack")
                // P名刺の名前の書体 (同梱。一覧はコア)。
                ForEach(cardNameFonts(), id: \.key) { font in
                    ossCredit(name: "\(font.familyName) (P名刺の書体)", license: font.license, url: font.sourceUrl)
                }
            }

            ImasListSection(
                "アプリ情報",
                footer: """
                担当・お気に入り・メモは iCloud に自動バックアップされ、再インストールや機種変更でも復元されます (同じ Apple ID でのサインインが必要)。

                本アプリはアイドルマスターシリーズの非公式ファンメイドアプリです。バンダイナムコエンターテインメント等の権利者とは一切関係ありません。
                """
            ) {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    ImasNavRow(title: "プライバシーポリシー", showsChevron: false)
                }
                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    ImasNavRow(title: "利用規約", showsChevron: false)
                }
                NavigationLink {
                    SupportView()
                } label: {
                    ImasNavRow(title: "サポート", showsChevron: false)
                }
                // ⚠️ ここで requestReview() を呼ばないこと。OS の都合 (年3回の上限等) で
                //    無視されることがあり、押しても何も起きないボタンになる。
                //    自分から評価しに来た人には App Store の投稿画面を直接開く。
                //    requestReview() は「こちらから声を掛ける」側 (ContentView) の担当。
                if let url = ReviewPrompt.writeReviewURL {
                    Link(destination: url) {
                        ImasNavRow(title: "アプリを評価する", systemImage: "star.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        AppAnalytics.tap("about.rate_app")
                    })
                }
            }
        }
        .imasForm()
        .navigationTitle("アプリについて")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("about")
    }

    private func ossCredit(name: String, license: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            ImasNavRow(title: name, subtitle: license)
        }
    }
}
