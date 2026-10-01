#if DEBUG
import SwiftUI

// =============================================================================
// 部品カタログ (DEBUG ビルドのみ)
//
// デザインシステムの全部品を、種類と状態ごとに実物で並べる。参照ページの見本はここを撮る。
// 部品を足したらここにも足す (docs/DESIGN_SYSTEM.md §15)。
// =============================================================================

enum DesignCatalogPage: String, CaseIterable, Identifiable {
    case buttons, chips, rows, rows2, sections, heroSong, heroIdol, hub, feedback, setlist, list, form, setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buttons: return "ボタン"
        case .chips: return "チップ・札・数字"
        case .rows: return "行 (実体)"
        case .rows2: return "行 (項目・入口・選択)"
        case .sections: return "区画・面・お知らせ"
        case .heroSong: return "詳細の頭 (曲)"
        case .heroIdol: return "詳細の頭 (アイドル)"
        case .hub: return "ハブ"
        case .feedback: return "状態・メーター"
        case .setlist: return "セトリと予想"
        case .list: return "一覧の型"
        case .form: return "編集シートの型"
        case .setup: return "ゲームの設定・読みもの"
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
            case .buttons: ButtonsPage()
            case .chips: ChipsPage()
            case .rows: EntityRowsPage()
            case .rows2: ValueRowsPage()
            case .sections: SectionsPage()
            case .heroSong: SongHeroPage()
            case .heroIdol: IdolHeroPage()
            case .hub: HubPage()
            case .feedback: FeedbackPage()
            case .setlist: SetlistPage()
            case .list: ListTemplatePage()
            case .form: FormTemplatePage()
            case .setup: SetupPage()
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - ボタン

private struct ButtonsPage: View {
    var body: some View {
        ImasPage {
            ImasSection("主ボタン (大)", style: .small, footer: "画面で一番大事な操作。1 画面に 1 つ。実体の無い画面では白黒。") {
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
            ImasSection("歌唱メンバーの予想 (アバター付き)", style: .small) {
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
            ImasSection("数字", style: .small) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    ImasMetric(value: "89", unit: "回", size: .large)
                    ImasMetric(value: "42", unit: "%", size: .medium, emphasized: true).imasTheme(seed: Sample.haruka)
                    ImasMetric(value: "2,051", unit: "件", size: .small)
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
                ImasCardList {
                    ImasRow(title: "THE IDOLM@STER", subtitle: "765PRO ALLSTARS",
                            leading: .artwork(title: "THE IDOLM@STER", brand: Sample.as765),
                            trailing: .metric("89", unit: "回")) {
                        HStack(spacing: DS.Space.gapTight) {
                            Text("2005年7月26日").imasText(.meta)
                            ImasBadge(text: "回収 3", kind: .positive, systemImage: "checkmark")
                        }
                    }
                    ImasRow(title: "Thank You!", subtitle: "MILLIONSTARS",
                            leading: .artwork(title: "Thank You!", brand: Sample.ml),
                            trailing: .metric("74", unit: "回"))
                        .environment(\.imasRowPosition, .following)
                    ImasRow(title: "お願い！シンデレラ", subtitle: "CINDERELLA GIRLS",
                            leading: .artwork(title: "お願い！シンデレラ", brand: Sample.cg),
                            trailing: .metric("120", unit: "回"))
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("アイドル", style: .large) {
                ImasCardList {
                    ImasRow(title: "天海春香", subtitle: "765AS · CV 中村繪里子",
                            leading: .avatar(label: "春香", seed: Sample.haruka, isPick: true),
                            trailing: .custom(AnyView(Image(systemName: "heart.fill").foregroundStyle(DS.pick))))
                    ImasRow(title: "如月千早", subtitle: "765AS · CV 今井麻美",
                            leading: .avatar(label: "千早", seed: Sample.chihaya))
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("ライブ・公演", style: .large) {
                ImasCardList {
                    ImasRow(title: "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)", subtitle: "11月7日(土)〜8日(日) · Kアリーナ横浜",
                            leading: .bar(brand: Sample.gakuen), trailing: .chevron) {
                        ImasBadge(text: "参加予定", kind: .attention)
                    }
                    ImasRow(title: "M@STERS OF IDOL WORLD 2025", subtitle: "2025年12月13日(土)〜14日(日) · 京セラドーム大阪",
                            leading: .bar(rainbow: true), trailing: .chevron, emphasis: .dimmed)
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

    var body: some View {
        ImasPage {
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
            ImasSection("区画の見出し (小)", style: .small, footer: "補足文は区画の下に灰色で置き、囲まない。") {
                ImasCard {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        Text("次の出演").imasText(.eyebrow)
                        Text("15th ANNIVERSARY PARTY!!!! ~ for your ONE ~").imasText(.cardTitle)
                        ImasCard(style: .inset) { Text("カードの中の囲み (inset)").imasText(.note) }
                    }
                }
            }
            ImasSection("実体色のカード (tinted)") {
                ImasCard(style: .tinted) {
                    Text("担当・次の出演など、その実体が主役のときだけ").imasText(.body)
                }
                .imasTheme(seed: Sample.kanade)
            }
            ImasSection("お知らせの帯", style: .small) {
                VStack(spacing: DS.Space.gap) {
                    ImasNotice(kind: .warning, title: "候補が足りません", message: "出題に必要な 10 曲に届いていません。ブランドを増やしてください。")
                    ImasNotice(kind: .error, message: "タグを読み込めませんでした。", actionTitle: "もう一度", action: {})
                    ImasNotice(kind: .success, message: "コールガイドを保存しました。")
                    ImasNotice(kind: .info, message: "5 分前時点の情報です。")
                }
            }
        }
    }
}

// MARK: - 詳細の頭

private struct SongHeroPage: View {
    @State private var tab = 0
    @State private var favorite = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ImasHero(layout: .centered, eyebrow: "765AS", title: "THE IDOLM@STER",
                         subtitle: "天海春香 / 如月千早 / 星井美希 / 菊地真 / 高槻やよい",
                         primary: .init(title: "再生", systemImage: "play.fill") {}) {
                    ImasArtwork(title: "THE IDOLM@STER", size: 168)
                } facts: {
                    HStack(spacing: DS.Space.gapTight) {
                        ImasBadge(text: "全体曲", kind: .all)
                        ImasBadge(text: "KAMISABI 収録", kind: .themed)
                    }
                }
                HStack(spacing: DS.Space.gap) {
                    ImasMarkTile(systemImage: favorite ? "star.fill" : "star", label: "お気に入り", isOn: favorite) { favorite.toggle() }
                    ImasMarkTile(systemImage: "note.text", label: "メモ", isOn: false) {}
                    ImasMarkTile(systemImage: "checkmark.seal", label: "習熟度", isOn: true) {}
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, DS.Space.card)
                .background(ImasThemeBackground())
                ImasSegmented(labels: ["情報", "歌詞", "披露履歴", "みんな"], selection: $tab)
                    .padding(DS.Space.screen)
                VStack(spacing: DS.Space.section) {
                    ImasStatGrid {
                        ImasStatTile(systemImage: "music.mic", value: "89", unit: "回", label: "披露回数")
                        ImasStatTile(systemImage: "checkmark.seal.fill", value: "3", unit: "公演", label: "現地回収", tappable: true)
                    }
                }
                .padding(.horizontal, DS.Space.screen)
            }
        }
        .background(DS.bg)
        .imasTheme(seed: nil, brand: Sample.as765)
    }
}

private struct IdolHeroPage: View {
    @State private var tab = 0
    @State private var pick = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ImasHero(layout: .leading, eyebrow: "765AS", title: "天海春香", subtitle: "CV 中村繪里子",
                         primary: .init(title: "出演ライブ", systemImage: "music.mic") {}) {
                    ImasAvatar(label: "春香", size: 88, isPick: pick)
                }
                HStack(spacing: DS.Space.gap) {
                    ImasMarkTile(systemImage: pick ? "heart.fill" : "heart", label: "担当", isOn: pick) { pick.toggle() }
                    ImasMarkTile(systemImage: "star", label: "お気に入り", isOn: false) {}
                    ImasMarkTile(systemImage: "note.text", label: "メモ", isOn: false) {}
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, DS.Space.card)
                .background(ImasThemeBackground())
                ImasSegmented(labels: ["ライブ", "楽曲", "プロフィール", "みんな"], selection: $tab)
                    .padding(DS.Space.screen)
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    ImasFeatureCard(eyebrow: "次の出演 · 11月28日(土)", title: "15th ANNIVERSARY PARTY!!!! ~ for your ONE ~",
                                    subtitle: "Kアリーナ横浜 · DAY1", seed: Sample.haruka)
                    ImasSection("ライブ歌唱曲", count: "42曲") {
                        ImasCardList {
                            ImasRow(title: "THE IDOLM@STER", leading: .artwork(title: "THE IDOLM@STER", brand: Sample.as765),
                                    trailing: .metric("71", unit: "回"), density: .compact)
                            ImasRow(title: "READY!!", leading: .artwork(title: "READY!!", brand: Sample.as765),
                                    trailing: .metric("56", unit: "回"), density: .compact)
                                .environment(\.imasRowPosition, .following)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screen)
            }
        }
        .background(DS.bg)
        .imasTheme(seed: Sample.haruka)
    }
}

/// 頭の地 (実体色) をタイルの段にも続ける。
private struct ImasThemeBackground: View {
    @Environment(\.imasTheme) private var theme
    var body: some View { theme.isNeutral ? DS.bg : theme.heroSurface }
}

// MARK: - ハブ

private struct HubPage: View {
    var body: some View {
        ImasPage {
            ImasFeatureCard(eyebrow: "担当", title: "花海咲季", subtitle: "学マス · CV 長月あおい", seed: Sample.saki,
                            primary: .init(title: "出演ライブ", systemImage: "music.mic") {},
                            secondary: .init(title: "詳細") {}) {
                ImasAvatar(label: "咲季", size: 64, isPick: true)
            }
            ImasFeatureCard(eyebrow: "参加予定 · あと 37 日", title: "LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)",
                            subtitle: "11月7日(土) · DAY1", brand: Sample.gakuen,
                            primary: .init(title: "セトリを予想", systemImage: "sparkles") {},
                            secondary: .init(title: "コールを見る") {})
            ImasSection("あそぶ") {
                VStack(spacing: DS.Space.gap) {
                    ImasEntryCard(systemImage: "gamecontroller.fill", title: "クイズ・ゲーム", preview: "つづきから: 歌詞クイズ Q.02")
                    ImasEntryCard(systemImage: "chart.bar.doc.horizontal", title: "みんなの投票", preview: "ハロウィンの日、仮装して事務所に来そうなアイドルは？")
                }
            }
            ImasSection("記録") {
                ImasStatGrid {
                    ImasStatTile(systemImage: "music.mic", value: "24", unit: "公演", label: "参加したライブ", tappable: true)
                    ImasStatTile(systemImage: "checkmark.seal.fill", value: "39", unit: "曲", label: "現地回収", tappable: true)
                    ImasStatTile(systemImage: "yensign", value: "184,300", unit: "円", label: "今年の収支")
                    ImasStatTile(systemImage: "star.fill", value: "112", unit: "件", label: "お気に入り")
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

    var body: some View {
        ImasPage {
            ImasSection("セトリ", count: "24曲") {
                ImasCardList {
                    ImasSetlistRow(number: "M01", title: "THE IDOLM@STER",
                                   performers: [.init(id: "a", name: "天海春香", color: Sample.haruka),
                                                .init(id: "b", name: "如月千早", color: Sample.chihaya),
                                                .init(id: "c", name: "星井美希", color: Sample.miki)],
                                   badges: [.init(text: "全員", kind: .all)], facts: ["初披露"], isCollected: true)
                    ImasSetlistRow(number: "M02", title: "細氷",
                                   performers: [.init(id: "b", name: "如月千早", color: Sample.chihaya)],
                                   badges: [.init(text: "ソロ", kind: .unit, seed: Sample.chihaya)], facts: ["12 回目"])
                        .environment(\.imasRowPosition, .following)
                    ImasSetlistRow(number: "M03", title: "Thank You!", performerSummary: "MILLIONSTARS 13 人",
                                   badges: [.init(text: "カバー", kind: .cover)], facts: ["未回収"])
                        .environment(\.imasRowPosition, .following)
                }
            }
            ImasSection("機械予測", footer: "過去のセトリと出演者から計算した確率です。") {
                ImasCardList {
                    ImasForecastRow(rank: 1, title: "標", brand: Sample.gakuen, measure: .probability(0.82),
                                    reasonLabel: "オリメン",
                                    performers: [.init(id: "s", name: "花海咲季", color: Sample.saki),
                                                 .init(id: "t", name: "月村手毬", color: "#3D5BA8"),
                                                 .init(id: "k", name: "藤田ことね", color: "#F5C900", isAbsent: true)])
                    ImasForecastRow(rank: 2, title: "Fighting My Way", brand: Sample.gakuen, measure: .probability(0.64),
                                    reasonLabel: "理由", reason: "ソロの代表曲")
                        .environment(\.imasRowPosition, .following)
                }
                .imasTheme(seed: nil, brand: Sample.gakuen)
            }
            ImasSection("みんなの予想", count: "11票") {
                ImasCardList {
                    ImasForecastRow(rank: 1, title: "標", brand: Sample.gakuen, measure: .votes(5, share: 1),
                                    isMine: voted.contains(1)) { toggle(1) }
                    ImasForecastRow(rank: 2, title: "初", brand: Sample.gakuen, measure: .votes(3, share: 0.6),
                                    isMine: voted.contains(2)) { toggle(2) }
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
    @State private var filters = ["765AS", "全体曲"]

    var body: some View {
        List {
            Section {
                ImasFilterBar(items: filters.map { f in
                    .init(id: f, title: f, brand: f == "765AS" ? Sample.as765 : nil) { filters.removeAll { $0 == f } }
                }, onClearAll: { filters.removeAll() })
                .listRowInsets(EdgeInsets())
                ImasListSummary(count: 2051, unit: "件", sortOptions: Sort.allCases, sortSelection: $sort) { $0.rawValue }
                    .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            ImasListSection("2005年") {
                ImasSongRow(title: "THE IDOLM@STER", subtitle: "765PRO ALLSTARS", brandHex: Sample.as765,
                            trailing: .metric("89", unit: "回")) {
                    HStack(spacing: DS.Space.gapTight) {
                        Text("7月26日").imasText(.meta)
                        ImasBadge(text: "回収 3", kind: .positive, systemImage: "checkmark")
                    }
                }
                ImasSongRow(title: "READY!!", subtitle: "765PRO ALLSTARS", brandHex: Sample.as765,
                            trailing: .metric("56", unit: "回")) { EmptyView() }
            }
            ImasListSection("ライブ") {
                ImasShowRow(title: "DAY1", subtitle: "12月13日(土) · 京セラドーム大阪 · 17:00 開演", rainbow: true,
                            trailing: .badge(ImasBadge(text: "参加済", kind: .positive)))
                ImasShowRow(title: "DAY2", subtitle: "12月14日(日) · 京セラドーム大阪 · 16:00 開演", rainbow: true)
            }
        }
        .listStyle(.plain)
        .imasForm()
    }
}

// MARK: - 編集シートの型

private struct FormTemplatePage: View {
    @State private var name = "LIVE TOUR -標-"
    @State private var url = "htps://example"
    @State private var memo = ""
    @State private var notify = true
    @State private var confirmDelete = false

    var body: some View {
        Form {
            ImasListSection("基本") {
                ImasTextFieldRow(title: "ライブ名", text: $name)
                ImasTextFieldRow(title: "特設ページ", text: $url, error: "URL の形になっていません")
                ImasToggleRow(title: "開演前に知らせる", subtitle: "開演 1 時間前に通知します", isOn: $notify)
            }
            ImasListSection("メモ", footer: "メモはこの端末にだけ保存されます。") {
                ImasTextAreaRow(text: $memo, prompt: "座席・同行者・感想など", limit: 400)
            }
            ImasListSection {
                ImasActionRow(title: "このライブを削除", kind: .destructive) { confirmDelete = true }
            }
        }
        .imasForm()
        .navigationTitle("ライブを編集")
        .imasSheetToolbar(.edit(canSave: true, onCancel: {}, onSave: {}))
        .imasConfirmDestructive("このライブを削除しますか？", isPresented: $confirmDelete,
                                message: "公演とセトリもいっしょに削除されます。") {}
    }
}

// MARK: - ゲームの設定・読みもの

private struct SetupPage: View {
    var body: some View {
        ImasPage {
            ImasSetupHeader(systemImage: "music.quarternote.3", title: "歌詞クイズ",
                            message: "歌詞の一節から曲名を当てます。")
            ImasCandidateCount(count: 7, minimum: 10)
            ImasNotice(kind: .warning, title: "候補が足りません", message: "出題に必要な 10 曲に届いていません。ブランドを増やしてください。")
            ImasSection("習熟度", style: .small) {
                ImasCard {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        Text("覚えた").imasText(.rowTitle)
                        ImasMeter(value: 7, total: 10).imasTheme(seed: Sample.chihaya)
                    }
                }
            }
            ImasSection("使い方", style: .small) {
                ImasCard {
                    ImasStepList(steps: [
                        .init(title: "ホーム画面を長押しする", detail: "アイコンが揺れたら左上の ＋ を押します。"),
                        .init(title: "「アイドルライブDB」を探す"),
                        .init(title: "担当画像を選ぶ", detail: "ウィジェットを長押しして編集します。"),
                    ])
                }
            }
            ImasButton(title: "はじめる", size: .large) {}
        }
    }
}
#endif
