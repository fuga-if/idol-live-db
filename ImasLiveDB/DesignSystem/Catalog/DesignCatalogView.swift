#if DEBUG
import SwiftUI

// =============================================================================
// 部品カタログ (DEBUG ビルドのみ)
//
// デザインシステムの全部品を、種類と状態ごとに実物で並べる。参照ページの見本はここを撮る。
// 部品を足したらここにも足す (docs/DESIGN_SYSTEM.md §15)。
// =============================================================================

enum DesignCatalogPage: String, CaseIterable, Identifiable {
    case venue, venueRows, application, buttons, chips, rows, rows2, sections, heroSong, heroIdol, heroIdolColor, hub, hubColor,
         feedback, setlist, list, form, setup, community, chat, stage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .venue: return "会場の部品 (チケット・掲示板・印)"
        case .venueRows: return "半券の行・入場証・名札"
        case .application: return "申込書 (編集シートの欄)"
        case .buttons: return "ボタン"
        case .chips: return "チップ・札・数字"
        case .rows: return "行 (実体)"
        case .rows2: return "行 (項目・入口・選択)"
        case .sections: return "区画・面・お知らせ"
        case .heroSong: return "詳細の頭 (曲)"
        case .heroIdol: return "詳細の頭 (アイドル)"
        case .heroIdolColor: return "詳細の頭 (アイドル・色の面)"
        case .hub: return "ハブ"
        case .hubColor: return "ハブ (担当を色の面で)"
        case .feedback: return "状態・メーター"
        case .setlist: return "セトリと予想"
        case .list: return "一覧の型"
        case .form: return "編集シートの型"
        case .setup: return "ゲームの設定・読みもの"
        case .community: return "コミュニティ (タグ・記録)"
        case .chat: return "AI チャット"
        case .stage: return "あそぶ (ステージ)"
        }
    }
}

/// カタログの目次。設定の「開発」から開く。
struct DesignCatalogIndexView: View {
    var body: some View {
        List(DesignCatalogPage.allCases) { page in
            NavigationLink(page.title) { DesignCatalogPageView(page: page) }
        }
        .navigationTitle("部品カタログ")
    }
}

struct DesignCatalogPageView: View {
    let page: DesignCatalogPage

    var body: some View {
        Group {
            switch page {
            case .venue: VenuePage()
            case .venueRows: VenueRowsPage()
            case .application: ApplicationFormPage()
            case .buttons: ButtonsPage()
            case .chips: ChipsPage()
            case .rows: EntityRowsPage()
            case .rows2: ValueRowsPage()
            case .sections: SectionsPage()
            case .heroSong: SongHeroPage()
            case .heroIdol: IdolHeroPage(surface: .paper)
            case .heroIdolColor: IdolHeroPage(surface: .color)
            case .hub: HubPage(oshiSurface: .panel)
            case .hubColor: HubPage(oshiSurface: .color)
            case .feedback: FeedbackPage()
            case .setlist: SetlistPage()
            case .list: ListTemplatePage()
            case .form: FormTemplatePage()
            case .setup: SetupPage()
            case .community: CommunityPage()
            case .chat: ChatPage()
            case .stage: StagePage()
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        // 見本を撮るとき、ページの途中・下を出す (DS_SCROLL=center / bottom)。
        .defaultScrollAnchor(Self.scrollAnchor)
    }

    private static var scrollAnchor: UnitPoint? {
        switch ProcessInfo.processInfo.environment["DS_SCROLL"] {
        case "bottom": return .bottom
        case "center": return .center
        default: return nil
        }
    }
}

// MARK: - 見本の色

private enum Sample {
    static let haruka = "#E22B30"
    static let chihaya = "#2743D2"
    static let miki = "#B4E04B"
    static let makoto = "#515558"
    static let yayoi = "#F39939"
    static let kanade = "#0D386D"
    static let saki = "#EA4A5B"
    static let shizuka = "#6495CF"
    static let kotoha = "#92CFBB"
    static let as765 = "#f34f6d"
    static let cg = "#2681c8"
    static let ml = "#ffc30b"
    static let gakuen = "#f39800"

    /// 見本のユニット (`ImasUnitAvatar`・`ImasUnitCell`・`ImasForecastRow(unit:)`)。
    static let unit = Unit(id: "sample-765as", brandId: "765as", name: "765PRO ALLSTARS",
                           isPermanent: true, nameAlt: nil, nameKana: nil)

    /// 見本のジャケ (実際の配信の画像)。
    enum Art {
        private static func url(_ s: String) -> URL? { URL(string: "https://is1-ssl.mzstatic.com/image/thumb/\(s)/600x600bb.jpg") }
        static let idolmaster = url("Music116/v4/2c/67/8d/2c678df3-f929-6bad-8c66-bef3c669c7e8/4540774158782.jpg")
        static let ready = url("Music122/v4/9e/37/0b/9e370bf4-b073-c6f9-18b1-dc4c6a4160e6/COCX-38070.jpg")
        static let jealousy = url("Music116/v4/96/80/64/96806435-086e-04ad-f2ad-eed5cf9db9ed/PA00114560_0_162943_jacket.jpg")
        static let thankYou = url("Music126/v4/ec/bc/da/ecbcdafa-f3cb-f967-6b96-e75ee8272493/4540774250431.jpg")
        static let onegai = url("Music124/v4/c0/0c/9a/c00c9ad7-b952-dd1d-4bc9-d38f9f343ccd/COCC_16718.jpg")
        static let shirube = url("Music211/v4/d2/d0/d1/d2d0d166-6d01-5ba1-1bb3-ac7afe4f04a6/PA00185909_0_222005_jacket.jpg")
        static let fightingMyWay = url("Music221/v4/33/4e/9c/334e9c4b-6ae8-55b2-7d1f-e6ab30fb2d9b/PA00153099_0_191075_jacket.jpg")
        static let hajime = url("Music211/v4/e5/ca/75/e5ca7591-dac2-60fa-348c-4a850f219c68/PA00153098_0_191078_jacket.jpg")
    }
}

// MARK: - 会場の部品

private struct VenuePage: View {
    @State private var pick = true
    @State private var favorite = false

    var body: some View {
        ImasPage {
            ImasSection("頭の印字", style: .small) {
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    ImasMasthead("PRODUCE", "2026.10.01 THU")
                    Text("プロデュース").font(.imasHeading(34, weight: .heavy)).foregroundStyle(DS.ink)
                }
            }
            ImasSection("チケット", style: .small, footer: "次のライブ・次の出演。右の半券にカウントダウン。紙はダークでも明るい。") {
                VStack(spacing: DS.Space.gapLoose) {
                    ImasTicket(label: "参加予定",
                               title: "学園アイドルマスター LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)",
                               metaImprint: "11.07 SAT", meta: "DAY1 · Kアリーナ横浜",
                               brand: Sample.gakuen,
                               countdown: .init(value: "37"))
                    ImasTicket(label: "次の出演", imprint: "NEXT STAGE",
                               title: "765 PRODUCTION × 961 PRODUCTION IDOL ULTIMATE ONCE AND FOR ALL",
                               metaImprint: "2027.07.25 SUN", meta: "第三公演 · 京王アリーナ TOKYO",
                               seed: Sample.haruka,
                               countdown: .init(value: "297"))
                    ImasTicket(label: "DAY2", imprint: "09.23 WED",
                               title: "学園アイドルマスター LIVE TOUR -標- 岩手公演",
                               brand: Sample.gakuen)
                }
            }
            ImasSection("電光掲示板", style: .small, footer: "記録や出演の数。ライトでもダークでも板は暗い。") {
                ImasBoard(title: "STATS", trailing: "2005 — 2026", cells: [
                    .init(value: "189", unit: "公演", label: "出演"),
                    .init(value: "42", unit: "曲", label: "歌唱した曲"),
                    .init(value: "12", unit: "公演", label: "一緒に参加"),
                ])
            }
            ImasSection("料金表", style: .small, footer: "電光掲示板と同じ暗い板。価格帯は内訳行を少し下げて小さく添える。") {
                ImasPriceList(title: "TICKET", rows: [
                    .init(id: "general", label: "一般 指定席", amount: "¥9,800"),
                    .init(id: "premium", label: "プレミアム席", amount: "¥15,800", note: "特典付き"),
                    .init(id: "stream", label: "ライブ・ビューイング", amount: "¥5,500〜¥13,200"),
                    .init(id: "stream-sub", label: "会場による内訳あり", amount: "推定含む", indented: true),
                ])
            }
            ImasSection("印", style: .small, footer: "担当・お気に入り・メモは丸いパンチ。押すと実体の色で点く。操作 (出演ライブ) は墨の丸。") {
                ImasMarkBar {
                    ImasMarkTile(systemImage: "heart.fill", label: "担当", isOn: pick) { pick.toggle() }
                    ImasMarkTile(systemImage: favorite ? "star.fill" : "star", label: "お気に入り", isOn: favorite) { favorite.toggle() }
                    ImasMarkTile(systemImage: "note.text", label: "メモ", isOn: false) {}
                    ImasMarkTile(systemImage: "music.mic", label: "出演ライブ", isOn: false, isAction: true) {}
                }
                .imasTheme(seed: Sample.haruka)
            }
            ImasSection("切り取り線", style: .small) {
                ImasPerforation()
            }
        }
    }
}

// MARK: - 半券の行・入場証・名札

private struct VenueRowsPage: View {
    @State private var pick = true
    @State private var brands: Set<String> = ["765as", "gakuen"]

    private let brandOptions: [ImasBrandPicker.Option] = [
        .init(id: "765as", label: "765", color: Sample.as765),
        .init(id: "cg", label: "シンデレラ", color: Sample.cg),
        .init(id: "ml", label: "ミリオン", color: Sample.ml),
        .init(id: "sidem", label: "SideM", color: "#0fbe94"),
        .init(id: "sc", label: "シャニ", color: "#8dbbff"),
        .init(id: "gakuen", label: "学マス", color: Sample.gakuen),
    ]

