import SwiftUI

// =============================================================================
// 会場の行と札 (docs/DESIGN_SYSTEM.md §5.4・§5.5・§6.7〜§6.10)
//
// ImasStubRow      半券の行。左の半券に日付 (月・日・曜日)、切り取り線、右に題と会場。
//                  ライブ・公演・記録の一覧の 1 行。
// ImasTicketRow    半券の形の短い行 (チケットの受付・取り込みの誘い)。左に記号、右に〆切。
// ImasPass         入場証 (担当・アカウント)。上の帯が実体の色、ストラップの穴、名前を大きく。
// ImasTicketStack  参加予定のチケットの束。いちばん上を大きく、後ろの 2 枚は端だけ見せる。
//                  横に払って次のチケットへ。
// ImasIdolHeader   アイドル詳細の頭。名札 (色の帯・名前・担当) と電光掲示板を 1 枚につなげる。
// ImasIdolCell     アイドルの名札 (格子の 1 つ)。上の帯が担当色。担当は帯と枠が点く。
// ImasBrandPicker  ブランドを選ぶ。チップを折り返して並べる (ペンライト、ロゴを入れたブランドはロゴ)。
// =============================================================================

// MARK: - 半券の日付

/// 半券の日付欄の中身。月の略号と曜日はコア (`ticketStubDate`) が決める。
struct ImasStubDate: Hashable {
    enum Kind: Hashable { case weekday, saturday, sunday, unknown }

    var top: String
    var big: String
    var bottom: String
    var kind: Kind

    init(top: String, big: String, bottom: String, kind: Kind = .unknown) {
        self.top = top
        self.big = big
        self.bottom = bottom
        self.kind = kind
    }

    /// `yyyy-MM-dd` (年月だけ・年だけも可) から。
    init(_ date: String) {
        let stub = ticketStubDate(date: date)
        self.top = stub.top
        self.big = stub.big
        self.bottom = stub.bottom
        switch stub.weekdayKind {
        case .weekday: kind = .weekday
        case .saturday: kind = .saturday
        case .sunday: kind = .sunday
        case .unknown: kind = .unknown
        }
    }

    var weekdayColor: Color {
        switch kind {
        case .saturday: return DS.saturday
        case .sunday: return DS.sunday
        case .weekday, .unknown: return DS.ink2
        }
    }
}

// MARK: - 半券の行

