import SwiftUI

// MARK: - Model

/// ヘルプの 1 機能カテゴリ。
struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let summary: String
    let body: [HelpItem]
}

struct HelpItem: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
}

// MARK: - Data

enum HelpCatalog {
    static let sections: [HelpSection] = [
        HelpSection(
            icon: "music.mic",
            tint: .pink,
            title: "ライブを探す",
            summary: "全ブランドのライブ・公演・セットリストを年別に閲覧できます。",
            body: [
                HelpItem(label: "年別リストで時系列に追える",
                         detail: "1000公演以上を年で分けて表示。新しい順なので、最新のライブから過去まで一気に俯瞰できます。"),
                HelpItem(label: "ブランドでフィルタ",
                         detail: "右上の絞り込みボタンから、765AS / シンデレラ / ミリオン / SideM / シャニ / 学マス / ヴイアラ など特定ブランドだけに絞れます。"),
                HelpItem(label: "種別 (live / stream / event / other) で絞れる",
                         detail: "本ライブ・配信・イベント・その他を切り替え可能。配信中心の活動だけ追いたい時に便利。"),
                HelpItem(label: "詳細でセトリ・出演者・チケット情報を確認",
                         detail: "ライブをタップすると、公演日ごとのセトリ、出演アイドル、コーレス、参考動画、チケット情報まで確認できます。"),
                HelpItem(label: "参加したライブを記録",
                         detail: "詳細画面から「参加した」をオンにすると、マイページの参加カウントに加算されます。"),
            ]
        ),
        HelpSection(
            icon: "music.note.list",
            tint: .indigo,
            title: "楽曲を探す",
            summary: "2300曲以上を曲名・アルバム・シリーズで探索できます。",
            body: [
                HelpItem(label: "3 つの表示モード",
                         detail: "曲一覧 / アルバムグリッド / シリーズグリッド を絞り込みパネルから切り替え可能。"),
                HelpItem(label: "Apple Music 連携",
                         detail: "Apple Music に契約していればプレビュー再生 / フル再生 OK。ジャケ写も自動取得。"),
                HelpItem(label: "歌唱履歴で深掘り",
                         detail: "曲詳細から「どのライブで何回歌われたか」を一覧表示。担当曲の披露頻度がわかります。"),
                HelpItem(label: "オリジナルメンバーを表示",
                         detail: "曲のアイコン群はオリジナル歌唱メンバー (ライブ歌唱者ではなく)。ユニット曲はユニット名で表示されます。"),
                HelpItem(label: "回収済 / 未回収で絞り込み",
                         detail: "マイマークで「回収済」を付けた曲だけ、または未回収だけを表示できます。"),
            ]
        ),
        HelpSection(
            icon: "person.3.fill",
            tint: .orange,
            title: "アイドル・CVを探す",
            summary: "全ブランドのアイドルを名前・CV名・属性で横断検索できます。",
            body: [
                HelpItem(label: "リスト / グリッド 切り替え",
                         detail: "上部の切り替えボタンで、密な一覧 (リスト) と画像中心のグリッドを切り替えられます。"),
                HelpItem(label: "アイドル名 ↔ CV 名 で表示切替",
                         detail: "絞り込みパネルから「CV名で表示」に切り替えると、 声優名で一覧化されます。"),
                HelpItem(label: "属性で絞り込み",
                         detail: "キュート/クール/パッション (CG)、 Fairy/Angel/Princess (ML)、 1年/3年 (学マス) などブランドごとの属性で絞れます。"),
                HelpItem(label: "アイドル詳細で担当曲・出演ライブを確認",
                         detail: "アイドルをタップすると、担当曲リスト・出演ライブ・誕生日・カラーが見られます。"),
                HelpItem(label: "別名 (aliases) も検索対象",
                         detail: "ロコ ↔ 伴田路子 のような別名表記も内部で同一アイドルとして紐づいています。"),
            ]
        ),
        HelpSection(
            icon: "bookmark.fill",
            tint: .red,
            title: "マイマーク（記録）",
            summary: "担当アイドル・回収済楽曲・参加ライブを記録できます。",
            body: [
                HelpItem(label: "担当アイドル",
                         detail: "アイドル詳細から「担当」を付けると、マイページに集約されて確認できます。"),
                HelpItem(label: "回収済 (持ってる) 楽曲",
                         detail: "曲詳細から「回収済」を付けると、自分のコレクション管理ができます。楽曲一覧で「回収済のみ」表示も可能。"),
                HelpItem(label: "参加ライブ",
                         detail: "ライブ詳細から「参加した」を付けると、マイページに参加履歴が積み上がります。"),
                HelpItem(label: "マイマークは端末に保存",
                         detail: "ローカル保存されるので、ログインなしで使えます。 CloudKit 同期にも対応 (端末間で同期可能)。"),
            ]
        ),
        HelpSection(
            icon: "square.and.pencil",
            tint: .blue,
            title: "みんなで編集",
            summary: "ログインすればセトリ・楽曲・ライブ情報を直接編集でき、その場で全員に反映されます。",
            body: [
                HelpItem(label: "直接編集して、すぐ反映",
                         detail: "承認待ちはありません。ログインユーザーがセトリ・新曲・新イベント・コーレス・参考動画などを直接追加・修正でき、CloudKit 経由ですぐ全員の端末に届きます。Wikipedia のような共同編集スタイルです。"),
                HelpItem(label: "編集には Sign in with Apple",
                         detail: "閲覧はログイン不要。編集に参加したい時だけマイページからログインしてください。各画面の「+」や鉛筆アイコンから編集できます。"),
                HelpItem(label: "すべての編集に履歴が残る",
                         detail: "誰がいつ何を変えたかが変更前後つきで記録されます。各データの編集履歴や、プロデュースタブの「最近の編集」フィードからたどれます。"),
                HelpItem(label: "「良かった」で感謝を伝える",
                         detail: "他の人の編集に「良かった」を付けられます。人気・感謝の指標で、付けた数・もらった数がマイページに表示されます。"),
                HelpItem(label: "間違いはすぐ戻せる",
                         detail: "自分の編集はいつでも取り消せます。誤りや荒らしはワンタップで元に戻され、悪質な場合はアカウントが利用停止になります。安心して編集してください。"),
                HelpItem(label: "貢献が積み上がる",
                         detail: "編集した数と「良かった」をもらった数で貢献度が積み上がり、マイページに称号バッジとして表示されます。"),
            ]
        ),
        HelpSection(
            icon: "tag.fill",
            tint: .teal,
            title: "タグ",
            summary: "ユーザー投稿のタグで曲を自由に分類できます。",
            body: [
                HelpItem(label: "曲にタグを付ける",
                         detail: "曲詳細から既存のタグを付けたり、新しいタグを作って付けたりできます。"),
                HelpItem(label: "タグから曲を辿る",
                         detail: "タグ一覧 → タグ詳細から、そのタグが付いた曲を一覧表示。「夏曲」「バラード」「神曲」など好きな切り口で検索可能。"),
                HelpItem(label: "タグの説明文を編集",
                         detail: "誰でもタグの説明を書き加えられます。Wikipedia のような共同編集スタイル。"),
            ]
        ),
        HelpSection(
            icon: "circle.hexagongrid.fill",
            tint: .purple,
            title: "ペンライト投票",
            summary: "曲ごとの「振る色」をみんなで投票して可視化。",
            body: [
                HelpItem(label: "曲詳細から好きな色セットを投票",
                         detail: "公式パレットの中から、その曲で振りたい色 (単色 / 複数色) を選んで投票できます。"),
                HelpItem(label: "集計結果を確認",
                         detail: "投票結果は色セット別の票数で表示。ライブ前の「色合わせ」用にどうぞ。"),
                HelpItem(label: "1 端末 1 票で差し替え可能",
                         detail: "同じ曲に複数回投票しても、最新の選択で上書きされます (端末単位)。"),
            ]
        ),
        HelpSection(
            icon: "music.note.house.fill",
            tint: .pink,
            title: "イントロドン",
            summary: "曲のイントロを聴いて曲名を当てるクイズ。",
            body: [
                HelpItem(label: "未加入でもプレビュー再生で遊べる",
                         detail: "Apple Music サブスク加入者はカタログのフル再生、未加入でも 30 秒プレビューで遊べます。"),
                HelpItem(label: "ブランド・難易度を選択",
                         detail: "ブランド絞り込みや、再生秒数で難易度調整できます。"),
                HelpItem(label: "音声入力で回答可能",
                         detail: "マイクで曲名を読み上げると、 Speech 認識で自動回答できます。"),
                HelpItem(label: "ベストスコアを記録",
                         detail: "ブランドごとに自己ベストが残ります。"),
            ]
        ),
        HelpSection(
            icon: "magnifyingglass",
            tint: .gray,
            title: "検索",
            summary: "「このタブを絞り込む」検索と、「全体を横断する」検索の 2 種類があります。",
            body: [
                HelpItem(label: "タブ内検索 = この一覧を絞り込む",
                         detail: "ライブ / 楽曲 / アイドル 各タブの検索バーは、いま表示中の一覧 (適用中の絞り込みも含む) をその場で絞り込みます。"),
                HelpItem(label: "全体検索 = 横断して探す",
                         detail: "左上のキラキラ虫眼鏡から、楽曲・アイドル・ライブをまとめて横断検索できます。タブをまたいで一気に目的の項目へ飛べます。"),
                HelpItem(label: "見つからなければ全体検索へ",
                         detail: "タブ内検索で結果が無いときは「全体から検索」ボタンが出ます。同じ語句のまま 1 タップで横断検索に切り替えられます。"),
                HelpItem(label: "アイドル別名にも対応",
                         detail: "「ロコ」と検索しても「伴田路子」がヒット。シャニやミリの別名表記も内部で名寄せ済み。"),
            ]
        ),
        HelpSection(
            icon: "calendar",
            tint: .green,
            title: "カレンダー",
            summary: "ライブ・CD リリース・アイドル誕生日を月別に表示。",
            body: [
                HelpItem(label: "プロデュースタブ → カレンダー",
                         detail: "月単位で全アイマスイベントを俯瞰。"),
                HelpItem(label: "ライブ・リリース・誕生日を色分け",
                         detail: "それぞれ別色で表示。タップで詳細にジャンプ。"),
            ]
        ),
        HelpSection(
            icon: "photo.on.rectangle.angled",
            tint: .mint,
            title: "画像インポート",
            summary: "アイドル・ブランドのアイコン画像を一括取り込み。",
            body: [
                HelpItem(label: "マイページ → 画像インポート",
                         detail: "JSON で {アイドル名: 画像URL} の形式を渡せば、まとめてダウンロード+保存できます。"),
                HelpItem(label: "型紙 JSON をダウンロード",
                         detail: "アプリ内から型紙 (全アイドル/全ブランド名がキーになった JSON) を書き出せます。それに画像URLを書き足すだけ。"),
                HelpItem(label: "アイドル別名にも対応",
                         detail: "型紙には別名表記も含まれているので、 ロコ でも 伴田路子 でも好きな表記の URL を書けます。"),
                HelpItem(label: "全画像リセット可能",
                         detail: "失敗したり差し替えたい時は「カスタム画像を全削除」でリセットできます。"),
            ]
        ),
        HelpSection(
            icon: "icloud.fill",
            tint: .cyan,
            title: "同期とアカウント",
            summary: "CloudKit で常に最新のデータ、 Sign in with Apple で編集に参加。",
            body: [
                HelpItem(label: "マスタデータは CloudKit で自動同期",
                         detail: "新しいライブやセトリは CloudKit から差分配信されます。アプリ更新を待たずに最新化されます。"),
                HelpItem(label: "Sign in with Apple は編集用",
                         detail: "閲覧機能には不要。データを編集したい時だけログインしてください。"),
                HelpItem(label: "アカウント削除も可能",
                         detail: "マイページ → アカウントを削除 で、サーバー上の編集履歴とユーザー情報をすべて削除します。"),
            ]
        ),
    ]
}