    var body: some View {
        ImasPage {
            ImasSection("半券の行", style: .small, footer: "ライブ・公演・記録の一覧。参加・参加予定は事実の札で出す。右に引くと参加予定にできる。") {
                VStack(spacing: DS.Space.gap) {
                    ImasStubRow(date: ImasStubDate("2026-11-07"),
                                title: "学園アイドルマスター LIVE TOUR -標- Kアリーナ横浜公演 (FINAL) DAY1",
                                subtitle: "Kアリーナ横浜 · 17:00", brand: Sample.gakuen,
                                badges: [.init(text: "参加予定", kind: .planned)])
                    ImasStubRow(date: ImasStubDate("2026-10-28"), title: "灯里愛夏 BIRTHDAY ONLINE LIVE 2026",
                                subtitle: "配信 · ASOBI STAGE", brand: "#656a75",
                                badges: [.init(text: "配信", kind: .neutral)])
                    ImasStubRow(date: ImasStubDate("2026-09-23"), title: "学園アイドルマスター LIVE TOUR -標- 岩手公演 DAY2",
                                subtitle: "トーサイクラシックホール岩手", brand: Sample.gakuen,
                                badges: [.init(text: "参加", kind: .positive)])
                    ImasStubRow(date: ImasStubDate("2024-08"), title: "日付が月までの公演", subtitle: "会場未定")
                    ImasStubRow(date: ImasStubDate("2025-12-13"), title: "765PRO ALLSTARS × CINDERELLA GIRLS 合同ライブ",
                                subtitle: "京セラドーム大阪", badges: [.init(text: "合同", kind: .unit)], rainbow: true)
                    ImasStubRow(date: ImasStubDate("2026-11-28"), title: "絞り込み結果から開いた公演",
                                subtitle: "Kアリーナ横浜", brand: Sample.cg, showsChevron: true)
                }
            }
            ImasSection("半券の形の短い行", style: .small) {
                VStack(spacing: DS.Space.gap) {
                    ImasTicketRow(title: "アソビストア一般会員先行", subtitle: "抽選 · 受付中 · 当落 10.31 13:00", deadline: "10.19")
                    ImasTicketRow(title: "SideM PRODUCER MEETING", subtitle: "プレミアム会員先行 · 締切", deadline: "23:59", isUrgent: true)
                    ImasTicketRow(title: "チケット代が未記録の公演が 3 件", subtitle: "過去の参加から取り込む") {}
                }
            }
            ImasSection("入場証", style: .small) {
                VStack(spacing: DS.Space.gapLoose) {
                    ImasPass(leftImprint: "PRODUCER PASS", rightImprint: "担当", title: "花海咲季",
                             subtitle: "学マス · CV 長月あおい", seed: Sample.saki) {
                        ImasPassStats(items: [("12", "回収"), ("4", "参加")])
                    }
                    ImasPass(leftImprint: "ACCOUNT", rightImprint: "ログイン中", title: "fuga",
                             subtitle: "コミュニティで表示される名前", onOpen: {})
                }
            }
            ImasSection("チケットの束", style: .small, footer: "横に払うと次のチケットが上に来る。") {
                ImasTicketStack(items: [
                    .init(id: "1", ticket: ImasTicket(label: "参加予定", title: "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL) DAY1",
                                                      metaImprint: "11.07 SAT", meta: "Kアリーナ横浜 · 17:00",
                                                      brand: Sample.gakuen, countdown: .init(value: "37")),
                          edge: "11.07 SAT · 標 FINAL DAY1 · 37 DAYS"),
                    .init(id: "2", ticket: ImasTicket(label: "参加予定", title: "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL) DAY2",
                                                      metaImprint: "11.08 SUN", meta: "Kアリーナ横浜 · 17:00",
                                                      brand: Sample.gakuen, countdown: .init(value: "38")),
                          edge: "11.08 SUN · 標 FINAL DAY2 · 38 DAYS"),
                    .init(id: "3", ticket: ImasTicket(label: "参加予定", title: "CINDERELLA GIRLS 15th ANNIVERSARY PARTY!!!! DAY1",
                                                      metaImprint: "11.28 SAT", meta: "Kアリーナ横浜 · 17:00",
                                                      brand: Sample.cg, countdown: .init(value: "58")),
                          edge: "11.28 SAT · CG 15th ANNIVERSARY PARTY!!!! · 58 DAYS"),
                ])
            }
            ImasSection("アイドル詳細の頭", style: .small) {
                ImasIdolHeader(imprint: "765PRO ALLSTARS", onImprintTap: {}, name: "天海春香",
                               subtitle: "あまみ はるか · CV 中村繪里子", seed: Sample.haruka, iconLabel: "春香", isPick: pick,
                               onTogglePick: { pick.toggle() },
                               stats: [.init(value: "189", unit: "公演", label: "出演"),
                                       .init(value: "42", unit: "曲", label: "歌唱した曲"),
                                       .init(value: "12", unit: "公演", label: "一緒に参加")]) {
                    ImasIconBadge(systemImage: "camera.fill", label: "写真を選ぶ", seed: Sample.haruka)
                }
            }
            ImasSection("アイドルの名札", style: .small) {
                ImasIdolGrid {
                    ImasIdolCell(name: "天海春香", seed: Sample.haruka, iconLabel: "春香", isPick: true, metric: "158cm")
                    ImasIdolCell(name: "如月千早", seed: Sample.chihaya, iconLabel: "千早", metric: "162cm")
                    ImasIdolCell(name: "星井美希", seed: Sample.miki, iconLabel: "美希", metric: "161cm")
                    ImasIdolCell(name: "菊地真", seed: Sample.makoto, iconLabel: "真", metric: "157cm")
                }
                ImasIdolGrid {
                    ImasIdolCell(name: "高槻やよい", kana: "たかつきやよい", seed: Sample.yayoi, iconLabel: "やよい",
                                 isSelected: true)
                    ImasIdolCell(name: "速水奏", kana: "はやみかなで", seed: Sample.kanade, iconLabel: "奏", isSelected: false)
                }
            }
            ImasSection("ブランドを選ぶ", style: .small) {
                ImasBrandPicker(options: brandOptions, selection: $brands)
            }
            ImasSection("ユニットの名札", style: .small, footer: "登録画像があれば画像、無ければブランド色 + 人数の記号 (`person.3.fill`)。") {
                HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                    ImasUnitAvatar(unit: Sample.unit, size: 52)
                    ImasUnitCell(unit: Sample.unit, metric: "タグ 3 個一致")
                        .frame(width: 120)
                }
            }
            ImasSection("日付の印", style: .small, footer: "月カレンダー・週ビューの日セル。当日=塗り、選択日(当日以外)=線。") {
                HStack(spacing: DS.Space.gapLoose) {
                    VStack(spacing: 4) { ImasDateMark(isToday: true, isSelected: false); Text("7").imasText(.meta) }
                    VStack(spacing: 4) { ImasDateMark(isToday: false, isSelected: true); Text("12").imasText(.meta) }
                    VStack(spacing: 4) { ImasDateMark(isToday: false, isSelected: false); Text("20").imasText(.meta) }
                }
            }
            ImasSection("写真の角の印", style: .small, footer: "写真サムネイルの角の小さな印。地の色に関わらず読めるよう半透明の黒 + 白。") {
                HStack(spacing: DS.Space.gapLoose) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: DS.rArtwork(72), style: .continuous).fill(DS.fill)
                            .frame(width: 72, height: 72)
                        ImasMediaBadge(systemImage: "star.fill", accessibilityLabel: "アイコンに設定中")
                    }
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: DS.rArtwork(72), style: .continuous).fill(DS.fill)
                            .frame(width: 72, height: 72)
                        ImasMediaBadge(systemImage: "eye.slash", label: "対象外")
                    }
                }
            }
        }
    }
}

// MARK: - 申込書

private struct ApplicationFormPage: View {
    enum How: Hashable { case venue, stream, viewing }
    enum Mode: Hashable { case normal, hard, endless }
    @State private var how: How = .venue
    @State private var mode: Mode = .normal
    @State private var questionCount = 20
    @State private var seat = "1階 C列 24番"
    @State private var price: Int? = 9900
    @State private var notify = true
    @State private var memo = ""
    @State private var reply = ""
    @State private var url = "htps://example"
    @State private var tagText = ""
    @State private var tags = ["ソロ曲好き", "初参戦"]