/// 半券の行。ライブ・公演・記録 (支出) の一覧の 1 行。
///
/// List の中に置くと、行の間を空けて地を透かす (行の区切り線は出さない)。行を引く操作は
/// 呼び出し側で `.imasSwipe` を付ける (右に引く = 参加・参加予定)。
struct ImasStubRow<Detail: View>: View {
    let date: ImasStubDate
    let title: String
    /// 会場・開演など。前にペンライト (ブランド) が付く。
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var badges: [ImasBadgeSpec] = []
    var emphasis: ImasRowEmphasis = .normal
    /// 合同ライブ等、単色で表せないとき、ペンライトを虹色にする。
    var rainbow: Bool = false
    /// 読み上げの日付 (「2026年11月7日 土曜日」)。無ければ日付欄をそのまま読む。
    var spokenDate: String? = nil
    /// 別画面へ進む矢印。`NavigationLink` に包んで OS が矢印を出す一覧では不要 (既定 false)。
    /// `Button` に包んで自前で矢印が要る一覧 (絞り込み結果など) だけ true にする。
    var showsChevron: Bool = false
    /// `detail` に free-form な見た目 (チップのボタンなど) を渡したとき、読み上げにも足したい文言。
    /// 題・副題・札だけでは伝わらない操作 (「セトリを見る」) をここで補う。
    var detailAccessibilityLabel: String? = nil
    /// 副題の行数。既定は 1 行。会場 + 補足などで長い行は 2 にする。
    var subtitleLineLimit: Int = 1
    @ViewBuilder var detail: Detail

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var stubWidth: CGFloat = 62

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                if !date.top.isEmpty {
                    Text(date.top).font(.imasMono(9.5, weight: .medium)).tracking(0.8).foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                Text(date.big)
                    .font(date.big.count > 3 ? ImasNumeralSize.medium.font : ImasNumeralSize.date.font)
                    .foregroundStyle(emphasis == .dimmed ? DS.ink3 : DS.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !date.bottom.isEmpty {
                    Text(date.bottom).font(.imasMono(9.5, weight: .medium)).tracking(0.8).foregroundStyle(date.weekdayColor)
                        .lineLimit(1)
                }
            }
            .frame(width: stubWidth)
            .padding(.vertical, 10)
            ImasPerforation(axis: .vertical, color: DS.perforation, lineWidth: 2)
                .padding(.vertical, 8)
            // 実体 (ブランド) の色は行頭の帯で示す (点は幅を取るだけなので使わない)。
            if seed != nil || brand != nil {
                ImasLeadBar(seed: seed, brand: brand, rainbow: rainbow)
                    .padding(.vertical, 12)
                    .padding(.leading, 10)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.imasHeading(14.5, weight: .heavy))
                    .foregroundStyle(emphasis == .dimmed ? DS.ink3 : DS.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(subtitleLineLimit)
                }
                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(badges) { b in ImasBadge(text: b.text, kind: b.kind, seed: b.seed) }
                    }
                }
                detail
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                ImasRowChevron()
                    .padding(.trailing, 14)
            }
        }
        .background(DS.surface, in: ImasTicketShape(cornerRadius: 12, cut: .verticalFromLeading(stubWidth + 1), notchRadius: 6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([spokenDate ?? [date.top, date.big, date.bottom].joined(separator: " "),
                             title, subtitle,
                             badges.isEmpty ? nil : badges.map(\.text).joined(separator: "、"),
                             detailAccessibilityLabel].compactMap { $0 }.joined(separator: "、"))
        .listRowInsets(EdgeInsets(top: 4, leading: DS.Space.screen, bottom: 4, trailing: DS.Space.screen))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

extension ImasStubRow where Detail == EmptyView {
    init(date: ImasStubDate, title: String, subtitle: String? = nil, seed: String? = nil, brand: String? = nil,
         badges: [ImasBadgeSpec] = [], emphasis: ImasRowEmphasis = .normal,
         rainbow: Bool = false, spokenDate: String? = nil, showsChevron: Bool = false) {
        self.init(date: date, title: title, subtitle: subtitle, seed: seed, brand: brand,
                  badges: badges, emphasis: emphasis, rainbow: rainbow, spokenDate: spokenDate,
                  showsChevron: showsChevron) { EmptyView() }
    }
}

// MARK: - 半券の形の短い行

/// 半券の形の短い行。チケットの受付 (〆切)・取り込みの誘いなど「紙で持つもの」の 1 行。
struct ImasTicketRow: View {
    var systemImage: String = "ticket"
    let title: String
    var subtitle: String? = nil
    /// 右の印字 (〆切の日付・時刻)。`isUrgent` なら朱。
    var deadline: String? = nil
    var isUrgent: Bool = false
    /// 押すと進む (矢印を出す)。
    var action: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 44

    var body: some View {
        let content = HStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.imasScaled(18, weight: .regular))
                .foregroundStyle(DS.ticketInk)
                .frame(width: iconColumn)
            ImasPerforation(axis: .vertical, color: DS.ticketDash, lineWidth: 2)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.imasHeading(14.5, weight: .bold)).foregroundStyle(DS.ticketInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.imasCaption).foregroundStyle(DS.ticketSub)
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 10)
            Spacer(minLength: DS.Space.gap)
            if let deadline {
                (Text("〆 ").font(.imasHeading(12, weight: .heavy)).foregroundStyle(DS.stamp)
                 + Text(deadline).font(.imasMono(12, weight: .bold)).foregroundStyle(isUrgent ? DS.stamp : DS.ticketInk))
                    .lineLimit(1)
                    .padding(.trailing, action == nil ? 14 : 4)
            }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.imasScaled(12, weight: .semibold))
                    .foregroundStyle(DS.ticketSub)
                    .padding(.trailing, 14)
            }
        }
        .background(DS.ticket, in: ImasTicketShape(cornerRadius: 12, cut: .verticalFromLeading(iconColumn + 1), notchRadius: 6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if let action {
            Button(action: action) { content }.buttonStyle(.imasPress)
        } else {
            content
        }
    }
}

