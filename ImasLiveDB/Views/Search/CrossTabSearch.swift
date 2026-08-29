import SwiftUI

/// タブの識別。`ContentView` の `TabView` の tag と対で持つ。
///
/// 生の数字を各画面に配ると、タブを 1 つ足したときに直し漏れる。
enum RootTab: Int, CaseIterable, Hashable {
    case schedule = 0, events = 1, songs = 2, idols = 3, produce = 4

    /// 「他のタブに N 件」で押せる先。検索欄を持つ一覧だけ。
    static let searchable: [RootTab] = [.events, .songs, .idols]

    var label: String {
        switch self {
        case .schedule: return "スケジュール"
        case .events: return "ライブ"
        case .songs: return "楽曲"
        case .idols: return "アイドル"
        case .produce: return "プロデュース"
        }
    }
}

/// タブを跨いだ検索の引き継ぎ。
///
/// ## なぜこれがあるか
///
/// 以前は虫眼鏡 1 つで横断検索 (`UnifiedSearchView`) を開いていた。1.11.0 で
/// 検索を各一覧の中に入れてから、横断検索が単独で提供するものは「すべて」スコープ
/// だけになっていた — 曲・アイドル・ライブ・歌詞は全部それぞれの一覧が持っている。
/// しかも一覧側の方が強い (ブランド絞り込みや並び順と組み合わせられる)。
///
/// 残っていた価値は「どのタブにあるか分からないものを探せる」ことだけなので、
/// 画面ごと畳んで、各一覧が「他のタブに N 件」を出す形に移した。
@Observable
@MainActor
final class CrossTabSearch {
    static let shared = CrossTabSearch()

    /// 移動先のタブ。`ContentView` が拾って切り替え、受け取った一覧が nil に戻す。
    private(set) var target: RootTab?
    /// 引き継ぐ検索語。
    private(set) var query: String = ""

    private init() {}

    func hand(_ query: String, to tab: RootTab) {
        self.query = query
        self.target = tab
    }

    /// 自分宛なら語を受け取る (受け取ったら消す。戻ってきたときに再適用されないように)。
    func take(for tab: RootTab) -> String? {
        guard target == tab else { return nil }
        target = nil
        return query
    }
}

/// 「他のタブに N 件」のチップ列。
///
/// 件数はコアが数える (各一覧の絞り込みと同じ索引を通るので、押した先で数が
/// 変わらない)。0 件の種別は出さない。
struct CrossTabCountChips: View {
    /// 打った語。空なら何も出さない。
    let query: String
    /// いま見ているタブ (自分自身は出さない)。
    let from: RootTab

    @State private var counts = CrossTabSearchCounts()

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.sp3) {
                        // 上のスコープ列 (「ほかに」) と同じ形の見出しを置く。
                        // 見出しが無いと、同じ見た目のチップ列が 2 段あるだけになり、
                        // 「絞り込む対象を変える」のか「別の画面へ移る」のかが読めない。
                        Text("別のタブ")
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                        ForEach(suggestions, id: \.tab) { item in
                            ImasFilterChip(text: "\(item.tab.label)に \(item.count)", isSelected: false) {
                                AppAnalytics.tap("cross_tab_search.jump")
                                CrossTabSearch.shared.hand(query, to: item.tab)
                            }
                        }
                    }
                    .padding(.horizontal, DS.sp5)
                    .padding(.vertical, DS.sp2)
                }
            }
        }
        // 打鍵ごとにコアへ 1 往復 (数えるだけなので実体は運ばない)。
        .task(id: query) { await reload() }
    }

    private var suggestions: [(tab: RootTab, count: Int)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return RootTab.searchable.compactMap { tab in
            guard tab != from else { return nil }
            let n = count(for: tab)
            return n > 0 ? (tab, n) : nil
        }
    }

    private func count(for tab: RootTab) -> Int {
        switch tab {
        case .events: return counts.events
        case .songs: return counts.songs
        case .idols: return counts.idols
        default: return 0
        }
    }

    private func reload() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            counts = CrossTabSearchCounts()
            return
        }
        counts = (try? await AppContainer.shared.globalSearchReading.counts(query: trimmed))
            ?? CrossTabSearchCounts()
    }
}
