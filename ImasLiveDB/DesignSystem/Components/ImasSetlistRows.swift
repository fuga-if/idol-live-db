import SwiftUI

// =============================================================================
// セトリと予想の行 (docs/DESIGN_SYSTEM.md §5.6・§5.8)
//
// ImasSetlistRow  セトリの 1 曲。曲順・ジャケ・曲名・歌唱者・役割の札・事実 (初披露・回収)。
//                 回収した曲はジャケの角に小さな判子 (場所を取らない)。
// ImasForecastRow 予想・機械予測の 1 曲。順位・ジャケ・曲名・根拠・確率 (または票)。
//                 推測なので確率は「%」付きで出し、事実の行 (セトリ) と同じ札を使わない。
//
// どちらもデータは素の値で受け取る (画面の ViewModel が組む)。見た目だけを持つ。
// =============================================================================

/// 歌唱者 1 人ぶんの表示データ。
struct ImasPerformer: Identifiable, Hashable {
    var id: String
    var name: String
    /// イメージカラーの hex。
    var color: String?
    /// 欠席 (オリメンだがこの公演に出ない)。
    var isAbsent: Bool = false
}

// MARK: - セトリの 1 曲

struct ImasSetlistRow: View {
    /// 曲順 (「01」)。MC・幕間は nil にして `interlude` を渡す。
    var number: String?
    let title: String
    /// ジャケ。無い曲は灰の面に音符。
    var artworkURL: URL? = nil
    /// ジャケが無いときの色の手がかり (曲の実体)。
    var seed: String? = nil
    var brand: String? = nil
    var performers: [ImasPerformer] = []
    /// 歌唱者が多いとき (全体曲) に名前の代わりに出す要約 (「全員」「13 人」)。
    var performerSummary: String? = nil
    /// 役割の札 (ユニット・全員・カバー・一部・主演・ゲスト)。
    var badges: [ImasBadgeSpec] = []
    /// 下段の事実 (「初披露」「12 回目」「回収」)。
    var facts: [String] = []
    /// 自分がこの曲を現地で聴いた。
    var isCollected: Bool = false
    /// 歌唱者の名前を何人まで並べるか。超えたら要約に替える。
    var performerLimit: Int = 6

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ImasRow(
            title: title,
            leading: .numberedArtwork(number: number ?? "", title: title, seed: seed, brand: brand,
                                      imageURL: artworkURL, isCollected: isCollected)
        ) {
            if !performers.isEmpty || performerSummary != nil {
                performerLine
            }
            if !badges.isEmpty || !facts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges) { b in ImasBadge(text: b.text, kind: b.kind, seed: b.seed) }
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                        Text(fact)
                            .font(fact == Self.firstPerformance ? .imasCaption.weight(.heavy) : .imasCaption)
                            .foregroundStyle(fact == Self.firstPerformance ? DS.ink : DS.ink2)
                    }
                }
            }
        }
    }

    /// 事実のうち、墨で強める言葉。
    static let firstPerformance = "初披露"

    /// 歌唱者。人数が多いときは名前の代わりにペンライトを並べて人数を添える (全体曲)。
    @ViewBuilder private var performerLine: some View {
        if performers.count > performerLimit || (performers.isEmpty && performerSummary != nil) {
            HStack(spacing: 6) {
                if !performers.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(performers.prefix(24)) { p in
                            ImasPenlight(color: p.color == nil ? DS.ink3
                                         : ImasTheme.derive(seed: p.color, brand: nil, scheme: scheme).penlight,
                                         size: .small)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text(performerSummary ?? "\(performers.count) 人").imasText(.rowSubtitle)
            }
        } else {
            FlowLayout(spacing: 10) {
                ForEach(performers) { p in
                    ImasPerformerChip(name: p.name, seed: p.color, isAbsent: p.isAbsent)
                }
            }
        }
    }
}

/// 札 1 枚ぶんのデータ (行の部品に並べて渡す)。
struct ImasBadgeSpec: Identifiable, Hashable {
    var id: String { "\(text)-\(kind)" }
    var text: String
    var kind: ImasBadge.Kind
    var seed: String? = nil
}

// MARK: - 予想・機械予測の 1 曲

struct ImasForecastRow: View {
    enum Measure {
        /// 機械予測の確率 (0〜1)。
        case probability(Double)
        /// みんなの予想の票数と、いちばん多い票数に対する割合 (0〜1)。
        case votes(Int, share: Double)
    }

    let rank: Int
    let title: String
    var artworkURL: URL? = nil
    /// ジャケが無いときの面の色 (曲のブランド色 hex)。
    var brand: String? = nil
    /// 曲でなくアイドル・ユニットの予想 (お題の投票) のとき。写真があれば写真、無ければ色の帯。
    var avatar: (label: String, imageURL: URL?, seed: String?)? = nil
    let measure: Measure
    /// 根拠の見出し (「オリメン」「理由」)。
    var reasonLabel: String? = nil
    /// 根拠の文 (「2/3 が出演」「ソロの代表曲」)。
    var reason: String? = nil
    /// 根拠の人 (オリメン)。欠席は薄字と取り消し線。
    var performers: [ImasPerformer] = []
    /// 自分が予想したか。
    var isMine: Bool = false
    /// 「予想する」の押し場所。nil なら出さない (機械予測)。
    var onVote: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.rowGap) {
            ImasRankNumber(rank: rank)
                .padding(.top, 10)
            if let avatar {
                if let url = avatar.imageURL {
                    ImasAvatar(label: avatar.label, seed: avatar.seed, brand: brand, size: 40, imageURL: url,
                               reservesPickRing: false)
                } else {
                    ImasLeadBar(seed: avatar.seed, brand: brand).frame(height: 36)
                }
            } else {
                ImasArtwork(title: title, seed: nil, brand: brand, size: 44, imageURL: artworkURL)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                    Text(title)
                        .imasText(.rowTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.gap)
                    measureView
                }
                if reason != nil || !performers.isEmpty {
                    reasonLine
                }
                ImasProportionLine(fraction: fraction)
                    .padding(.top, 2)
                if let onVote {
                    Button(action: onVote) {
                        Label(isMine ? "予想した" : "予想する", systemImage: isMine ? "checkmark" : "hand.thumbsup")
                    }
                    .buttonStyle(.imas(isMine ? .primary : .secondary, size: .small))
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowV)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double {
        switch measure {
        case let .probability(p): return p
        case let .votes(_, share): return share
        }
    }

    @ViewBuilder private var measureView: some View {
        switch measure {
        case let .probability(p):
            ImasMetric(value: "\(Int((p * 100).rounded()))", unit: "%", size: .medium, emphasized: rank <= 3)
        case let .votes(n, _):
            ImasMetric(value: "\(n)", unit: "票", size: .medium, emphasized: rank <= 3)
        }
    }

    private var reasonLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            if let reasonLabel {
                Text(reasonLabel)
                    .font(ImasTextRole.badge.font)
                    .foregroundStyle(DS.ink3)
                    .fixedSize()
            }
            if !performers.isEmpty {
                FlowLayout(spacing: 10) {
                    ForEach(performers) { p in
                        ImasPerformerChip(name: p.name, seed: p.color, isAbsent: p.isAbsent)
                    }
                    if let reason {
                        Text(reason).imasText(.rowSubtitle)
                    }
                }
            } else if let reason {
                Text(reason).imasText(.rowSubtitle).lineLimit(2)
            }
        }
    }
}