// MARK: - 入場証

/// 入場証。担当・アカウントの顔。上の帯が実体の色で、ストラップを通す穴が開いている。
struct ImasPass<Trailing: View>: View {
    /// 帯の左右の印字 (「PRODUCER PASS」「担当」)。
    var leftImprint: String
    var rightImprint: String? = nil
    let title: String
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var onOpen: (() -> Void)? = nil
    /// 名前の右 (数・バーコード・矢印)。
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let band = t.isNeutral ? DS.sys : t.accent
        let onBand = t.isNeutral ? DS.onSys : t.onAccent
        let content = VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack {
                    Text(leftImprint).imasText(.imprint, color: onBand.opacity(0.9))
                    Spacer(minLength: 60)
                    if let rightImprint { Text(rightImprint).imasText(.imprint, color: onBand.opacity(0.9)) }
                }
                .padding(.horizontal, 16)
                Capsule().fill(DS.bg).frame(width: 44, height: 10)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.18), lineWidth: 1))
                    .accessibilityHidden(true)
            }
            .frame(height: 44)
            .background(band)
            HStack(alignment: .bottom, spacing: DS.Space.gapLoose) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.imasHeading(28, weight: .heavy))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle).font(.imasFootnote).foregroundStyle(DS.ink2).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .imasSurfaceEdge(cornerRadius: DS.rCard)
        .accessibilityElement(children: .combine)

        if let onOpen {
            Button(action: onOpen) { content }.buttonStyle(.imasPress)
        } else {
            content
        }
    }
}

extension ImasPass where Trailing == EmptyView {
    init(leftImprint: String, rightImprint: String? = nil, title: String, subtitle: String? = nil,
         seed: String? = nil, brand: String? = nil, onOpen: (() -> Void)? = nil) {
        self.init(leftImprint: leftImprint, rightImprint: rightImprint, title: title, subtitle: subtitle,
                  seed: seed, brand: brand, onOpen: onOpen) { EmptyView() }
    }
}