// MARK: - Top View

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("アイドルライブDB の使い方")
                            .font(.imasTitle3)
                        Text("各カテゴリで「こんなことができる」を一覧で紹介しています。気になる項目から覗いてみてください。")
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink2)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("特集") {
                    NavigationLink {
                        WidgetHowToView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.square.badge.camera")
                                .font(.imasTitle3)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.55),
                                                            Color(red: 0.55, green: 0.35, blue: 0.95)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("担当ウィジェットの使い方").font(.imasHeadline)
                                Text("推しの画像をホーム画面に。画像付きで手順を案内します。")
                                    .font(.imasCaption)
                                    .foregroundStyle(DS.ink2)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("機能カテゴリ") {
                    ForEach(HelpCatalog.sections) { section in
                        NavigationLink {
                            HelpDetailView(section: section)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: section.icon)
                                    .font(.imasTitle3)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(section.tint.gradient, in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title).font(.imasHeadline)
                                    Text(section.summary)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section {
                    Text("使い方は今後さらに増えていく予定です。データの間違いに気づいたらログインしてその場で直せます。要望や不具合は GitHub Issue からお寄せください。")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .navigationTitle("ヘルプ")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("help")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Detail View

private struct HelpDetailView: View {
    let section: HelpSection

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: section.icon)
                        .font(.imasScaled( 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(section.tint.gradient, in: RoundedRectangle(cornerRadius: 18))
                    Text(section.title)
                        .font(.imasTitle2)
                    Text(section.summary)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .listRowBackground(Color.clear)
            }

            Section("できること") {
                ForEach(section.body) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(section.tint)
                                .padding(.top, 2)
                            Text(item.label)
                                .font(.imasSubhead.bold())
                        }
                        Text(item.detail)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink2)
                            .padding(.leading, 26)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(DS.surface)
            .listRowSeparatorTint(DS.sep)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HelpView()
}
