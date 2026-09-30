import SwiftUI

/// ティアー表の編集画面。
///
/// 動かし方は 2 通り: ①タップで選ぶ → 下のバーで段を押す ②長押しでつかんで段へドラッグ。
/// 片手でも確実に動かせる①を主にして、②は慣れた人向けの近道。
struct TierListView: View {
    let subject: SortMakerSubject

    @State private var store = TierListStore.shared
    @State private var board: TierListBoard
    @State private var items: [String: SortMakerItem] = [:]
    @State private var selectedId: String?
    @State private var detail: DetailDestination?
    @State private var showShare = false
    @State private var confirmReset = false
    @State private var moveFeedback = 0
    @Environment(\.colorScheme) private var scheme

    private let tiers = tierListTiers()

    init(board: TierListBoard) {
        self.subject = board.subject
        _board = State(initialValue: board)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp4) {
                Text(board.scopeLabel).font(.imasCaption).foregroundStyle(DS.ink3)
                VStack(spacing: 2) {
                    ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                        tierRow(index: index, tier: tier)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                unplacedSection
                Text("タップで選んで下のボタンで段を選ぶか、長押しでつかんで段まで運んでください。")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.sp5)
            .padding(.bottom, selectedId == nil ? 0 : 88)
        }
        .background(DS.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let id = selectedId, let item = items[id] {
                moveBar(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedId)
        .navigationTitle(subject.tierTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    AppAnalytics.tap("tier_list.share")
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("シェア")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if board.suggested != nil {
                        Button("ソート結果のたたき台に戻す", systemImage: "arrow.counterclockwise") {
                            update { $0.placements = $0.suggested ?? [:] }
                        }
                    }
                    Button("全部を未分類に戻す", systemImage: "tray", role: .destructive) { confirmReset = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("その他")
            }
        }
        .confirmationDialog("全部を未分類に戻しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("未分類に戻す", role: .destructive) { update { $0.placements = [:] } }
        }
        .sheet(item: $detail) { DetailSheetView(destination: $0) }
        .sheet(isPresented: $showShare) {
            TierListShareSheet(board: board, items: items, tiers: tiers)
        }
        .sensoryFeedback(.selection, trigger: moveFeedback)
        .task {
            let loaded = await SortMakerCandidates.load(subject, ids: board.itemIds)
            items = Dictionary(loaded.compactMap { $0.map { ($0.id, $0) } }, uniquingKeysWith: { a, _ in a })
        }
        .trackScreen("tier_list")
    }

    // MARK: - 段

    private func tierRow(index: Int, tier: TierListTier) -> some View {
        let theme = ImasTheme.derive(seed: tier.colorSeed, scheme: scheme)
        let ids = board.ids(inTier: index)
        return HStack(alignment: .top, spacing: 0) {
            Button {
                if let id = selectedId { move(id, to: index) }
            } label: {
                Text(tier.label)
                    .font(.imasScaled(24, weight: .black))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 56)
                    .frame(maxHeight: .infinity)
                    .background(theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(selectedId == nil)
            .accessibilityLabel("\(tier.label)ランク \(ids.count)件")
            .accessibilityHint(selectedId == nil ? "" : "選んだものをここへ移す")

            itemsFlow(ids, emptyText: selectedId == nil ? nil : "ここへ移す")
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .background(DS.surface)
                .contentShape(Rectangle())
                .onTapGesture { if let id = selectedId { move(id, to: index) } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .dropDestination(for: String.self) { dropped, _ in
            // 他のアプリから運ばれた文字列は受けない。
            guard let id = dropped.first, board.itemIds.contains(id) else { return false }
            move(id, to: index)
            return true
        }
    }

    private var unplacedSection: some View {
        let ids = board.unplacedIds
        return VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text("未分類").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                Text("\(ids.count)").font(.imasCaption).foregroundStyle(DS.ink3).monospacedDigit()
                Spacer()
            }
            itemsFlow(ids, emptyText: ids.isEmpty ? "全部振り分けました" : nil)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { if let id = selectedId { move(id, to: nil) } }
                .dropDestination(for: String.self) { dropped, _ in
                    // 他のアプリから運ばれた文字列は受けない。
            guard let id = dropped.first, board.itemIds.contains(id) else { return false }
                    move(id, to: nil)
                    return true
                }
        }
    }

    @ViewBuilder
    private func itemsFlow(_ ids: [String], emptyText: String?) -> some View {
        if ids.isEmpty {
            Text(emptyText ?? "")
                .font(.imasCaption).foregroundStyle(DS.ink3)
                .padding(DS.sp4)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    TierListChip(item: items[id], isSelected: selectedId == id)
                        .onTapGesture { tapChip(id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(selectedId == nil || selectedId == id ? "選んでから段を指定" : "選んだものをこの段へ移す")
                        .draggable(id) {
                            TierListChip(item: items[id], isSelected: true)
                        }
                        .contextMenu {
                            if let item = items[id] {
                                Button("詳細を見る", systemImage: "info.circle") { detail = item.detail }
                            }
                        }
                }
            }
            .padding(6)
        }
    }

    // MARK: - 移すバー

    private func moveBar(_ item: SortMakerItem) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text("「\(item.title)」をどこへ？")
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Spacer(minLength: DS.sp2)
                Button("やめる") { selectedId = nil }
                    .font(.imasSubhead).foregroundStyle(DS.ink2)
            }
            HStack(spacing: 6) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                    let theme = ImasTheme.derive(seed: tier.colorSeed, scheme: scheme)
                    Button { move(item.id, to: index) } label: {
                        Text(tier.label)
                            .font(.imasScaled(18, weight: .black))
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { move(item.id, to: nil) } label: {
                    Image(systemName: "tray")
                        .font(.imasScaled(16, weight: .semibold))
                        .foregroundStyle(DS.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("未分類へ")
            }
        }
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp3)
        .background(.bar)
    }