    var body: some View {
        ImasFormPage {
            ImasTicket(label: "DAY2", imprint: "09.23 WED",
                       title: "学園アイドルマスター LIVE TOUR -標- 岩手公演",
                       brand: Sample.gakuen)
            ImasSection("参加のしかた (横に並ぶ札: grid)", style: .small) {
                ImasChoiceCards(choices: [
                    .init(value: How.venue, title: "現地", systemImage: "chair"),
                    .init(value: How.stream, title: "配信", systemImage: "dot.radiowaves.left.and.right"),
                    .init(value: How.viewing, title: "LV", systemImage: "film"),
                ], selection: $how)
            }
            ImasSection("遊び方 (縦に積む行: row)", style: .small) {
                ImasChoiceCards(choices: [
                    .init(value: Mode.normal, title: "ノーマル", systemImage: "music.note", subtitle: "よく流れる曲だけ出題"),
                    .init(value: Mode.hard, title: "ハード", systemImage: "music.note.list", subtitle: "登録曲すべてから出題"),
                    .init(value: Mode.endless, title: "エンドレス", systemImage: "infinity", subtitle: "正解し続ける限り続く"),
                ], selection: $mode, style: .row)
            }
            ImasSection("問題数 (数字だけの札: numeral)", style: .small) {
                ImasChoiceCards(choices: [
                    .init(value: 10, title: "10", subtitle: "問"),
                    .init(value: 20, title: "20", subtitle: "問"),
                    .init(value: 30, title: "30", subtitle: "問"),
                ], selection: $questionCount, style: .numeral)
            }
            ImasFormCard {
                ImasFormTextField(label: "席", imprint: "SEAT", systemImage: "chair", text: $seat)
                ImasFormAmount(label: "チケット代", amount: $price, note: "一般 指定席")
                ImasFormLink(label: "会場", imprint: "VENUE", systemImage: "mappin", value: "トーサイクラシックホール岩手") {}
                ImasFormTextField(label: "特設ページ", imprint: "URL", systemImage: "link", text: $url,
                                  error: "URL の形になっていません", keyboard: .URL)
                ImasFormToggle(label: "通知", imprint: "NOTIFY", systemImage: "bell", title: "開演 1 時間前に知らせる", isOn: $notify)
                ImasFormTextArea(label: "メモ", text: $memo, prompt: "座席・同行者・感想など")
            }
            ImasSection("返信 (開いたら自動でキーボードを出す: autofocus)", style: .small) {
                ImasFormCard {
                    ImasFormTextArea(label: "返信", imprint: "REPLY", systemImage: "arrowshape.turn.up.left",
                                      text: $reply, prompt: "コメントへの返信", autofocus: true)
                }
            }
            ImasSection("マイタグ", style: .small, footer: "押すと増える、手元だけのタグ。") {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    ImasChipFlow {
                        ForEach(tags, id: \.self) { tag in
                            ImasRemovableChip(text: tag) { tags.removeAll { $0 == tag } }
                        }
                    }
                    ImasChipInputField(text: $tagText, prompt: "マイタグを追加", submitAccessibilityLabel: "マイタグを追加") {
                        guard !tagText.isEmpty else { return }
                        tags.append(tagText)
                        tagText = ""
                    }
                }
            }
            ImasNote("チケット代は収支に入ります。この端末にだけ保存されます。")
            ImasButton(title: "この記録を削除", systemImage: "trash", role: .destructive, size: .large) {}
        }
    }
}

// MARK: - ボタン

private struct ButtonsPage: View {
    var body: some View {
        ImasPage {
            ImasSection("主ボタン (大)", style: .small, footer: "画面で一番大事な操作。1 画面に 1 つ。色は墨で、アイドルの画面でも変えない。") {
                VStack(spacing: DS.Space.gap) {
                    ImasButton(title: "はじめる", size: .large) {}
                    ImasButton(title: "セトリを予想", systemImage: "sparkles", size: .large) {}
                        .imasTheme(seed: nil, brand: Sample.gakuen)
                }
            }
            ImasSection("役割", style: .small) {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    HStack(spacing: DS.Space.gap) {
                        ImasButton(title: "主", role: .primary) {}
                        ImasButton(title: "副", role: .secondary) {}
                        ImasButton(title: "文字", role: .plain) {}
                        ImasButton(title: "削除", role: .destructive) {}
                    }
                    HStack(spacing: DS.Space.gap) {
                        ImasButton(title: "主", role: .primary) {}
                        ImasButton(title: "副", role: .secondary) {}
                        ImasButton(title: "文字", role: .plain) {}
                        ImasButton(title: "削除", role: .destructive) {}
                    }
                    .imasTheme(seed: Sample.haruka)
                }
            }
            ImasSection("大きさ", style: .small) {
                HStack(spacing: DS.Space.gap) {
                    ImasButton(title: "大 50", size: .large, fillsWidth: false) {}
                    ImasButton(title: "中 40", size: .medium) {}
                    ImasButton(title: "小 32", size: .small) {}
                }
                .imasTheme(seed: Sample.chihaya)
            }
            ImasSection("状態", style: .small) {
                HStack(spacing: DS.Space.gap) {
                    ImasButton(title: "保存", role: .primary) {}.disabled(true)
                    ImasButton(title: "送信", role: .primary, isLoading: true) {}
                    ImasButton(title: "予想する", systemImage: "hand.thumbsup", role: .secondary, size: .small) {}
                }
                .imasTheme(seed: Sample.saki)
            }
            ImasSection("記号のボタン", style: .small) {
                HStack(spacing: DS.Space.gapLoose) {
                    ImasIconButton(systemImage: "chevron.left", label: "前の月", size: .regular) {}
                    ImasIconButton(systemImage: "chevron.right", label: "次の月", size: .small) {}
                    ImasIconButton(systemImage: "play.fill", label: "再生", style: .filled) {}
                        .imasTheme(seed: Sample.haruka)
                    ImasIconButton(systemImage: "ellipsis", label: "その他", style: .plain) {}
                    ImasIconButton(systemImage: "trash", label: "削除中", style: .filled, isLoading: true) {}
                }
            }
        }
    }
}

// MARK: - チップ・札・数字

private struct ChipsPage: View {
    @State private var brand = "765as"
    @State private var picked: Set<String> = ["haruka", "miki"]

