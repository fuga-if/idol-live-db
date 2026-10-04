import SwiftUI

// =============================================================================
// セトリと予想の行 (docs/DESIGN_SYSTEM.md §5.6・§5.8)
//
// ImasSetlistRow  セトリの 1 曲。曲順・ジャケ・曲名・歌唱者・役割の札・事実 (初披露・回収)。
//                 回収は印にせず事実の札 (初回収など) で出す。
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
    /// 判子に入れる短い名前 (アイドルの略称)。アイドルでない人 (アイドル情報の無い歌唱者) は nil。
    var iconLabel: String? = nil
    /// 設定した写真。
    var imageURL: URL? = nil
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
    /// 歌唱者の名前を何人まで並べるか。超えたら要約に替える。
    var performerLimit: Int = 6
    /// ジャケの代わりに渡す試聴可能なジャケなど。渡すと `artworkURL` より優先する
    /// (曲順はそのまま左に置く)。DesignSystem はプレイヤー等のアプリサービスを知らないので、
    /// その配線は画面側が済ませたビューを渡す。
    var customArtwork: AnyView? = nil
    /// 曲名を押せるようにする (曲の詳細などへ)。nil なら押せない文字のまま。
    var onSelectTitle: (() -> Void)? = nil
    /// 歌唱者の表示を画面側で組みたいとき。渡すと `performers`/`performerSummary` より優先する
    /// (ユニット名義・全員などの定型以外で、行固有の組み方がどうしても要るときだけ使う)。
    var performersOverride: AnyView? = nil
    /// 歌唱者のアイコンの束 (`ImasAvatarStack`) を押したとき (歌唱者の一覧シートを開く)。
    var onSelectPerformers: (() -> Void)? = nil
    /// 担当 (マイピック) の強調。行の左端に細い帯を立てる。
    var highlightsPick: Bool = false
    /// 行の末尾 (Good ボタンなど)。
    var trailing: ImasRowTrailing = .none
    /// 歌唱者のアイコンの束の直径。文字サイズ設定に合わせて画面側が倍率をかけて渡す (既定 26)。
    var avatarSize: CGFloat = 26
    /// ジャケの一辺。文字サイズ設定に合わせて画面側が倍率をかけて渡す (既定 44)。
    var artworkSize: CGFloat = 44
    /// この披露についての事実を、軸 (披露・回収) ごとにまとめたもの。詳細表示のときだけ渡る。
    /// 軸の分け方・ラベル・順・強さ (`tone`) は imas-core (`SetlistRowMetaRecord`) が決める。
    var noteGroups: [SetlistRowNoteGroupRecord] = []
    /// 自由記述のメモ (MC・コメント等)。斜体の小さい文字で最後に添える。
    var note: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ImasRow(
            title: title,
            leading: leadingView,
            trailing: trailing,
            // セトリの曲名は折り返し優先で省略しない (全体曲の長い曲名も最後まで出す)。
            titleLineLimit: 99,
            onSelectTitle: onSelectTitle
        ) {
            if let performersOverride {
                performersOverride
            } else if !performers.isEmpty || performerSummary != nil {
                performerLine
            }
            // 横一列 (HStack) ではなく回り込み (FlowLayout) にしてある。幅が足りないとき、
            // HStack は札の中の文字を折り返すので「1 年 1 か月 / ぶり」と割れて読めなくなる。
            // 回り込みなら札ごと次の行に落ちる (札は ideal size で置かれるので中では折れない)。
            if !badges.isEmpty || !facts.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(badges) { b in
                        // 「全員」だけは押せる (歌唱者の一覧シートを開く)。他の札はただの表示。
                        if b.kind == .all, let onSelectPerformers {
                            Button(action: onSelectPerformers) {
                                ImasBadge(text: b.text, kind: b.kind, seed: b.seed)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ImasBadge(text: b.text, kind: b.kind, seed: b.seed)
                        }
                    }
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                        Text(fact)
                            .font(fact == Self.firstPerformance ? .imasCaption.weight(.heavy) : .imasCaption)
                            .foregroundStyle(fact == Self.firstPerformance ? DS.ink : DS.ink2)
                    }
                }
            }
            if !noteGroups.isEmpty {
                noteGroupsBlock
            }
            if let note {
                Text(note).imasText(.note).italic()
            }
        }
        .overlay(alignment: .leading) {
            if highlightsPick {
                RoundedRectangle(cornerRadius: DS.Size.leadBar / 2, style: .continuous)
                    .fill(DS.pick.opacity(0.7))
                    .frame(width: DS.Size.leadBar)
                    .padding(.vertical, DS.Space.gap)
            }
        }
    }

    /// 曲順 + ジャケの先頭。曲名は押せるときだけボタンにする (読み上げの題はそのまま行が持つ)。
    private var leadingView: ImasRowLeading {
        guard let customArtwork else {
            return .numberedArtwork(number: number ?? "", title: title, seed: seed, brand: brand,
                                    imageURL: artworkURL)
        }
        let combined = HStack(alignment: .top, spacing: 10) {
            Text(number ?? "")
                .font(.imasMono(11.5, weight: .bold))
                .foregroundStyle(DS.ink2)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 2)
            customArtwork
        }
        // 前と同じく上揃え (曲順・ジャケ・Good を縦の真ん中に寄せない)。
        return .custom(AnyView(combined), width: 24 + 10 + artworkSize, alignment: .top)
    }

    /// 事実のうち、墨で強める言葉。
    static let firstPerformance = "初披露"

    /// 歌唱者。アイドルのアイコン (写真か判子) が分かる人がいれば束ねて見せる (アイコンを消さない)。
    /// アイコンが分からない人だけのときは名前のチップ、人数だけ多いときはペンライト + 人数。
    @ViewBuilder private var performerLine: some View {
        if performers.contains(where: { $0.iconLabel != nil || $0.imageURL != nil }) {
            ImasAvatarStack(people: performers, maxVisible: 5, size: avatarSize, onTap: onSelectPerformers)
        } else if performers.count > performerLimit || (performers.isEmpty && performerSummary != nil) {
            Text(performerSummary ?? "\(performers.count) 人").imasText(.rowSubtitle)
        } else {
            FlowLayout(spacing: 10) {
                ForEach(performers) { p in
                    ImasPerformerChip(name: p.name, seed: p.color, isAbsent: p.isAbsent)
                }
            }
        }
    }

    /// **この披露についての事実**の段。軸の名前を固定幅で左に置き、値を右に流す
    /// (丸い札を並べると「・」繋ぎの 1 行になって構造が消えるため)。
    private var noteGroupsBlock: some View {
        let accent = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme).accent
        return VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .fill(DS.sep)
                .frame(height: 0.5)
                .padding(.top, 3)
                .padding(.bottom, 2)
            ForEach(noteGroups, id: \.label) { group in
                noteGroupLine(group, accent: accent, showsDetail: group.label == noteGroups.last?.label)
            }
        }
    }

    /// 「13 人 初歌唱」「原唱 …」の誰が・誰がいないかは、歌唱者の一覧で見せる。入口は段の右下に小さく 1 つだけ
    /// (段ごとに矢印を並べない・大きなボタンにしない)。置くかはコアが決める (どれかの段が `opensPerformers`)。
    private var detailOpener: (() -> Void)? {
        noteGroups.contains(where: \.opensPerformers) ? onSelectPerformers : nil
    }

    /// 軸 1 本 (名前 + 値)。最後の段の右端に「詳しく」を添える。
    private func noteGroupLine(_ group: SetlistRowNoteGroupRecord, accent: Color, showsDetail: Bool) -> some View {
        // 軸の名前は値の 1 行目に、「詳しく」は値の最後の行に揃える。
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(group.label)
                    .font(.imasCaption2)
                    .kerning(0.4)
                    .foregroundStyle(DS.ink3)
                    .frame(width: 26, alignment: .leading)
                Self.notesText(group.notes, accent: accent)
                    .font(.imasCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsDetail, let open = detailOpener {
                Button(action: open) {
                    (Text("詳しく") + Text(" ") + Text(Image(systemName: "chevron.right")).font(.imasCaption2.weight(.semibold)))
                        .font(.imasCaption2.weight(.medium))
                        .foregroundStyle(DS.ink3)
                        .padding(.vertical, 4)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityHint("歌唱者の一覧を開く")
            }
        }
    }

    /// 1 つの軸の値を 1 本の `Text` に連結する。折り返すのは値と値の間だけ
    /// (値の中は `unbreakable` で繋ぐ。「13 / 人 初歌唱」のように値の途中で割れると読めない)。
    private static func notesText(_ notes: [SetlistRowNoteRecord], accent: Color) -> Text {
        notes.enumerated().reduce(Text("")) { acc, pair in
            let (index, note) = pair
            return acc + (index == 0 ? Text("") : Text("  ")) + noteText(note, accent: accent)
        }
    }

    /// 値 1 つを途中で折り返さない文字列にする。空白は改行しない空白に、字と字の間は
    /// 単語結合子で繋ぐ (日本語は字の間でも折り返せるため、空白だけでは足りない)。
    /// 名前の並び (`咲耶・摩美々・…`) は「・」の後ろでだけ折り返せるようにする (名前の途中で割らない)。
    /// それでも 1 行に収まらない長さのときは、OS が折り返す。
    static func unbreakable(_ text: String) -> String {
        var out = ""
        for (i, ch) in text.enumerated() {
            if i > 0, !out.hasSuffix("・") { out += "\u{2060}" }
            out += ch == " " ? "\u{00A0}" : String(ch)
        }
        return out
    }

    /// 事実 1 つの見え方。**判断はしない** — core が付けた `tone` に対応表を当てるだけ。
    /// 色だけで意味を分けると、色が見分けづらい人には全部同じ文字列に見える。
    /// 自分の記録 (回収 / 未回収) には印を付けて、色に頼らず分かるようにする。
    private static func noteText(_ note: SetlistRowNoteRecord, accent: Color) -> Text {
        switch note.tone {
        case .value:
            return Text(unbreakable(note.text)).font(.imasCaption.weight(.medium)).foregroundColor(DS.ink)
        case .detail:
            return Text(unbreakable(note.text)).foregroundColor(DS.ink3)
        case .debut:
            // 初披露・初歌唱。行でいちばん珍しい事実なので、太字 + 曲の色で一番強く出す。
            return Text(unbreakable(note.text)).font(.imasCaption.weight(.bold)).foregroundColor(accent)
        case .mine:
            return Text(Image(systemName: "checkmark"))
                .font(.imasCaption2.weight(.semibold))
                .foregroundColor(DS.successInk)
                + Text(" ")
                + Text(unbreakable(note.text)).font(.imasCaption.weight(.semibold)).foregroundColor(DS.successInk)
        case .missing:
            return Text(Image(systemName: "circle.dotted"))
                .font(.imasCaption2)
                .foregroundColor(DS.ink3)
                + Text(" ")
                + Text(unbreakable(note.text)).foregroundColor(DS.ink2)
        }
    }
}