/// 入場証の右に並べる小さな数 (「12 回収」「4 参加」)。
struct ImasPassStats: View {
    let items: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .trailing, spacing: 3) {
                    Text(item.value).font(ImasNumeralSize.large.font).foregroundStyle(DS.ink)
                    Text(item.label).font(.imasCaption2).foregroundStyle(DS.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - チケットの束

/// 参加予定のチケットの束。いちばん上のチケットを大きく、後ろの 2 枚は下の端だけを見せる。
/// 束を横に払うと次のチケットが上に来る。1 枚なら束にしない。
struct ImasTicketStack: View {
    struct Item: Identifiable {
        let id: String
        let ticket: ImasTicket
        /// 後ろに回ったときに端に出す 1 行 (「11.08 SUN · 標 FINAL DAY2 · 38 DAYS」)。
        let edge: String
    }

    let items: [Item]
    @State private var front = 0

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let ordered = (0..<items.count).map { items[($0 + front) % items.count] }
            ZStack(alignment: .bottom) {
                ForEach(Array(ordered.dropFirst().prefix(2).enumerated()).reversed(), id: \.element.id) { depth, item in
                    edgeStrip(item.edge, depth: depth + 1)
                }
                ordered[0].ticket
                    .padding(.bottom, CGFloat(min(items.count - 1, 2)) * 20)
                    .id(ordered[0].id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .gesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    guard items.count > 1, abs(value.translation.width) > 50,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(.imasStandard) {
                        front = value.translation.width < 0 ? (front + 1) % items.count : (front + items.count - 1) % items.count
                    }
                }
            )
            .sensoryFeedback(.selection, trigger: front)
            .accessibilityAction(named: "次のチケット") {
                withAnimation(.imasStandard) { front = (front + 1) % items.count }
            }
        }
    }

    private func edgeStrip(_ text: String, depth: Int) -> some View {
        HStack {
            Text(text)
                .font(.imasMono(10, weight: .medium))
                .foregroundStyle(DS.ticketSub)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(height: 70, alignment: .bottom)
        .background(DS.ticket, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .brightness(depth == 1 ? -0.02 : -0.05)
        .padding(.horizontal, CGFloat(depth) * 8)
        .padding(.bottom, CGFloat(2 - depth) * 20)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - アイドル詳細の頭

/// アイドル詳細の頭。名札 (色の帯・アイコン・名前・よみと CV・担当の印) と、その下につなげた電光掲示板。
/// アイコンはいつも出す (写真があれば写真、無ければ判子)。右下には写真を選ぶ口 (`ImasIconBadge`) などを重ねる。
struct ImasIdolHeader<IconAccessory: View>: View {
    /// 名札の上の印字 (ブランド名)。
    var imprint: String
    /// 印字を押したとき (ブランドで絞ったアイドル一覧へ)。nil なら押せない。
    var onImprintTap: (() -> Void)? = nil
    let name: String
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    /// 判子に入れる短い名前。nil なら `name`。
    var iconLabel: String? = nil
    var imageURL: URL? = nil
    let isPick: Bool
    var onTogglePick: (() -> Void)? = nil
    /// 名前を長押ししたときのコピー (名前・よみ・CV)。
    var copyItems: [CopyItem] = []
    var stats: [ImasBoard.Cell] = []
    /// アイコンの右下に重ねるもの (写真を選ぶ口)。
    @ViewBuilder var iconAccessory: IconAccessory

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let color = t.isNeutral ? DS.ink : t.penlight
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(t.isNeutral ? DS.sys : t.accent).frame(width: 8)
                HStack(spacing: DS.Space.gapLoose) {
                    ImasAvatar(label: iconLabel ?? name, seed: seed, brand: brand, size: 72, isPick: isPick,
                               imageURL: imageURL)
                        .overlay(alignment: .bottomTrailing) { iconAccessory }
                    VStack(alignment: .leading, spacing: 4) {
                        imprintView
                        Text(name).font(.imasHeading(28, weight: .heavy)).foregroundStyle(DS.ink)
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .imasCopyable(copyItems)
                        if let subtitle {
                            // 1 行に入らないときは「 · 」の区切りで行を分ける (日付の途中で折り返さない)。
                            ViewThatFits(in: .horizontal) {
                                Text(subtitle).lineLimit(1)
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(subtitle.components(separatedBy: " · ").enumerated()), id: \.offset) { _, part in
                                        Text(part).lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                }
                            }
                            .font(.imasCaption).foregroundStyle(DS.ink2)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                Spacer(minLength: 0)
                if let onTogglePick {
                    ImasPerforation(axis: .vertical, color: DS.perforation).padding(.vertical, 12)
                    Button(action: onTogglePick) {
                        VStack(spacing: 4) {
                            Image(systemName: isPick ? "heart.fill" : "heart")
                                .font(.imasScaled(20, weight: isPick ? .semibold : .regular))
                                .symbolEffect(.bounce, value: isPick)
                            Text("担当").font(.imasCaption2.weight(.heavy))
                        }
                        .foregroundStyle(isPick ? color : DS.ink3)
                        .frame(width: 64)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.imasPress)
                    .sensoryFeedback(.impact(weight: .medium), trigger: isPick)
                    .accessibilityLabel(isPick ? "担当から外す" : "担当にする")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(DS.surface)
            if !stats.isEmpty {
                // 電光掲示板は角の丸い板なので、名札と接する上の角は板の色で埋めて四角くつなげる。
                ImasBoard(cells: stats)
                    .background(DS.board)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: DS.rCard, bottomTrailingRadius: DS.rCard,
                                                      style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .imasSurfaceEdge(cornerRadius: DS.rCard)
    }

    @ViewBuilder private var imprintView: some View {
        if let onImprintTap {
            Button(action: onImprintTap) {
                Text(imprint).imasText(.imprint, color: DS.ink2).lineLimit(1)
            }
            .buttonStyle(.imasPress)
            .accessibilityHint("このブランドのアイドルを見る")
        } else {
            Text(imprint).imasText(.imprint, color: DS.ink3).lineLimit(1)
        }
    }
}

extension ImasIdolHeader where IconAccessory == EmptyView {
    init(imprint: String, onImprintTap: (() -> Void)? = nil, name: String, subtitle: String? = nil,
         seed: String? = nil, brand: String? = nil, iconLabel: String? = nil, imageURL: URL? = nil,
         isPick: Bool, onTogglePick: (() -> Void)? = nil, copyItems: [CopyItem] = [],
         stats: [ImasBoard.Cell] = []) {
        self.init(imprint: imprint, onImprintTap: onImprintTap, name: name, subtitle: subtitle, seed: seed,
                  brand: brand, iconLabel: iconLabel, imageURL: imageURL, isPick: isPick,
                  onTogglePick: onTogglePick, copyItems: copyItems, stats: stats) { EmptyView() }
    }
}

// MARK: - アイドルの名札 (格子)

/// アイドルの名札。格子に並べる (iPhone は 4 列)。上の帯が担当色、その下にアイコン (写真か判子)・名前・並べ替えの値。
/// 担当はアイコンの輪が二重になる。選ぶ格子 (ピッカー) では枠が点き、右上に選択の印。
struct ImasIdolCell: View {
    let name: String
    var kana: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    /// 判子に入れる短い名前。nil なら `name`。
    var iconLabel: String? = nil
    var imageURL: URL? = nil
    var isPick: Bool = false
    /// 並べ替えの値 (「158cm」「17歳」)。何順に並んでいるかを名札から読めるようにする。nil なら出さない。
    var metric: String? = nil
    /// 選ぶ格子 (ピッカー) のときの選択。nil なら選択の印を出さない。
    var isSelected: Bool? = nil
    var iconSize: CGFloat = 52

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let band = t.isNeutral ? DS.sys : t.accent
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            Rectangle().fill(band).frame(height: 5)
            VStack(spacing: 4) {
                ImasAvatar(label: iconLabel ?? name, seed: seed, brand: brand, size: iconSize, isPick: isPick,
                           imageURL: imageURL)
                Text(name).font(.imasHeading(12.5, weight: .heavy)).foregroundStyle(DS.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let kana {
                    Text(kana).font(.imasCaption2).foregroundStyle(DS.ink3).lineLimit(1).minimumScaleFactor(0.7)
                }
                if let metric {
                    Text(metric).font(.imasMono(10.5, weight: .semibold)).foregroundStyle(DS.ink3).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 7)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity)
        }
        .background(DS.surface, in: shape)
        .clipShape(shape)
        .overlay {
            if isSelected == true {
                shape.strokeBorder(t.isNeutral ? DS.ink : t.penlight, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let isSelected {
                ImasSelectionMark(isSelected: isSelected, seed: seed, brand: brand, size: 18)
                    .padding(.top, 9)
                    .padding(.trailing, 5)
            }
        }
        .imasSurfaceEdge(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([name, isPick ? "担当" : nil, metric].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}

/// 名札の格子 (iPhone は 4 列、iPad は画面で 6 列を渡す)。
struct ImasIdolGrid<Content: View>: View {
    var columns: Int = 4
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.gap), count: columns),
                  spacing: DS.Space.gap) {
            content
        }
    }
}

// MARK: - ブランドを選ぶ

/// ブランドを選ぶ。チップを折り返して並べる。先頭はペンライト、ロゴを読み込んだブランドはロゴ。
/// `includesAll` で先頭に「すべて」(何も選ばない = 全部) を置く。
struct ImasBrandPicker: View {
    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
        /// ブランドの色 (hex)。
        var color: String? = nil
        /// 読み込んだロゴ (端末の中のファイル)。
        var logoURL: URL? = nil
    }

    let options: [Option]
    @Binding var selection: Set<String>
    var includesAll: Bool = true
    /// 「全部選んでいない」チップの文言。画面ごとの言葉づかいに合わせて渡せる (既定「すべて」)。
    var allLabel: String = "すべて"
    var allowsMultiple: Bool = true

    var body: some View {
        ImasChipFlow {
            if includesAll {
                ImasFilterChip(text: allLabel, isSelected: selection.isEmpty) {
                    selection = []
                }
            }
            ForEach(options) { option in
                ImasFilterChip(text: option.label, isSelected: selection.contains(option.id), brand: option.color,
                               leading: option.logoURL.map { .logo($0) } ?? .dot) {
                    toggle(option.id)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if allowsMultiple {
            if !selection.insert(id).inserted { selection.remove(id) }
        } else {
            selection = selection.contains(id) && includesAll ? [] : [id]
        }
    }
}
