import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: DS.sp3) {
                    Image(systemName: "music.mic.circle.fill")
                        .font(.imasScaled( 64))
                        .foregroundStyle(.tint)
                    Text("ImasLiveDB")
                        .font(.imasTitle2.bold())
                    Text("非公式ファンメイドアプリ")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    Text("ver. \(appVersion) (\(buildNumber))")
                        .font(.imasScaled(11))
                        .foregroundStyle(DS.ink2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.sp4)
            }

            Section("開発者") {
                LabeledContent("開発者", value: "fuga-if")
                Link(destination: URL(string: "https://github.com/fuga-if")!) {
                    Label("GitHub プロフィール", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                Link(destination: URL(string: "https://ko-fi.com/fugaapp")!) {
                    Label("開発をサポートする", systemImage: "heart.fill")
                }
            } footer: {
                Text("サーバー運用費等の足しにさせていただきます。任意のご支援です。")
            }

            Section {
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
            } header: {
                Text("データ提供")
            } footer: {
                Text("各情報源のデータはそのままの複製ではなく、独自の集計・整形を加えて利用しています。")
            }

            Section("ライセンス情報") {
                ossCredit(name: "GRDB.swift", license: "MIT License", url: "https://github.com/groue/GRDB.swift")
                ossCredit(name: "Nuke", license: "MIT License", url: "https://github.com/kean/Nuke")
            }

            Section("アプリ情報") {
                NavigationLink("プライバシーポリシー") {
                    PrivacyPolicyView()
                }
                NavigationLink("利用規約") {
                    TermsOfServiceView()
                }
                NavigationLink("サポート") {
                    SupportView()
                }
                Button {
                    AppAnalytics.tap("about.rate_app")
                    requestReview()
                } label: {
                    Label("アプリを評価する", systemImage: "star.fill")
                }
            }

            Section {
                Text("担当・お気に入り・メモは iCloud に自動バックアップされ、再インストールや機種変更でも復元されます (同じ Apple ID でのサインインが必要)。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }

            Section {
                Text("本アプリはアイドルマスターシリーズの非公式ファンメイドアプリです。バンダイナムコエンターテインメント等の権利者とは一切関係ありません。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
        }
        .navigationTitle("アプリについて")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("about")
    }

    private func ossCredit(name: String, license: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(name)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink)
                Text(license)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
        }
    }
}