    /// チップのタップ。何か選んでいて別のチップを押したら、そのチップの段へ移す
    /// (段の中はチップで埋まるので、行の余白を押せと言っても押せない)。
    private func tapChip(_ id: String) {
        if let selected = selectedId, selected != id {
            move(selected, to: board.placements[id])
        } else {
            selectedId = selectedId == id ? nil : id
        }
    }

    // MARK: - 更新

    private func move(_ id: String, to tier: Int?) {
        moveFeedback += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            update { $0.placements[id] = tier }
            selectedId = nil
        }
    }

    private func update(_ change: (inout TierListBoard) -> Void) {
        change(&board)
        board.savedAt = Date()
        store.save(board)
    }
}

/// ティアー表の 1 枚 (ジャケ / アイコン + 名前)。
struct TierListChip: View {
    let item: SortMakerItem?
    let isSelected: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: item?.seed, brand: item?.brandId, scheme: scheme)
        VStack(spacing: 3) {
            Group {
                switch item {
                case .song(let song):
                    ArtworkImageView(url: song.artworkUrl.flatMap(URL.safeHTTP(string:)), size: 52,
                                     songTitle: song.title, songId: song.id)
                        .allowsHitTesting(false)
                case .idol(let idol):
                    IdolAvatarView(idol: idol, size: 52, reservesPickRing: false)
                case nil:
                    ImasArtwork(title: "?", size: 52)
                }
            }
            Text(item?.title ?? "")
                .font(.imasCaption2).foregroundStyle(DS.ink2)
                .lineLimit(1)
                .frame(width: 60)
        }
        .padding(3)
        .background(isSelected ? theme.tint : .clear, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rSM, style: .continuous)
                .stroke(theme.accent, lineWidth: isSelected ? 2.5 : 0)
        )
        .scaleEffect(isSelected ? 1.06 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item?.title ?? "不明")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// ティアー表の共有 (画像 / テキスト)。
struct TierListShareSheet: View {
    let board: TierListBoard
    let items: [String: SortMakerItem]
    let tiers: [TierListTier]

    private var title: String {
        board.subject == .song ? "好きな曲ティアー表" : "好きなアイドルティアー表"
    }

    private var rows: [(tier: TierListTier, names: [String])] {
        tiers.enumerated().map { i, t in (t, board.ids(inTier: i).compactMap { items[$0]?.title }) }
    }

    var body: some View {
        ShareCardSheet(title: "ティアー表をシェア", screenName: "tier_list_share") {
            VStack(spacing: DS.sp4) {
                ShareCardActionPane(card: { size in
                    TierListShareCard(title: title, scopeLabel: board.scopeLabel, rows: rows, size: size)
                })
                Button {
                    AppAnalytics.tap("tier_list.share_text")
                    let text = tierListShareText(title: title, scopeLabel: board.scopeLabel,
                                                 tiers: rows.map { TierListShareTier(label: $0.tier.label, names: $0.names) })
                    SystemShare.present(items: [text])
                } label: {
                    Label("テキストでシェア", systemImage: "text.alignleft")
                        .font(.imasSubhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// 画像カード。段ごとに色の札 + 名前を詰めて並べる (画像は載せない)。
struct TierListShareCard: View {
    let title: String
    let scopeLabel: String
    let rows: [(tier: TierListTier, names: [String])]
    var size: ShareCard.Size = ShareCard.portrait

    /// 1 段に載せる名前の上限。超えた分は「ほかN」。
    private let perTier = 8

    var body: some View {
        SoloShareScaffold(palette: ShareCardPalette(seed: rows.first?.tier.colorSeed), size: size, badge: title) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scopeLabel)
                    .font(.imasScaled(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.tier.label)
                            .font(.imasScaled(20, weight: .black))
                            .foregroundStyle(ShareInk.nearBlack)
                            .frame(width: 40, height: 40)
                            .background(ShareCardPalette(seed: row.tier.colorSeed).accent,
                                        in: RoundedRectangle(cornerRadius: 6))
                        FlowLayout(spacing: 5) {
                            ForEach(Array(row.names.prefix(perTier).enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.imasScaled(13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                            }
                            if row.names.count > perTier {
                                Text("ほか\(row.names.count - perTier)")
                                    .font(.imasScaled(12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.vertical, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    }
                }
            }
        }
    }
}