    var body: some View {
        ImasPage {
            ImasSection("絞り込み (押すと切り替わる)", style: .small) {
                ImasChipFlow {
                    ImasFilterChip(text: "すべて", isSelected: brand == "all") { brand = "all" }
                    ImasFilterChip(text: "765AS", isSelected: brand == "765as", brand: Sample.as765, leading: .dot) { brand = "765as" }
                    ImasFilterChip(text: "デレマス", isSelected: brand == "cg", brand: Sample.cg, leading: .dot) { brand = "cg" }
                    ImasFilterChip(text: "ミリオン", isSelected: brand == "ml", brand: Sample.ml, leading: .dot) { brand = "ml" }
                    ImasFilterChip(text: "学マス", isSelected: brand == "gakuen", brand: Sample.gakuen, leading: .dot) { brand = "gakuen" }
                }
            }
            ImasSection("歌唱メンバーの予想 (写真が無ければ判子)", style: .small) {
                ImasChipFlow {
                    ForEach([("haruka", "天海春香", "春香", Sample.haruka), ("chihaya", "如月千早", "千早", Sample.chihaya),
                             ("miki", "星井美希", "美希", Sample.miki), ("makoto", "菊地真", "真", Sample.makoto),
                             ("yayoi", "高槻やよい", "やよい", Sample.yayoi)], id: \.0) { id, name, short, color in
                        ImasFilterChip(text: name, isSelected: picked.contains(id), seed: color,
                                       leading: .avatar(label: short)) {
                            if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
                        }
                    }
                }
            }
            ImasSection("効いている絞り込み・情報の札", style: .small) {
                ImasChipFlow {
                    ImasRemovableChip(text: "765AS", brand: Sample.as765) {}
                    ImasRemovableChip(text: "ソロ曲") {}
                    ImasChip(text: "全体曲")
                    ImasChip(text: "765AS", style: .themed, brand: Sample.as765)
                    ImasAwardChip(title: "夏に聴きたい曲", rank: 1)
                }
            }
            ImasSection("状態の札 (押せない)", style: .small) {
                ImasChipFlow {
                    ImasBadge(text: "ユニット", kind: .unit, seed: Sample.chihaya)
                    ImasBadge(text: "全員", kind: .all)
                    ImasBadge(text: "カバー", kind: .cover)
                    ImasBadge(text: "一部", kind: .partial)
                    ImasBadge(text: "主演", kind: .lead, seed: Sample.haruka)
                    ImasBadge(text: "ゲスト", kind: .guest)
                    ImasBadge(text: "参加済", kind: .positive, systemImage: "checkmark")
                    ImasBadge(text: "受付中", kind: .attention)
                    ImasBadge(text: "落選", kind: .negative)
                    ImasBadge(text: "LV", kind: .neutral)
                    ImasBadge(text: "NEW", kind: .new, seed: Sample.saki)
                    ImasBadge(text: "12", kind: .themed, systemImage: "tag.fill", brand: Sample.ml)
                }
            }
            ImasSection("数字", style: .small, footer: "`.micro` (8pt) は枠の高さが決まっていて文字を詰め込むしかない場所専用 (月カレンダーの単日バー・あふれ件数など)。") {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    ImasMetric(value: "89", unit: "回", size: .large)
                    ImasMetric(value: "42", unit: "%", size: .medium, emphasized: true).imasTheme(seed: Sample.haruka)
                    ImasMetric(value: "2,051", unit: "件", size: .small)
                    Text("+12").imasText(.micro)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 14)
                        .background(DS.fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            ImasSection("1 段で横スクロール (続きは端を透かす: fades)", style: .small) {
                ImasChipRow(fades: true) {
                    ForEach(["すべて", "765AS", "シンデレラ", "ミリオン", "SideM", "シャニ", "学マス", "ALSTREAM", "シャッフル"], id: \.self) { text in
                        ImasFilterChip(text: text, isSelected: text == "すべて") {}
                    }
                }
            }
        }
    }
}

// MARK: - 行 (実体)

private struct EntityRowsPage: View {
    var body: some View {
        ImasPage {
            ImasSection("曲", count: "3曲", style: .large) {
                ImasCardList(style: .plain) {
                    ImasRow(title: "THE IDOLM@STER", subtitle: "765PRO ALLSTARS",
                            leading: .artwork(title: "THE IDOLM@STER", brand: Sample.as765, imageURL: Sample.Art.idolmaster),
                            trailing: .metric("89", unit: "回", emphasized: true)) {
                        HStack(spacing: DS.Space.gapTight) {
                            Text("2005年7月26日").imasText(.meta)
                            ImasBadge(text: "回収 3", kind: .positive, systemImage: "checkmark")
                        }
                    }
                    ImasRow(title: "Thank You!", subtitle: "MILLIONSTARS",
                            leading: .artwork(title: "Thank You!", brand: Sample.ml, imageURL: Sample.Art.thankYou),
                            trailing: .metric("74", unit: "回", emphasized: true))
                        .environment(\.imasRowPosition, .following)
                    ImasRow(title: "お願い！シンデレラ", subtitle: "CINDERELLA GIRLS",
                            leading: .artwork(title: "お願い！シンデレラ", brand: Sample.cg, imageURL: Sample.Art.onegai),
                            trailing: .metric("120", unit: "回", emphasized: true))
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("アイドル", style: .large) {
                ImasCardList(style: .plain) {
                    ImasRow(title: "天海春香", subtitle: "765AS · CV 中村繪里子",
                            leading: .avatar(label: "春香", seed: Sample.haruka, isPick: true),
                            trailing: .badge(ImasBadge(text: "担当", kind: .lead)))
                    ImasRow(title: "如月千早", subtitle: "765AS · CV 今井麻美",
                            leading: .avatar(label: "千早", seed: Sample.chihaya))
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("歌唱者のアイコン", style: .small, footer: "写真があれば写真、無ければ判子。入り切らない人数は +N。") {
                ImasAvatarStack(people: [.init(id: "a", name: "天海春香", color: Sample.haruka, iconLabel: "春香"),
                                         .init(id: "b", name: "如月千早", color: Sample.chihaya, iconLabel: "千早"),
                                         .init(id: "c", name: "星井美希", color: Sample.miki, iconLabel: "美希"),
                                         .init(id: "d", name: "菊地真", color: Sample.makoto, iconLabel: "真"),
                                         .init(id: "e", name: "高槻やよい", color: Sample.yayoi, iconLabel: "やよい"),
                                         .init(id: "f", name: "萩原雪歩", color: "#D3DDE9", iconLabel: "雪歩")],
                                maxVisible: 4, size: 26)
            }
            ImasSection("ライブ・公演", style: .large) {
                ImasCardList(style: .plain) {
                    ImasRow(title: "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)", subtitle: "11月7日(土)〜8日(日) · Kアリーナ横浜",
                            leading: .bar(brand: Sample.gakuen), trailing: .chevron) {
                        ImasBadge(text: "参加予定", kind: .attention)
                    }
                    ImasRow(title: "M@STERS OF IDOL WORLD 2025", subtitle: "2025年12月13日(土)〜14日(日) · 京セラドーム大阪",
                            leading: .bar(rainbow: true), trailing: .chevron, emphasis: .dimmed)
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("ジャケの格子 (アルバム・シリーズ)", style: .small) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.gap), count: 3), spacing: DS.Space.gapLoose) {
                    ImasArtworkCell(title: "THE IDOLM@STER", subtitle: "2005年7月26日", brand: Sample.as765, imageURL: Sample.Art.idolmaster)
                    ImasArtworkCell(title: "READY!!", subtitle: "2008年2月27日", brand: Sample.as765, imageURL: Sample.Art.ready)
                    ImasArtworkCell(title: "ジャケ未登録のシリーズ", brand: Sample.ml, fallbackSystemImage: "square.stack")
                }
            }
            ImasSection("記録 (編集履歴・お知らせ)", style: .small, footer: "先頭は種類ごとの記号 (地は敷かない)。自由な中身 (diff 本文など) は detail で足す。") {
                ImasCardList {
                    ImasRecordRow(systemImage: "pencil", tone: .themed, title: "「THE IDOLM@STER」の歌唱者を直した",
                                  subtitle: "よ〜だ · 3分前", badges: [.init(text: "変更", kind: .neutral)]) {
                        Text("歌唱者: 5人 → 6人").imasText(.note)
                    }
                    ImasRecordRow(systemImage: "arrow.uturn.backward", tone: .negative, title: "「お願い！シンデレラ」の追加を差し戻した",
                                  subtitle: "fuga · 1時間前", badges: [.init(text: "差し戻し", kind: .negative)])
                        .environment(\.imasRowPosition, .following)
                    ImasRecordRow(leading: .avatar(label: "春香", seed: Sample.haruka),
                                  title: "天海春香のプロフィールが直された", subtitle: "よ〜だ · 昨日",
                                  badges: [.init(text: "変更", kind: .neutral)])
                        .environment(\.imasRowPosition, .following)
                }
            }
        }
    }
}

// MARK: - 行 (項目・入口・選択)

private struct ValueRowsPage: View {
    @State private var notify = true
    @State private var selected: Set<Int> = [0]
    @State private var scope = "現地のみ"
    @State private var count = 10
    @State private var pick = true
    @State private var favorite = false
    @State private var owned = true
    @State private var query = ""
    @State private var expanded = true

    var body: some View {
        ImasPage {
            ImasSection("選ぶ・設定する行", style: .small, footer: "選べる行は行のどこを押しても切り替わる。値を選ぶ行はその場にメニューが出る。") {
                ImasCardList {
                    ImasSelectableRow(title: "天海春香", subtitle: "765PRO ALLSTARS", isSelected: selected.contains(0), seed: Sample.haruka) {
                        if !selected.insert(0).inserted { selected.remove(0) }
                    }
                    ImasSelectableRow(title: "READY!!", leading: .artwork(title: "READY!!", imageURL: Sample.Art.ready),
                                      isSelected: selected.contains(1)) {
                        if !selected.insert(1).inserted { selected.remove(1) }
                    }
                    .environment(\.imasRowPosition, .following)
                    ImasMenuRow(title: "回収に数える", systemImage: "checkmark.seal", options: ["現地のみ", "現地と配信"],
                                selection: $scope) { $0 }
                        .environment(\.imasRowPosition, .following)
                    ImasStepperRow(title: "問題数", systemImage: "number", value: $count, range: 5...30, step: 5, unit: "問")
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("行の末尾の印", style: .small) {
                ImasCardList {
                    ImasRow(title: "天海春香", subtitle: "あまみ はるか", leading: .avatar(label: "春香", seed: Sample.haruka),
                            trailing: .mark(.pick, isOn: pick) { pick.toggle() })
                    ImasRow(title: "READY!!", leading: .artwork(title: "READY!!", imageURL: Sample.Art.ready),
                            trailing: .mark(.favorite, isOn: favorite) { favorite.toggle() })
                        .environment(\.imasRowPosition, .following)
                    ImasRow(title: "KAMISABI SR 「THE IDOLM@STER」", leading: .icon("rectangle.stack", tone: .themed),
                            trailing: .mark(.owned, isOn: owned) { owned.toggle() })
                        .environment(\.imasRowPosition, .following)
                }
                .imasTheme(seed: Sample.haruka)
            }
            ImasSection("開閉トグルの行", style: .small, footer: "押すたびに chevron が回転する。中身の開閉は呼び出し側が isExpanded を見て出し分ける。") {
                ImasCardList {
                    ImasDisclosureRow(title: "個別衣装", count: "4着", isExpanded: $expanded)
                    if expanded {
                        ImasChipFlow {
                            ImasChip(text: "制服")
                            ImasChip(text: "ライブ衣装")
                            ImasChip(text: "私服")
                            ImasChip(text: "サンタ衣装")
                        }
                        .padding(.horizontal, DS.Space.rowH)
                        .padding(.bottom, DS.Space.gap)
                        .environment(\.imasRowPosition, .following)
                    }
                }
            }
            ImasSection("一覧の頭", style: .small) {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    HStack(spacing: DS.Space.gap) {
                        ImasToolbarButton(systemImage: "gearshape", label: "設定") {}
                        ImasSearchField(prompt: "曲名・歌詞・アイドル", text: $query)
                        ImasToolbarButton(systemImage: "line.3.horizontal.decrease.circle.fill", label: "絞り込み", badge: 2) {}
                    }
                    ImasDateHeader(big: "11", imprint: "NOV 2026 · 4 公演")
                    ImasDateHeader(big: "09", imprint: "SEP 2026 · 終わった", isPast: true)
                }
            }
            ImasSection("項目と値", style: .small) {
                ImasCardList {
                    ImasValueRow(key: "よみ", value: "あいどるますたー")
                    ImasValueRow(key: "ブランド", value: "765AS", isLink: true)
                        .environment(\.imasRowPosition, .following)
                    ImasValueRow(key: "キャパ", value: "55,000人", monospaced: true)
                        .environment(\.imasRowPosition, .following)
                }
                .imasTheme(seed: nil, brand: Sample.as765)
            }
            ImasSection("入口・設定", style: .small) {
                ImasCardList {
                    ImasNavRow(title: "デフォルトブランド", systemImage: "square.grid.2x2", value: "すべて")
                    ImasNavRow(title: "使い方を見る", systemImage: "questionmark.circle")
                        .environment(\.imasRowPosition, .following)
                    ImasToggleRow(title: "ライブ名を省略表示", subtitle: "「THE IDOLM@STER」を省いて短く出す", isOn: $notify)
                        .environment(\.imasRowPosition, .following)
                    ImasActionRow(title: "曲を追加", systemImage: "plus") {}
                        .environment(\.imasRowPosition, .following)
                    ImasActionRow(title: "このライブを削除", kind: .destructive) {}
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("選ぶ (複数・1 つ)", style: .small) {
                ImasCardList {
                    ForEach(0..<3) { i in
                        Button {
                            if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                        } label: {
                            ImasRow(title: ["天海春香", "如月千早", "星井美希"][i],
                                    leading: .selection(selected.contains(i)), density: .compact)
                        }
                        .buttonStyle(.imasRow)
                        .environment(\.imasRowPosition, i == 0 ? .first : .following)
                    }
                    ImasRow(title: "京セラドーム大阪", subtitle: "大阪府", leading: .selection(true, single: true), density: .compact)
                        .environment(\.imasRowPosition, .following)
                }
            }
        }
    }
}

// MARK: - 区画・面・お知らせ

private struct SectionsPage: View {
    var body: some View {
        ImasPage {
            ImasSection("区画の見出し (大)", count: "42曲", seeAll: {}) {
                ImasCard { Text("カードの中身。行でない中身 (説明・グラフ・プレビュー) を 1 枚にまとめる。").imasText(.body) }
            }
            ImasSection("区画の見出し (文脈アクション)", actionTitle: "＋ タグ", actionSystemImage: "plus", onAction: {}) {
                ImasCard { Text("「すべて見る」(別画面へ) とは見え方が違う。その場で何かを始める操作のときに使い、同時には出さない。").imasText(.body) }
            }
            ImasSection("区画の見出し (小)", style: .small, footer: "補足文は区画の下に灰色で置き、囲まない。") {
                ImasCard {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        Text("次の出演").imasText(.eyebrow)
                        Text("15th ANNIVERSARY PARTY!!!! ~ for your ONE ~").imasText(.cardTitle)
                        ImasCard(style: .inset) { Text("カードの中の囲み (inset)").imasText(.note) }
                    }
                }
            }
            ImasSection("行のまとまり (面)", style: .small) {
                ImasCardList {
                    ImasNavRow(title: "クイズ・ゲーム", systemImage: "gamecontroller")
                    ImasNavRow(title: "みんなの投票", systemImage: "chart.bar.doc.horizontal")
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("お知らせの帯", style: .small) {
                VStack(spacing: DS.Space.gap) {
                    ImasNotice(kind: .warning, title: "候補が足りません", message: "出題に必要な 10 曲に届いていません。ブランドを増やしてください。")
                    ImasNotice(kind: .error, message: "タグを読み込めませんでした。", actionTitle: "もう一度", action: {})
                    ImasNotice(kind: .success, message: "コールガイドを保存しました。")
                    ImasNotice(kind: .info, message: "5 分前時点の情報です。")
                    ImasNotice(kind: .info, message: "オフラインです。記録はこの端末に保存され、次につながったときに同期します。", systemImage: "wifi.slash")
                }
            }
            ImasSection("提案バー", style: .small, footer: "一覧の絞り込み結果から、その場限りの単発の提案を 1 本の全幅バーで出す。恒常的な入口は ImasEntryCard、読まないと困る注意は ImasNotice。") {
                VStack(spacing: DS.Space.gapTight) {
                    ImasSuggestionBar(systemImage: "sparkles", title: "この 12 曲でイントロドンを始める",
                                      detail: "12曲", style: .prominent, showsChevron: true) {}
                    ImasSuggestionBar(systemImage: "sparkles", title: "あと 4 曲必要です", style: .prominent, isEnabled: false) {}
                    ImasSuggestionBar(systemImage: "arrow.up.arrow.down", title: "披露回数順に並べ替える", style: .subtle,
                                      action: {}, onDismiss: {})
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
            }
        }
    }
}

// MARK: - 詳細の頭

private struct SongHeroPage: View {
    @State private var tab = 0
    @State private var favorite = false
    @State private var previewing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ImasHero(layout: .centered, eyebrow: "765PRO ALLSTARS", onEyebrowTap: {}, title: "THE IDOLM@STER",
                         subtitle: "天海春香 / 如月千早 / 星井美希 / 菊地真 / 高槻やよい",
                         primary: .init(title: "Apple Music で再生", systemImage: "play.fill") {}) {
                    ImasArtwork(title: "THE IDOLM@STER", size: 200, imageURL: Sample.Art.idolmaster)
                } facts: {
                    HStack(spacing: DS.Space.gapTight) {
                        ImasBadge(text: "全体曲", kind: .all)
                        ImasBadge(text: "2005年7月26日", kind: .neutral)
                    }
                }
                ImasMarkBar {
                    ImasMarkTile(systemImage: favorite ? "star.fill" : "star", label: "お気に入り", isOn: favorite) { favorite.toggle() }
                    ImasMarkTile(systemImage: "note.text", label: "メモ", isOn: false) {}
                    ImasMarkTile(systemImage: "checkmark.seal.fill", label: "習熟度", isOn: true) {}
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, DS.Space.section)
                ImasTabs(labels: ["情報・歌唱", "歌詞", "披露履歴", "コミュニティ"], selection: $tab)
                    .padding(.horizontal, DS.Space.screen)
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    ImasStatGrid(columns: 3) {
                        ImasStatTile(systemImage: "mic.fill", value: "89", unit: "回", label: "披露")
                        ImasStatTile(systemImage: "checkmark.seal.fill", value: "3", unit: "公演", label: "現地で回収", tappable: true)
                        ImasStatTile(systemImage: "calendar", value: "2005", unit: "年", label: "初披露")
                    }
                    ImasSection("ジャケの状態", style: .small, footer: "画像が無ければブランド色の面 + 曲名。previewURL を渡すと再生/停止が乗る。") {
                        HStack(spacing: DS.Space.gapLoose) {
                            ImasArtwork(title: "THE IDOLM@STER", size: 64, imageURL: Sample.Art.idolmaster)
                            ImasArtwork(title: "ジャケ未登録の曲", seed: nil, brand: Sample.ml, size: 64)
                            ImasArtwork(title: "READY!!", size: 64, imageURL: Sample.Art.ready,
                                        previewURL: URL(string: "https://example.com/preview.m4a"), isPreviewing: previewing) {
                                previewing.toggle()
                            }
                        }
                    }
                    ImasSection("最近の披露", count: "89回") {
                        ImasCardList(style: .plain) {
                            ImasRow(title: "M@STERS OF IDOL WORLD 2025", subtitle: "12月13日(土) · 京セラドーム大阪",
                                    leading: .bar(rainbow: true), trailing: .value("M24"), density: .compact)
                            ImasRow(title: "765PRO ALLSTARS LIVE 20th", subtitle: "7月26日(土) · 横浜アリーナ",
                                    leading: .bar(brand: Sample.as765), trailing: .value("M01"), density: .compact)
                                .environment(\.imasRowPosition, .following)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.card)
            }
        }
        .background(DS.paper)
        .environment(\.imasBackdrop, .paper)
        .imasTheme(seed: nil, brand: Sample.as765)
    }
}

private struct IdolHeroPage: View {
    let surface: ImasHeroSurface
    @State private var tab = 0
    @State private var pick = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ImasHero(layout: .leading, surface: surface, eyebrow: "765PRO ALLSTARS", title: "天海春香",
                         subtitle: "あまみ はるか · CV 中村繪里子",
                         primary: .init(title: "出演ライブ", systemImage: "music.mic") {}) {
                    // 写真を設定したアイドルだけアイコンが出る (見本は写真なし)。
                    EmptyView()
                }
                ImasMarkBar {
                    ImasMarkTile(systemImage: pick ? "heart.fill" : "heart", label: "担当", isOn: pick) { pick.toggle() }
                    ImasMarkTile(systemImage: "star", label: "お気に入り", isOn: false) {}
                    ImasMarkTile(systemImage: "note.text", label: "メモ", isOn: false) {}
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, surface == .color ? DS.Space.card : 0)
                .padding(.bottom, DS.Space.section)
                ImasTabs(labels: ["ライブ", "楽曲", "プロフィール", "コミュニティ"], selection: $tab)
                    .padding(.horizontal, DS.Space.screen)
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    ImasFeatureCard(eyebrow: "次の出演", title: "15th ANNIVERSARY PARTY!!!! ~ for your ONE ~",
                                    subtitle: "11月28日(土) · Kアリーナ横浜 · DAY1", seed: Sample.haruka,
                                    metric: .init(prefix: "あと", value: "58", unit: "日"), onOpen: {})
                    ImasStatGrid(columns: 3) {
                        ImasStatTile(systemImage: "music.mic", value: "189", unit: "公演", label: "出演")
                        ImasStatTile(systemImage: "music.note", value: "42", unit: "曲", label: "歌唱した曲")
                        ImasStatTile(systemImage: "person.2.fill", value: "12", unit: "公演", label: "一緒に参加", tappable: true)
                    }
                    ImasSection("ライブ歌唱曲", count: "42曲", seeAll: {}) {
                        ImasCardList(style: .plain) {
                            ImasRow(title: "THE IDOLM@STER", leading: .artwork(title: "THE IDOLM@STER", brand: Sample.as765, imageURL: Sample.Art.idolmaster),
                                    trailing: .metric("71", unit: "回", emphasized: true), density: .compact)
                            ImasRow(title: "READY!!", leading: .artwork(title: "READY!!", brand: Sample.as765, imageURL: Sample.Art.ready),
                                    trailing: .metric("56", unit: "回", emphasized: true), density: .compact)
                                .environment(\.imasRowPosition, .following)
                            ImasRow(title: "太陽のジェラシー", leading: .artwork(title: "太陽のジェラシー", brand: Sample.as765, imageURL: Sample.Art.jealousy),
                                    trailing: .metric("48", unit: "回", emphasized: true), density: .compact)
                                .environment(\.imasRowPosition, .following)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.card)
            }
        }
        .background(DS.paper)
        .environment(\.imasBackdrop, .paper)
        .imasTheme(seed: Sample.haruka)
    }
}

// MARK: - ハブ

private struct HubPage: View {
    let oshiSurface: ImasFeatureSurface

    var body: some View {
        ImasPage {
            ImasFeatureCard(eyebrow: "担当", title: "花海咲季", subtitle: "学マス · CV 長月あおい",
                            seed: Sample.saki, surface: oshiSurface, onOpen: {})
            ImasFeatureCard(eyebrow: "参加予定", title: "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)",
                            subtitle: "11月7日(土) · DAY1", brand: Sample.gakuen,
                            metric: .init(prefix: "あと", value: "37", unit: "日"),
                            primary: .init(title: "セトリを予想する", systemImage: "sparkles") {},
                            secondary: .init(title: "コールを見る", systemImage: "hands.clap") {})
            ImasFeatureCard(eyebrow: "お題", title: "お化け屋敷に一緒に行きたいアイドルは？",
                            subtitle: "42票 · 21候補", metric: .init(prefix: "あと", value: "28", unit: "日"),
                            primary: .init(title: "投票する", systemImage: "hand.thumbsup") {},
                            secondary: .init(title: "ほかのお題", systemImage: "list.bullet") {})
            ImasShortcutGroup("あそぶ") {
                ImasShortcutTile(systemImage: "play.fill", label: "つづきから", detail: "歌詞クイズ Q.02", seed: Sample.saki)
                ImasShortcutTile(systemImage: "music.note.list", label: "イントロドン", seed: Sample.saki)
                ImasShortcutTile(systemImage: "text.quote", label: "歌詞クイズ", seed: Sample.saki)
                ImasShortcutTile(systemImage: "gamecontroller", label: "すべてのゲーム", seed: Sample.saki)
            }
            ImasSection("あなたの記録") {
                ImasStatGrid(columns: 4) {
                    ImasStatTile(systemImage: "music.mic", value: "24", label: "参加ライブ", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "sparkles", value: "3", label: "予想", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "star.fill", value: "112", label: "お気に入り", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "square.and.pencil", value: "12", label: "投稿", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "chart.bar.doc.horizontal", value: "5", label: "投票", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "music.note", value: "39", label: "回収", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "chart.bar.fill", value: "18", label: "習熟度", seed: Sample.saki, tappable: true)
                    ImasStatTile(systemImage: "yensign.circle.fill", value: "¥184,300", label: "収支", seed: Sample.saki, tappable: true)
                }
            }
        }
    }
}

// MARK: - 状態・メーター

private struct FeedbackPage: View {
    var body: some View {
        ImasPage {
            ImasCard {
                ImasEmptyState(.empty, title: "まだ参加したライブがありません",
                               message: "ライブの一覧で左にスワイプすると参加を付けられます。",
                               actionTitle: "ライブを見る", action: {})
            }
            ImasCard {
                ImasEmptyState(.noResults, title: "見つかりません", message: "「春香」に合う曲はありません。",
                               actionTitle: "絞り込みを解除", action: {})
            }
            ImasSignInPrompt(message: "セトリ予想の投票にはログインが必要です")
            ImasSection("画面全体の読み込み中", style: .small) {
                HStack(spacing: DS.Space.card) {
                    ImasCard { ImasLoadingState().frame(height: 100) }
                    ImasCard { ImasLoadingState(title: "読み込み中…").frame(height: 100) }
                }
            }
            ImasSection("メーター (習熟度・進み具合)", style: .small, footer: "ImasLevelCell は段階のマス (色は呼び出し側のドメインが決める)。ImasProgressBar はラベル無しの線 (対戦の進み具合・つづきからの達成率)。") {
                ImasCard {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        HStack(spacing: 3) {
                            ForEach(0..<10, id: \.self) { i in
                                ImasLevelCell(level: UInt8(i), steps: 10) { level, steps in
                                    DS.sys.opacity(0.35 + 0.65 * Double(level) / Double(steps))
                                }
                            }
                        }
                        ImasProgressBar(fraction: 0.42, seed: Sample.saki)
                    }
                }
            }
            ImasSection("割合", style: .small) {
                ImasCard {
                    HStack(spacing: DS.Space.card) {
                        ImasProgressRing(fraction: 0.39).imasTheme(seed: Sample.kanade)
                        VStack(alignment: .leading, spacing: 0) {
                            ImasStatBar(label: "765AS", value: "7/446", percent: 1.6, brand: Sample.as765)
                            ImasStatBar(label: "ミリオン", value: "31/1,075", percent: 2.9, brand: Sample.ml)
                            ImasStatBar(label: "学マス", value: "60/125", percent: 48, brand: Sample.gakuen)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - セトリと予想

private struct SetlistPage: View {
    @State private var voted: Set<Int> = [1]
    @State private var previewingSetlist = false

    var body: some View {
        ImasPage {
            ImasSection("セトリ", count: "24曲", footer: "紙に入れて切り取り線で区切る。歌唱者はアイコンを重ねる (写真か判子)。回収は事実の札 (初回収)。") {
                ImasCardList(style: .sheet) {
                    ImasSetlistRow(number: "01", title: "THE IDOLM@STER", artworkURL: Sample.Art.idolmaster, brand: Sample.as765,
                                   performers: [.init(id: "a", name: "天海春香", color: Sample.haruka, iconLabel: "春香"),
                                                .init(id: "b", name: "如月千早", color: Sample.chihaya, iconLabel: "千早"),
                                                .init(id: "c", name: "星井美希", color: Sample.miki, iconLabel: "美希"),
                                                .init(id: "d", name: "菊地真", color: Sample.makoto, iconLabel: "真"),
                                                .init(id: "e", name: "高槻やよい", color: Sample.yayoi, iconLabel: "やよい"),
                                                .init(id: "f", name: "萩原雪歩", color: "#D3DDE9", iconLabel: "雪歩"),
                                                .init(id: "g", name: "水瀬伊織", color: "#FD99E1", iconLabel: "伊織")],
                                   badges: [.init(text: "全体", kind: .all)], facts: ["初披露", "初回収"],
                                   onSelectPerformers: {}, highlightsPick: true,
                                   trailing: .custom(AnyView(ImasLikeButton(isOn: true, count: 42) {})))
                    ImasSetlistRow(number: "02", title: "READY!!", brand: Sample.as765,
                                   performers: [.init(id: "b", name: "如月千早", color: Sample.chihaya, iconLabel: "千早")],
                                   badges: [.init(text: "ソロ", kind: .unit)], facts: ["12 回目"],
                                   customArtwork: AnyView(
                                       ImasArtwork(title: "READY!!", size: 44, imageURL: Sample.Art.ready,
                                                   previewURL: URL(string: "https://example.com/preview.m4a"),
                                                   isPreviewing: previewingSetlist) { previewingSetlist.toggle() }
                                   ),
                                   trailing: .custom(AnyView(ImasLikeButton(isOn: false, count: 0) {})))
                        .environment(\.imasRowPosition, .following)
                    ImasSetlistRow(number: "03", title: "Thank You!", artworkURL: Sample.Art.thankYou, brand: Sample.ml,
                                   performers: (0..<13).map { .init(id: "m\($0)", name: "", color: [Sample.ml, Sample.shizuka, Sample.kotoha][$0 % 3]) },
                                   performerSummary: "MILLIONSTARS 13 人",
                                   badges: [.init(text: "カバー", kind: .cover)], facts: ["未回収"],
                                   trailing: .custom(AnyView(ImasLikeButton(isOn: false, count: 3, isBusy: true) {})))
                        .environment(\.imasRowPosition, .following)
                    ImasSetlistRow(number: "04", title: "ジャケの無い曲", brand: Sample.ml,
                                   performers: [.init(id: "d", name: "田中琴葉", color: Sample.kotoha)],
                                   noteGroups: [
                                       .init(label: "披露", notes: [.init(text: "3回目", tone: .value), .init(text: "1年ぶり", tone: .detail)]),
                                       .init(label: "回収", notes: [.init(text: "未回収", tone: .missing)]),
                                   ],
                                   note: "この公演だけアレンジ違い")
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("機械予測", footer: "過去のセトリと出演者から計算した確率です。") {
                ImasCardList(style: .plain) {
                    ImasForecastRow(rank: 1, title: "標", artworkURL: Sample.Art.shirube, brand: Sample.gakuen, measure: .probability(0.82),
                                    reasonLabel: "オリメン",
                                    performers: [.init(id: "s", name: "花海咲季", color: Sample.saki),
                                                 .init(id: "t", name: "月村手毬", color: "#3D5BA8"),
                                                 .init(id: "k", name: "藤田ことね", color: "#F5C900", isAbsent: true)])
                    ImasForecastRow(rank: 2, title: "Fighting My Way", subtitle: "ソロ曲", artworkURL: Sample.Art.fightingMyWay, brand: Sample.gakuen, measure: .probability(0.64),
                                    reasonLabel: "理由", reason: "ソロの代表曲")
                        .environment(\.imasRowPosition, .following)
                }
                .imasTheme(seed: nil, brand: Sample.gakuen)
            }
            ImasSection("みんなの予想", count: "11票") {
                ImasCardList(style: .plain) {
                    ImasForecastRow(rank: 1, title: "標", artworkURL: Sample.Art.shirube, brand: Sample.gakuen, measure: .votes(5, share: 1),
                                    isMine: voted.contains(1)) { toggle(1) }
                    ImasForecastRow(rank: 2, title: "初", artworkURL: Sample.Art.hajime, brand: Sample.gakuen, measure: .votes(3, share: 0.6),
                                    isMine: voted.contains(2)) { toggle(2) }
                        .environment(\.imasRowPosition, .following)
                    ImasForecastRow(rank: 3, title: "太陽のジェラシー", artworkURL: Sample.Art.jealousy, brand: Sample.gakuen,
                                    measure: .votes(2, share: 0.4), onVote: {}, voteDisabled: true)
                        .environment(\.imasRowPosition, .following)
                    ImasForecastRow(rank: 4, title: "Fighting My Way", artworkURL: Sample.Art.fightingMyWay, brand: Sample.gakuen,
                                    measure: .votes(1, share: 0.2), onVote: {}, isVoteLoading: true)
                        .environment(\.imasRowPosition, .following)
                    ImasForecastRow(rank: 5, title: "次に新ユニット曲が出るなら", unit: Sample.unit, measure: .votes(1, share: 0.2), onVote: {})
                        .environment(\.imasRowPosition, .following)
                }
                .imasTheme(seed: nil, brand: Sample.gakuen)
            }
        }
    }

    private func toggle(_ i: Int) {
        if voted.contains(i) { voted.remove(i) } else { voted.insert(i) }
    }
}
// MARK: - 一覧の型

private struct ListTemplatePage: View {
    enum Sort: String, CaseIterable { case release = "リリース日順", performances = "披露回数順" }
    @State private var sort: Sort = .performances
    @State private var ascending = false
    @State private var filters = ["765AS", "全体曲"]
    @State private var previewingSong = false

    var body: some View {
        List {
            Section {
                ImasFilterBar(items: filters.map { f in
                    .init(id: f, title: f, brand: f == "765AS" ? Sample.as765 : nil) { filters.removeAll { $0 == f } }
                }, onClearAll: { filters.removeAll() })
                .listRowInsets(EdgeInsets())
                ImasListSummary(count: 2051, unit: "件", sortOptions: Sort.allCases, sortSelection: $sort,
                                sortLabel: { $0.rawValue }, sortAscending: $ascending)
                    .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            ImasListSection("2005年") {
                ImasSongRow(title: "THE IDOLM@STER", subtitle: "765PRO ALLSTARS", artworkURL: Sample.Art.idolmaster,
                            brandHex: Sample.as765, showsBrandBar: true,
                            previewURL: URL(string: "https://example.com/preview.m4a"), isPreviewing: previewingSong,
                            onPreviewTap: { previewingSong.toggle() },
                            trailing: .metric("89", unit: "回", emphasized: true)) {
                    HStack(spacing: DS.Space.gapTight) {
                        Text("7月26日").imasText(.meta)
                        ImasBadge(text: "回収 3", kind: .positive, systemImage: "checkmark")
                    }
                }
                ImasSongRow(title: "ジャケ未登録の曲", subtitle: "765PRO ALLSTARS",
                            brandHex: Sample.as765, showsBrandBar: true, trailing: .metric("56", unit: "回", emphasized: true)) { EmptyView() }
            }
            ImasListSection("ライブ") {
                ImasShowRow(date: "2025-12-13", title: "DAY1", subtitle: "京セラドーム大阪 · 17:00 開演",
                            brandHex: Sample.as765, badges: [.init(text: "参加", kind: .positive)])
                ImasShowRow(date: "2025-12-14", title: "DAY2", subtitle: "京セラドーム大阪 · 16:00 開演",
                            brandHex: Sample.as765)
            }
        }
        .imasList()
    }
}

// MARK: - 編集シートの型

private struct FormTemplatePage: View {
    enum SavingDemo { case spinner, progress }

    @State private var name = "LIVE TOUR -標-"
    @State private var url = "htps://example"
    @State private var memo = ""
    @State private var notify = true
    @State private var confirmDelete = false
    @State private var toolbarKind = 0
    @State private var savingDemo: SavingDemo?

    private var currentToolbarKind: ImasSheetToolbarKind {
        switch toolbarKind {
        case 0: return .edit(canSave: true, onCancel: {}, onSave: {})
        case 1: return .submit(canSubmit: true, isSubmitting: false, onCancel: {}, onSubmit: {})
        case 2: return .select(canFinish: true, onCancel: {}, onFinish: {})
        case 3: return .read(onClose: {})
        default: return .prompt(canRecord: true, onLater: {}, onRecord: {})
        }
    }

    private func trySaving(_ demo: SavingDemo) {
        savingDemo = demo
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savingDemo = nil }
    }

    var body: some View {
        Form {
            ImasListSection("ツールバーの種類 (見本切り替え)", footer: "編集=キャンセル/保存、送信=キャンセル/送信、選択=キャンセル/完了、閲覧=閉じる、後で=あとで/記録する。") {
                ImasSegmented(labels: ["編集", "送信", "選択", "閲覧", "後で"], selection: $toolbarKind)
                    .listRowBackground(Color.clear)
            }
            ImasListSection("基本") {
                ImasTextFieldRow(title: "ライブ名", text: $name)
                ImasTextFieldRow(title: "特設ページ", text: $url, error: "URL の形になっていません")
                ImasToggleRow(title: "開演前に知らせる", subtitle: "開演 1 時間前に通知します", isOn: $notify)
            }
            ImasListSection("メモ", footer: "メモはこの端末にだけ保存されます。") {
                ImasTextAreaRow(text: $memo, prompt: "座席・同行者・感想など", limit: 400)
            }
            ImasListSection("保存中のオーバーレイ (見本。触ると 1.5 秒で消える)") {
                ImasActionRow(title: "保存中 (くるくる) を試す", systemImage: "arrow.clockwise") { trySaving(.spinner) }
                ImasActionRow(title: "送信中 (進み具合) を試す", systemImage: "arrow.up.circle") { trySaving(.progress) }
            }
            ImasListSection {
                ImasActionRow(title: "このライブを削除", kind: .destructive) { confirmDelete = true }
            }
        }
        .imasForm()
        .navigationTitle("ライブを編集")
        .imasSheetToolbar(currentToolbarKind)
        .imasConfirmDestructive("このライブを削除しますか？", isPresented: $confirmDelete,
                                message: "公演とセトリもいっしょに削除されます。") {}
        .imasSavingOverlay(savingDemo != nil, label: savingDemo == .progress ? "送信中" : "保存中",
                           progress: savingDemo == .progress ? 0.6 : nil)
    }
}

// MARK: - ゲームの設定・読みもの

private struct SetupPage: View {
    var body: some View {
        ImasPage {
            ImasSetupHeader(systemImage: "music.quarternote.3", title: "歌詞クイズ",
                            message: "歌詞の一節から曲名を当てます。")
            ImasCandidateCount(count: 7, minimum: 10)
            ImasCandidateCount(count: nil, minimum: 10, isLoading: true, loadingText: "候補を計算中…")
            ImasCandidateCount(count: nil, minimum: 10, note: "読み込みに失敗しました")
            ImasNotice(kind: .warning, title: "候補が足りません", message: "出題に必要な 10 曲に届いていません。ブランドを増やしてください。")
            ImasSection("習熟度", style: .small) {
                ImasCard {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        Text("覚えた").imasText(.rowTitle)
                        ImasMeter(value: 7, total: 10).imasTheme(seed: Sample.chihaya)
                    }
                }
            }
            ImasSection("使い方 (写真・図解を添えた手順)", style: .small) {
                ImasCard {
                    ImasStepList(steps: [
                        .init(title: "ホーム画面を長押しする", detail: "アイコンが揺れたら左上の ＋ を押します。"),
                        .init(title: "「アイドルライブDB」を探す"),
                        .init(title: "担当画像を選ぶ", detail: "ウィジェットを長押しして編集します。") {
                            ImasArtwork(title: "担当画像の見本", size: 120, imageURL: Sample.Art.idolmaster)
                        },
                    ])
                }
            }
            ImasSection("できること (番号の無い列挙)", style: .small) {
                ImasCard {
                    ImasPointList(points: [
                        .init("checkmark.seal", "現地で聴いた曲を記録する"),
                        .init("chart.bar", "ブランドごとの回収率を見る"),
                        .init("sparkles", "次のセトリをみんなで予想する"),
                    ])
                }
            }
            ImasButton(title: "はじめる", size: .large) {}
        }
    }
}

// MARK: - コミュニティ (タグ・記録)

private struct CommunityPage: View {
    @State private var tagColor = "#FF8C42"

    var body: some View {
        ImasPage {
            ImasSection("タグ詳細の頭", style: .small) {
                ImasCard {
                    ImasTagHeaderCard(name: "夏に聴きたい曲", colorHex: "#FF8C42", categoryLabel: "雰囲気",
                                      description: "海・花火・浴衣が似合う曲。")
                }
            }
            ImasSection("タグ詳細の頭 (説明なし・色なし)", style: .small) {
                ImasCard {
                    ImasTagHeaderCard(name: "ソロ曲好き", categoryLabel: "好み")
                }
            }
            ImasSection("タグの色を選ぶ", style: .small) {
                ImasCard { ImasColorPicker(selectedHex: $tagColor) }
            }
            ImasSection("色そのものを見せる丸", style: .small, footer: "タグの色・ペンライトの色そのもの (導出を通さない数少ない部品)。読み上げは色名。") {
                HStack(alignment: .center, spacing: DS.Space.gapLoose) {
                    ImasSwatch(hex: "#FF6B6B", size: .dot)
                    ImasSwatch(hex: "#4D96FF", size: .small)
                    ImasSwatch(hex: "#1DD1A1", size: .large, isSelected: true)
                    ImasSwatch(hex: "#9B5DE5", size: .large)
                }
            }
            ImasSection("順位の小さい札 (文中に差し込む)", style: .small, footer: "行の先頭いっぱいに置く大きな順位は ImasRankNumber。こちらは名前と同じ行に添える小さい版。") {
                ImasCard {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        HStack(spacing: DS.Space.gap) {
                            ImasRankBadge(rank: 1)
                            Text("天海春香").imasText(.rowTitle)
                            Spacer(minLength: 0)
                            Text("42票").imasText(.meta)
                        }
                        HStack(spacing: DS.Space.gap) {
                            ImasRankBadge(rank: 12)
                            Text("萩原雪歩").imasText(.rowTitle)
                            Spacer(minLength: 0)
                            Text("3票").imasText(.meta)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AI チャット

private struct ChatPage: View {
    @State private var input = ""

    private func aiAvatar(seed: String? = nil) -> some View {
        ImasAvatar(label: "AI", seed: seed, size: 30, reservesPickRing: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.card) {
                    ImasChatBubble(role: .assistant, content: .text("どんな曲を探していますか？")) { aiAvatar() }
                    ImasChatBubble(role: .user, content: .text("夏に聴きたいアップテンポな曲"))
                    ImasChatToolChip(label: "曲を検索中…")
                    ImasChatBubble(role: .assistant, content: .streaming("候補が")) { aiAvatar() }
                    ImasChatBubble(role: .assistant, content: .failed(message: nil, onRetry: {})) { aiAvatar() }
                    ImasChatBubble(role: .assistant, content: .text("学マスの新曲だよ！"), partnerName: "藤田ことね", seed: Sample.saki) {
                        aiAvatar(seed: Sample.saki)
                    }
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.gapLoose)
                .padding(.bottom, DS.Space.gap)
            }
            ImasChatComposer(text: $input, placeholder: "質問を入力", isRunning: false, canSend: !input.isEmpty,
                             onSend: {}, onStop: {}) {
                Text("1 日 10 回まで利用できます。").imasText(.note)
            }
        }
        .background(DS.bg)
    }
}

// MARK: - あそぶ (ステージ)

private struct StagePage: View {
    private func stageLabel(_ text: String) -> some View {
        Text(text).font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.section) {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    ImasSection("表彰台・対戦の結果", style: .small, footer: "ImasPodium・ImasVersusBadge・imasAccentCard は地が紙面のまま (QS の固定色は使わない)。ソートメーカー・ティアー表の結果で使う。") {
                        ImasPodium(entries: [
                            .init(id: "1", rank: 1, title: "天海春香", seed: Sample.haruka,
                                  visual: AnyView(ImasAvatar(label: "春香", seed: Sample.haruka, size: 64)), action: {}),
                            .init(id: "2", rank: 2, title: "如月千早", seed: Sample.chihaya,
                                  visual: AnyView(ImasAvatar(label: "千早", seed: Sample.chihaya, size: 52)), action: {}),
                            .init(id: "3", rank: 3, title: "星井美希", seed: Sample.miki,
                                  visual: AnyView(ImasAvatar(label: "美希", seed: Sample.miki, size: 52)), action: {}),
                        ])
                    }
                    ImasSection("ティアー表", style: .small, footer: "ImasTierHeader・ImasTierBoard・ImasTierRow・ImasTierItems・ImasTierChip・ImasTierLabel・ImasTierMoveBar。段の色は段ごとのシード。選んでいる間だけ札と面が移し先になる。") {
                        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                            ImasTierHeader(title: "765PRO ALLSTARS のティアー表", subtitle: "アイドル · 3 / 13 振り分け済み") {}
                            ImasTierBoard {
                                ImasTierRow(label: "S", seed: "#E5484D", isTarget: true, accessibilityLabel: "S 2件") {} content: {
                                    ImasTierItems(ids: ["春香", "千早"], layout: .flow, emptyText: "ここへ移す") { name in
                                        ImasTierChip(title: name, seed: name == "春香" ? Sample.haruka : Sample.chihaya,
                                                     isSelected: name == "千早") { size in
                                            ImasAvatar(label: name, seed: name == "春香" ? Sample.haruka : Sample.chihaya,
                                                       size: size, reservesPickRing: false)
                                        }
                                    }
                                }
                                ImasTierRow(label: "神曲", seed: "#F5A524", isTarget: true, accessibilityLabel: "神曲 1件") {} content: {
                                    ImasTierItems(ids: ["美希"], layout: .flow) { name in
                                        ImasTierChip(title: name, seed: Sample.miki, isSelected: false) { size in
                                            ImasAvatar(label: name, seed: Sample.miki, size: size, reservesPickRing: false)
                                        }
                                    }
                                }
                                ImasTierRow(label: "B", seed: "#3E9B5F", isTarget: true, accessibilityLabel: "B 0件") {} content: {
                                    ImasTierItems(ids: [String](), layout: .flow, emptyText: "ここへ移す") { _ in EmptyView() }
                                }
                            }
                            HStack(spacing: DS.Space.gap) {
                                ImasTierLabel(label: "S", seed: "#E5484D", style: .swatch)
                                ImasTierLabel(label: "神曲", seed: "#F5A524", style: .swatch)
                                ImasTierLabel(label: "?", seed: "#3E9B5F", style: .swatch)
                            }
                            ImasTierMoveBar(
                                title: "「如月千早」をどこへ？",
                                tiers: [.init(id: "s", label: "S", seed: "#E5484D"),
                                        .init(id: "g", label: "神曲", seed: "#F5A524"),
                                        .init(id: "b", label: "B", seed: "#3E9B5F")],
                                onCancel: {}, onMove: { _ in }, onUnplace: {}
                            )
                        }
                    }
                    ImasSection("対戦カードの間・選べるカードの縁", style: .small) {
                        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                            HStack(spacing: 12) {
                                ImasAvatar(label: "春香", seed: Sample.haruka, size: 44)
                                ImasVersusBadge()
                                ImasAvatar(label: "千早", seed: Sample.chihaya, size: 44)
                            }
                            HStack(spacing: DS.Space.gap) {
                                VStack(spacing: 4) {
                                    Text("対戦相手").imasText(.rowLabel)
                                    Text("765AS").imasText(.meta)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Space.gap)
                                .imasAccentCard(seed: Sample.haruka, isSelected: true, style: .card)
                                Text("学マス").imasText(.chip)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: DS.Size.chip)
                                    .imasAccentCard(brand: Sample.gakuen, isSelected: false, style: .chip)
                            }
                        }
                    }
                    ImasSection("ハブからステージへの入口", style: .small, footer: "ImasStageWordmark・ImasStagePreviewCard は QS の固定色のまま、明るい一覧に埋め込む窓。") {
                        ImasStagePreviewCard {
                            HStack(spacing: 10) {
                                ImasStageWordmark(text: "Q")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("QUIZ STAGE").font(QS.mono(11)).foregroundStyle(QS.dim)
                                    Text("歌詞クイズ Q.04 / 10").font(QS.text(13, weight: .bold)).foregroundStyle(QS.ink)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screen)

                VStack(alignment: .leading, spacing: 20) {
                    stageLabel("メンバーカラークイズ")
                    HStack(spacing: 10) {
                        ImasStageColorSwatch(hex: "#E54B4D", letter: "A", style: .choice, isSelected: true) {}
                        ImasStageColorSwatch(hex: "#3A8EE6", letter: "B", style: .choice) {}
                        ImasStageColorSwatch(hex: "#7A5AE0", letter: "C", style: .choice, isEliminated: true) {}
                    }
                    HStack(spacing: 10) {
                        ImasStageColorSwatch(hex: "#F2C12E", style: .palette)
                        ImasStageColorSwatch(hex: "#3FB27F", style: .palette, isUsed: true)
                        ImasStageAssignmentTarget(assignedHex: nil)
                        ImasStageAssignmentTarget(assignedHex: "#E54B4D", verdict: true)
                        ImasStageAssignmentTarget(assignedHex: "#3A8EE6", verdict: false)
                        ImasStageColorGridIcon()
                    }

                    stageLabel("再生中の表示・案内行")
                    ImasStageEqualizer(columns: 20, rows: 4, dotSize: 8)
                    ImasStageInfoRow(systemImage: "info.circle", title: "正解すると次の問題に進みます", detail: "残り 12 問", showsChevron: true) {}
                    ImasStageInfoRow(systemImage: "arrow.clockwise", title: "次の問題を読み込み中", isLoading: true)

                    stageLabel("判定カード")
                    ImasStagePartialVerdictCard(number: 4, isPerfect: true, headline: "全員正解！", score: 120)
                    ImasStagePartialVerdictCard(number: 5, isPerfect: false, headline: "2 / 3 正解", score: 60)

                    stageLabel("再生・操作のボタン")
                    HStack(spacing: 12) {
                        ImasStageIconTileButton(systemImage: "arrow.counterclockwise", label: "もう一度") {}
                        ImasStagePlaybackControl(isPlaying: false, onTap: {}, onHoldBegin: {}, onHoldEnd: {})
                        ImasStagePlaybackControl(isPlaying: true, onTap: {}, onHoldBegin: {}, onHoldEnd: {})
                    }
                    HStack(spacing: 20) {
                        ImasStagePlaybackControl(isPlaying: false, style: .circle, onTap: {}, onHoldBegin: {}, onHoldEnd: {})
                        ImasStageCircleButton(label: "!", size: 88) {}
                    }

                    stageLabel("進捗・数・達成")
                    VStack(alignment: .leading, spacing: 10) {
                        ImasStageProgressBar(fraction: 0.6)
                        ImasStageProgressBar(fraction: 0.92, isUrgent: true)
                    }
                    HStack(spacing: 10) {
                        ImasStageStatTile(label: "SCORE") {
                            Text("820").font(QS.num(26)).foregroundStyle(QS.ink)
                        }
                        ImasStageStatTile(label: "ハイスコア") {
                            Text("755").font(QS.num(26)).foregroundStyle(QS.ink)
                        } trailing: {
                            ImasStageBadgeStamp(title: "自己ベスト更新", detail: "700 → 755")
                        }
                    }
                    HStack(spacing: 20) {
                        ImasStageScoreChip(colorHex: Sample.haruka, name: "春香P", score: 420)
                        ImasStageScoreChip(colorHex: Sample.chihaya, name: "千早P", score: 380)
                    }

                    stageLabel("聴取中・判定中・正誤")
                    HStack(spacing: 16) {
                        ImasStagePenlightBars(colors: [Color(hexString: Sample.haruka), Color(hexString: Sample.chihaya),
                                                       Color(hexString: Sample.miki)])
                        HStack(spacing: 8) {
                            ImasStagePulse()
                            Text("聴取中").font(QS.text(12, weight: .semibold)).foregroundStyle(QS.dim)
                        }
                    }
                    ImasStagePanel {
                        Text("判定中…").font(QS.text(13, weight: .bold)).foregroundStyle(QS.ink)
                    }
                    HStack(spacing: 24) {
                        ImasStageRushFlash(isCorrect: true)
                        ImasStageRushFlash(isCorrect: false)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)

                    stageLabel("1 対 1 対戦の結果")
                    ImasStageVersusResult(
                        winnerColorHex: Sample.haruka, headline: "春香P の勝ち！",
                        players: (.init(name: "春香P", colorHex: Sample.haruka, score: 820),
                                  .init(name: "千早P", colorHex: Sample.chihaya, score: 640))
                    ) {
                        ImasStageIconTileButton(systemImage: "arrow.counterclockwise", label: "もう一度") {}
                        ImasStageIconTileButton(systemImage: "square.and.arrow.up", label: "シェア") {}
                    }
                    .frame(height: 260)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QS.bg)
                .environment(\.colorScheme, .dark)
            }
            .padding(.top, DS.Space.gapLoose)
            .padding(.bottom, DS.Space.section)
        }
        .background(DS.paper)
        .environment(\.imasBackdrop, .paper)
    }
}
#endif
