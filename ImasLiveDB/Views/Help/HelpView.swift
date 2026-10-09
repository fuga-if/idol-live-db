import SwiftUI

// MARK: - Model

/// ヘルプの 1 機能カテゴリ。
struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    /// カテゴリ識別用の装飾テーマ seed (hex)。`ImasTheme.derive(seed:scheme:)` に渡して
    /// ライト/ダーク双方で一貫したトークンを導出する (生の SwiftUI システムカラーは使わない)。
    let tint: String
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
            tint: "#FF2D55",
            title: "ライブを探す",
            summary: "全ブランドのライブ・公演・セットリストを年別に閲覧できます。",
            body: [
                HelpItem(label: "年別リストで時系列に追える",
                         detail: "1000公演以上を年で分けて表示。新しい順なので、最新のライブから過去まで一気に俯瞰できます。"),
                HelpItem(label: "ブランドでフィルタ",
                         detail: "右上の絞り込みボタンから、765AS / シンデレラ / ミリオン / SideM / シャニ / 学マス / ヴイアラ など特定ブランドだけに絞れます。"),
                HelpItem(label: "ライブの種別で見分ける",
                         detail: "周年ライブ・オーケストラ・他社イベント・リリースイベント・バースデーライブなどの種別が付いています。絞り込みで種別ごとに外すこともできます。"),
                HelpItem(label: "詳細でセトリ・出演者・チケット情報を確認",
                         detail: "ライブをタップすると、公演日ごとのセトリ、出演アイドル、参考動画、チケット情報まで確認できます。"),
                HelpItem(label: "参加したライブを記録",
                         detail: "公演の行を左にスワイプすると、その場で参加 (現地 / 配信 / LV) を登録できます。現地で見て配信のアーカイブも買った公演のように、形態は複数付けられます (チケット代も形態ごとに記録できます)。詳細画面からも付けられ、マイページの参加カウントに加算されます。"),
                HelpItem(label: "衣装と着用公演",
                         detail: "イベント詳細の「情報」タブに、そのイベントで着た衣装がまとまっています。衣装を開くと、ほかのイベントも含めてその衣装を着た公演と曲をたどれます。"),
                HelpItem(label: "開催前のセトリ予想",
                         detail: "開催前の公演では、みんなの予想に加えて、過去のセトリから推定した「機械予測」が出ます。気になる曲はそのまま自分の予想に入れられます。"),
            ]
        ),
        HelpSection(
            icon: "list.number",
            tint: "#FF6B3D",
            title: "セットリストの見方",
            summary: "曲ごとの「いつぶり」や自分の回収を、セトリの行で確かめられます。",
            body: [
                HelpItem(label: "シンプル / 普通 / 詳細 の 3 つの表示",
                         detail: "セトリ右上の「…」メニューから選べます。シンプルは曲名と歌った人だけ、詳細は自分の回収まで行に出します。"),
                HelpItem(label: "「初披露」「3 年 10 か月ぶり」",
                         detail: "その曲が前にいつ歌われたかを出します。数えるのはその公演の時点なので、昔のライブを開くと当時の間隔が出ます。1 か月未満は「12 日ぶり」のように日数で出します。"),
                HelpItem(label: "自分の回収を重ねる",
                         detail: "詳細表示では「初回収」「回収 3 回目」「未回収」が行に出て、セトリの上に「この公演で 12 曲回収」のような要約が出ます。"),
                HelpItem(label: "オリメンにとって何回目か",
                         detail: "カバーや別ユニットで歌われた曲には、歌った本人にとって何回目か (オリメン 4 回目 など) を添えます。"),
                HelpItem(label: "数えない公演",
                         detail: "会場の舞台が無い配信だけのライブと MV 上映会は、セトリには並びますが、披露回数・いつぶり・回収には数えません。"),
            ]
        ),
        HelpSection(
            icon: "music.note.list",
            tint: "#5856D6",
            title: "楽曲を探す",
            summary: "2300曲以上を曲名・アルバム・シリーズで探索できます。",
            body: [
                HelpItem(label: "3 つの表示モード",
                         detail: "曲一覧 / アルバムグリッド / シリーズグリッド を絞り込みパネルから切り替え可能。"),
                HelpItem(label: "Apple Music 連携",
                         detail: "Apple Music に契約していればプレビュー再生 / フル再生 OK。ジャケ写も自動取得。"),
                HelpItem(label: "Spotify 連携",
                         detail: "自分の Spotify アプリの Client ID で連携すると、セトリや自分のプレイリストを Spotify に書き出せ、曲を Spotify で開けます。始め方はヘルプの「Spotify と連携する」に図つきで載っています。"),
                HelpItem(label: "歌唱履歴で深掘り",
                         detail: "曲詳細から「どのライブで何回歌われたか」を一覧表示。担当曲の披露頻度がわかります。"),
                HelpItem(label: "オリジナルメンバーを表示",
                         detail: "曲のアイコン群はオリジナル歌唱メンバー (ライブ歌唱者ではなく)。ユニット曲はユニット名で表示されます。"),
                HelpItem(label: "回収済 / 未回収で絞り込み",
                         detail: "マイマークで「回収済」を付けた曲だけ、または未回収だけを表示できます。"),
                HelpItem(label: "並びはリリース日順",
                         detail: "既定はリリース日の新しい順です。件数の行にある並び替えメニューから、披露回数順などにすぐ切り替えられます。"),
                HelpItem(label: "曲の補足",
                         detail: "曲名の下に、その曲についての補足が出ます。ログインすれば曲詳細から補足を書いたり直したりできます。"),
                HelpItem(label: "KAMISABI の収録曲",
                         detail: "絞り込みで「KAMISABI収録曲のみ」を選ぶと収録曲だけになります。カードの所持も記録でき、収録率が分かります。"),
            ]
        ),
        HelpSection(
            icon: "text.quote",
            tint: "#C2410C",
            title: "歌詞とコールガイド",
            summary: "JASRAC・NexTone の許諾を受けて歌詞を掲載しています。コールは歌詞の行に書き込めます。",
            body: [
                HelpItem(label: "曲詳細で歌詞を読む",
                         detail: "掲載している曲は、曲詳細の歌詞タブで読めます。"),
                HelpItem(label: "歌詞で曲を探す",
                         detail: "楽曲タブの検索で「歌詞で探す」を選ぶと、歌詞の中の言葉から曲を探せます。"),
                HelpItem(label: "コールガイド",
                         detail: "歌詞の行ごとにコールや手拍子を書き込めます。ライブ前の予習にどうぞ。ログインすれば誰でも書けます。"),
                HelpItem(label: "コールガイドのまとめ",
                         detail: "プロデュースタブの「コールガイド」で、コールが入っている曲・最近書かれた曲・まだ書かれていない曲を 1 画面で見られます。楽曲一覧も「コールガイドがある曲のみ」で絞れます。"),
            ]
        ),
        HelpSection(
            icon: "person.3.fill",
            tint: "#FF9500",
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
                         detail: "アイドルをタップすると、担当曲・出演ライブ・誕生日・カラーが見られます。担当曲はソロ・ユニット・全体曲・カバーの小タブで切り替えられます。"),
                HelpItem(label: "別名 (aliases) も検索対象",
                         detail: "ロコ ↔ 伴田路子 のような別名表記も内部で同一アイドルとして紐づいています。"),
            ]
        ),
        HelpSection(
            icon: "bookmark.fill",
            tint: "#FF3B30",
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
            icon: "yensign.circle.fill",
            tint: "#16A34A",
            title: "収支（家計簿）",
            summary: "チケット代・交通費・グッズ代など、アイマスに使ったお金を記録できます。",
            body: [
                HelpItem(label: "プロデュースタブの「収支」から",
                         detail: "日付と金額と費目 (チケット・交通・宿・グッズ・課金 など) で記録します。月別・年別の合計と費目ごとの内訳が出ます。"),
                HelpItem(label: "公演に紐づける",
                         detail: "支出を公演に紐づけると、「この遠征でいくら使ったか」と 1 公演あたりの額が分かります。課金や通販は紐づけずに同じ帳簿へ入れられます。"),
                HelpItem(label: "チケット代を自動で聞く",
                         detail: "参加を付けたとき、チケット価格が分かっている公演ならその額で記録するかを確認します。過去の参加から、まだ記録していないチケット代をまとめて取り込むこともできます。"),
                HelpItem(label: "端末の中だけに保存",
                         detail: "収支はサーバーに送らず、端末の中だけに保存します。"),
            ]
        ),
        HelpSection(
            icon: "chart.bar.fill",
            tint: "#0EA5E9",
            title: "習熟度",
            summary: "曲ごとの覚え具合を付けて、シリーズやユニットごとにどこまで覚えたかを確かめられます。",
            body: [
                HelpItem(label: "プロデュースタブの「習熟度」から",
                         detail: "シリーズ・ユニット・年代ごとに曲がまとまっていて、あと何曲覚えればいいかが分かります。"),
                HelpItem(label: "1 タップで段階を上げる",
                         detail: "曲の行から 1 タップで段階を上げられます。"),
                HelpItem(label: "段階は自分で決める",
                         detail: "マイページの設定で、段の数 (2〜4 段) と呼び名を変えられます。呼び名を変えても、付けた記録はそのまま残ります。"),
            ]
        ),
        HelpSection(
            icon: "square.and.pencil",
            tint: "#007AFF",
            title: "みんなで編集",
            summary: "ログインすればセトリ・楽曲・ライブ情報を直接編集でき、その場で全員に反映されます。",
            body: [
                HelpItem(label: "直接編集して、すぐ反映",
                         detail: "承認待ちはありません。ログインユーザーがセトリ・新曲・新イベント・参考動画などを直接追加・修正でき、CloudKit 経由ですぐ全員の端末に届きます。Wikipedia のような共同編集スタイルです。"),
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
            tint: "#30B0C7",
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
            tint: "#AF52DE",
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
            icon: "gamecontroller.fill",
            tint: "#FF2D55",
            title: "クイズ・ゲーム",
            summary: "プロデュースタブの「クイズ・ゲーム」で 6 種類のクイズが遊べます。",
            body: [
                HelpItem(label: "6 種類のクイズ",
                         detail: "アイドル当て・ソロ曲クイズ・歌詞クイズ・セトリ当て・イントロドン・メンバーカラー合わせがあります。"),
                HelpItem(label: "歌詞クイズ",
                         detail: "歌詞の一節から曲名を当てる「曲名当て」と、次に来る行を選ぶ「続きはどれ」の 2 通りで遊べます。"),
                HelpItem(label: "セトリ当て",
                         detail: "実際の公演のセトリの空欄に入る曲を 4 択で当てます。"),
                HelpItem(label: "累計ポイントと「つづきから」",
                         detail: "遊ぶほどポイントが貯まります。途中でやめても「つづきから」で再開できます。結果は画像にしてシェアできます。"),
                HelpItem(label: "イントロドンは未加入でもプレビューで遊べる",
                         detail: "Apple Music サブスク加入者はカタログのフル再生、未加入でも 30 秒プレビューで遊べます。"),
                HelpItem(label: "ブランド・難易度を選択",
                         detail: "出題するブランドや難易度を選べます。イントロドンは再生秒数で難易度を調整できます。"),
                HelpItem(label: "音声入力で回答可能",
                         detail: "イントロドンでは、マイクで曲名を読み上げると自動で回答できます。"),
            ]
        ),
        HelpSection(
            icon: "magnifyingglass",
            tint: "#8E8E93",
            title: "検索",
            summary: "ライブ・楽曲・アイドルの各一覧の検索欄から、その場で絞り込めます。",
            body: [
                HelpItem(label: "一覧の中で絞り込む",
                         detail: "ライブ / 楽曲 / アイドル 各タブの検索欄は、いま表示中の一覧をその場で絞り込みます。ブランドの絞り込みや並び順と組み合わせられます。"),
                HelpItem(label: "何で探すかを切り替える",
                         detail: "楽曲は曲名・アイドル名・作詞作曲者・歌詞、アイドルはアイドル名と CV 名を切り替えて探せます。打っている間、それぞれ何件当たるかが出ます。"),
                HelpItem(label: "ほかのタブの件数",
                         detail: "「ライブに 8」のように、同じ語がほかのタブで何件当たるかも出ます。押すとそのタブへ移って同じ語で絞り込みます。"),
                HelpItem(label: "アイドル別名にも対応",
                         detail: "「ロコ」と検索しても「伴田路子」がヒット。シャニやミリの別名表記も内部で名寄せ済み。"),
            ]
        ),
        HelpSection(
            icon: "calendar",
            tint: "#34C759",
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
            tint: "#00C7BE",
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
            tint: "#32ADE6",
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
                ImasListSection {
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        Text("アイドルライブDB の使い方").imasText(.cardTitle)
                        Text("各カテゴリで「こんなことができる」を一覧で紹介しています。気になる項目から覗いてみてください。")
                            .imasText(.rowSubtitle)
                    }
                    .padding(.vertical, DS.Space.gapTight)
                }

                ImasListSection("特集") {
                    NavigationLink {
                        WidgetHowToView()
                    } label: {
                        ImasNavRow(
                            title: "担当ウィジェットの使い方",
                            subtitle: "推しの画像をホーム画面に。画像付きで手順を案内します。",
                            systemImage: "person.crop.square.badge.camera",
                            iconTone: .themed,
                            seed: "#FF4D8C",
                            showsChevron: false,
                            subtitleLineLimit: 2
                        )
                    }
                    NavigationLink {
                        SpotifyHowToView()
                    } label: {
                        ImasNavRow(
                            title: "Spotify と連携する",
                            subtitle: "自分の Spotify アプリを作って、セトリを Spotify のプレイリストに。図つきで手順を案内します。",
                            systemImage: "music.note.list",
                            showsChevron: false,
                            subtitleLineLimit: 2
                        )
                    }
                }

                ImasListSection("機能カテゴリ") {
                    ForEach(HelpCatalog.sections) { section in
                        NavigationLink {
                            HelpDetailView(section: section)
                        } label: {
                            ImasNavRow(
                                title: section.title,
                                subtitle: section.summary,
                                systemImage: section.icon,
                                iconTone: .themed,
                                seed: section.tint,
                                showsChevron: false,
                                subtitleLineLimit: 2
                            )
                        }
                    }
                }

                ImasListSection {
                    ImasNote("使い方は今後さらに増えていく予定です。データの間違いに気づいたらログインしてその場で直せます。要望や不具合は GitHub Issue からお寄せください。")
                        .padding(.vertical, DS.Space.gapTight)
                }
            }
            .listStyle(.plain)
            .imasForm()
            .navigationTitle("ヘルプ")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("help")
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
    }
}

// MARK: - Detail View

private struct HelpDetailView: View {
    let section: HelpSection
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: section.tint, scheme: scheme)
        List {
            ImasListSection {
                VStack(spacing: DS.Space.gapLoose) {
                    ImasIconTile(systemImage: section.icon, size: .s56, tone: .themed, seed: section.tint)
                    Text(section.title).imasText(.sectionTitle)
                    Text(section.summary)
                        .imasText(.rowSubtitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.gapLoose)
            }

            ImasListSection("できること") {
                ForEach(section.body) { item in
                    HStack(alignment: .top, spacing: DS.Space.gap) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(t.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                            Text(item.label).imasText(.rowTitle)
                            Text(item.detail).imasText(.rowSubtitle)
                        }
                    }
                    .padding(.vertical, DS.Space.gapTight)
                }
            }
        }
        .listStyle(.plain)
        .imasForm()
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HelpView()
}