/// 1 人ぶんの事実の札 (歌唱者の一覧で名前の下に並べる `オリメン` / `初歌唱`)。
/// **言葉も強さ (`tone`) も imas-core が決める** — ここは強さに札の見え方を当てるだけ。
/// 初歌唱 (`debut`) は墨の線で囲んで、灰の地のオリメンの札より先に目に入るようにする。
struct ImasNoteBadges: View {
    let notes: [SetlistRowNoteRecord]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                ImasBadge(text: note.text, kind: Self.kind(note.tone))
            }
        }
    }

    private static func kind(_ tone: RowNoteTone) -> ImasBadge.Kind {
        switch tone {
        case .debut: .attention
        case .mine: .positive
        case .value, .detail, .missing: .neutral
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
    /// 題の下に 1 行 (ユニット名・歌唱者など)。お題の投票は曲のときだけ渡す。
    var subtitle: String? = nil
    var artworkURL: URL? = nil
    /// ジャケが無いときの面の色 (曲のブランド色 hex)。
    var brand: String? = nil
    /// 曲でなくアイドルの予想 (お題の投票) のとき。写真があれば写真、無ければ判子。
    var avatar: (label: String, imageURL: URL?, seed: String?)? = nil
    /// 曲でなくユニットの予想のとき。登録画像とブランド色を自分で解決する (`avatar` より優先)。
    var unit: Unit? = nil
    /// 曲の試聴 URL。渡すとジャケのタップが曲詳細への遷移と別に試聴を切り替える
    /// (行全体のタップは呼び出し側の onTapGesture のまま)。
    var previewURL: URL? = nil
    /// いま試聴中か。
    var isPreviewing: Bool = false
    /// ジャケがタップされたとき。`previewURL` が無いときは使わない。
    var onPreviewTap: (() -> Void)? = nil
    let measure: Measure
    /// `measure` の割合バーを出すか。機械予測はいつも出す。みんなの投票は最多との比較が
    /// 無かった表示なので、お題の投票では外す。
    var showsProportionLine: Bool = true
    /// 根拠の見出し (「オリメン」「理由」)。
    var reasonLabel: String? = nil
    /// 根拠の文 (「2/3 が出演」「ソロの代表曲」)。
    var reason: String? = nil
    /// 根拠の人 (オリメン)。欠席は薄字と取り消し線。
    var performers: [ImasPerformer] = []
    /// 2 行目の根拠 (オリメンの行の下に「理由」を出すとき)。
    var secondReason: (label: String, text: String)? = nil
    /// 試聴。渡すとジャケを押して 30 秒の試聴を再生・停止できる。
    var preview: (url: URL, songId: String)? = nil
    /// 自分が予想したか。
    var isMine: Bool = false
    /// 「予想する」を押せないとき (残りの票が無い)。予想済みの取り消しは常に押せる。
    var isVoteDisabled: Bool = false
    /// 「予想する」を送っている最中。
    var isVoting: Bool = false
    /// 「予想する」の押し場所。nil なら出さない。
    var onVote: (() -> Void)? = nil
    /// 投票ボタンの文言 (お題の投票は「投票する」、予想は既定の「予想する」)。
    var voteLabel: String = "予想する"
    var votedLabel: String = "予想した"
    /// 読み上げだけ見た目の文言と変えたいとき (お題の投票はトグルなので「投票」「投票を取消」)。
    /// nil なら見た目の文言 (`voteLabel`/`votedLabel`) をそのまま読む。
    var voteAccessibilityLabel: String? = nil
    var votedAccessibilityLabel: String? = nil
    /// 投票ボタンだけを無効にする (残票切れ・他の行の処理中)。行のタップで詳細を開く操作はいつでも有効。
    /// (`isVoteDisabled` と違い、予想済みの取り消しも止める。お題の投票が使う)
    var voteDisabled: Bool = false
    /// 投票/取消の通信中 (`isVoting` と同じ。お題の投票が使う呼び名)。
    var isVoteLoading: Bool = false
    /// 別画面へ進む矢印。行のタップで遷移するときに出す。
    var showsChevron: Bool = false
    /// 行の読み上げを 1 つに合成してよいか。押せるもの (予想・投票のボタン、開く中身) を持つ行は
    /// この値に関わらず合成しない (合成すると中のボタンを読み上げから押せず、行のダブルタップで投票が走る)。
    /// `false` にすると押せるものが無くても要素を分ける (呼び出し側が行に「詳細を開く」操作を足すとき)。
    var combineAccessibility: Bool = true
    /// 「予想する」の横に並べる補助の操作 (歌唱メンバー予想の開閉など)。
    var accessory: AnyView? = nil
    /// 行の下に開く中身 (歌唱メンバー予想)。
    var expansion: AnyView? = nil

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            mainRow
            if let expansion {
                expansion
                    .padding(.leading, DS.Space.rowH + ImasRankNumber.width + DS.Space.rowGap)
                    .padding(.trailing, DS.Space.rowH)
                    .padding(.bottom, DS.Space.rowV)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // 押せるものを持つ行は要素を束ねない (束ねると中のボタンを読み上げから押せない)。
        if combineAccessibility && onVote == nil && expansion == nil {
            content.accessibilityElement(children: .combine)
        } else {
            content.accessibilityElement(children: .contain)
        }
    }

    private var mainRow: some View {
        HStack(alignment: .top, spacing: DS.Space.rowGap) {
            ImasRankNumber(rank: rank)
                .padding(.top, 10)
            leadingView
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                    Text(title)
                        .imasText(.rowTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.gap)
                    measureView
                    if showsChevron {
                        ImasRowChevron()
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ImasTextRole.rowSubtitle.font)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                if reason != nil || !performers.isEmpty {
                    reasonLine
                }
                if let secondReason {
                    basisLine(label: secondReason.label) {
                        Text(secondReason.text).imasText(.rowSubtitle).lineLimit(2)
                    }
                }
                if showsProportionLine {
                    ImasProportionLine(fraction: fraction)
                        .padding(.top, 2)
                }
                voteArea
            }
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowV)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leadingView: some View {
        if let unit {
            ImasUnitAvatar(unit: unit, size: 40)
        } else if let avatar {
            // アイドル・ユニットの候補は写真があれば写真、無ければ ImasAvatar 自身の判子
            // (アイコンを消さない。以前はここで帯だけに落としていた)。
            ImasAvatar(label: avatar.label, seed: avatar.seed, brand: brand, size: 40,
                       imageURL: avatar.imageURL, reservesPickRing: false)
        } else if let preview {
            ImasArtwork(title: title, seed: nil, brand: brand, size: 44, imageURL: artworkURL)
                .overlay { ImasPreviewOverlay(url: preview.url, songId: preview.songId, size: 44) }
        } else {
            ImasArtwork(title: title, seed: nil, brand: brand, size: 44, imageURL: artworkURL,
                        previewURL: previewURL, isPreviewing: isPreviewing, onPreview: onPreviewTap)
        }
    }

    /// 予想・投票のボタンと、その横の補助の操作。
    @ViewBuilder private var voteArea: some View {
        if onVote != nil || accessory != nil {
            HStack(spacing: DS.Space.gap) {
                if let onVote {
                    ImasButton(title: isMine ? votedLabel : voteLabel,
                               systemImage: isMine ? "checkmark" : "hand.thumbsup",
                               role: isMine ? .primary : .secondary, size: .small,
                               isLoading: isVoting || isVoteLoading, action: onVote)
                        // 予想済みの取り消しは残りの票に関わらず押せる (`isVoteDisabled`)。
                        // お題の投票は他の行の処理中なども含めてボタンごと止める (`voteDisabled`)。
                        .disabled(voteDisabled || (isVoteDisabled && !isMine))
                        .accessibilityLabel(isMine ? (votedAccessibilityLabel ?? votedLabel)
                                                   : (voteAccessibilityLabel ?? voteLabel))
                }
                if let accessory { accessory }
            }
            .padding(.top, 2)
        } else if isMine {
            // 投票できない状態 (締切後など) でも、自分が選んだことは押せない印で残す。
            Label(votedLabel, systemImage: "checkmark")
                .imasText(.badge, color: DS.ink2)
                .padding(.top, 2)
        }
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

    /// 見出し付きの根拠 1 行 (「理由」+ 文)。
    private func basisLine<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            Text(label)
                .font(ImasTextRole.badge.font)
                .foregroundStyle(DS.ink3)
                .fixedSize()
            content()
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

// MARK: - 試聴

/// ジャケに重ねる試聴の印。押すと 30 秒の試聴を再生・停止する。再生中は暗くして停止の記号。
struct ImasPreviewOverlay: View {
    let url: URL
    let songId: String
    var size: CGFloat = 44

    private var isPlaying: Bool { MusicKitService.shared.isPlaying(songId: songId) }

    var body: some View {
        Button {
            MusicKitService.shared.togglePreview(url: url, songId: songId)
        } label: {
            ZStack {
                if isPlaying {
                    RoundedRectangle(cornerRadius: DS.rArtwork(size), style: .continuous)
                        .fill(Color.black.opacity(0.4))
                }
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.imasScaled(size * 0.25))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "試聴を止める" : "試聴する")
    }
}
