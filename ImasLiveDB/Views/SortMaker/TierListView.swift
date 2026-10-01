import SwiftUI

/// ティアー表の編集画面。
///
/// 動かし方は 2 通り: ①タップで選ぶ → 下のバーで段を押す ②長押しでつかんで段へドラッグ。
/// 片手でも確実に動かせる①を主にして、②は慣れた人向けの近道。
/// 1 回動かすたびに端末へ保存する (一覧から何枚でも開き直せる)。
struct TierListView: View {
    let subject: SortMakerSubject

    @State private var store = TierListStore.shared
    @State private var board: TierListBoard
    @State private var items: [String: SortMakerItem] = [:]
    @State private var selectedId: String?
    @State private var detail: DetailDestination?
    @State private var showExport = false
    @State private var showEdit = false
    @State private var confirmReset = false
    @State private var moveFeedback = 0
    /// 未分類の絞り込み (全曲を入れても探せるように)。
    @State private var unplacedQuery = ""
    /// 未分類の検索用カタログ。照合規則はコア (`text_search_index`)。項目を読み込んだ時に 1 回組む。
    @State private var catalog: TextSearchCatalog?
    @Environment(\.colorScheme) private var scheme

    init(board: TierListBoard) {
        self.subject = board.subject
        _board = State(initialValue: board)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp4) {
                titleHeader
                VStack(spacing: 2) {
                    ForEach(board.tiers) { tier in
                        tierRow(tier)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                Button {
                    showEdit = true
                } label: {
                    Label("段を編集", systemImage: "slider.horizontal.3")
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink2)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                }
                .buttonStyle(.plain)
                unplacedSection
                Text("タップで選んで下のボタンで段を選ぶか、長押しでつかんで段まで運んでください。変えるたびに端末に保存されます。")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.sp5)
            .padding(.bottom, selectedId == nil ? 0 : 120)
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
                    AppAnalytics.tap("tier_list.export")
                    selectedId = nil
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("画像にする")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("名前と段を編集", systemImage: "pencil") { showEdit = true }
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
        .sheet(isPresented: $showExport) {
            TierListExportSheet(board: board, items: items)
        }
        .sheet(isPresented: $showEdit) {
            TierListEditSheet(board: board) { title, tiers in
                update {
                    $0.title = title
                    $0.tiers = tiers
                    // 消した段にいたものは未分類へ。
                    let ids = Set(tiers.map(\.id))
                    $0.placements = $0.placements.filter { ids.contains($0.value) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: moveFeedback)
        .task {
            let loaded = await SortMakerCandidates.load(subject, ids: board.itemIds)
            items = Dictionary(loaded.compactMap { $0.map { ($0.id, $0) } }, uniquingKeysWith: { a, _ in a })
            catalog = TextSearchCatalog(fieldsPerItem: board.itemIds.map { id in
                switch items[id] {
                case .song(let s): return [s.title, s.titleKana, s.singerLabel, s.unitName]
                case .idol(let i): return [i.name, i.nameKana, i.aliases]
                case nil: return []
                }
            })
        }
        .trackScreen("tier_list")
    }

    private var titleHeader: some View {
        Button {
            showEdit = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.sp2) {
                    Text(board.displayTitle)
                        .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .font(.imasScaled(13, weight: .semibold)).foregroundStyle(DS.ink3)
                }
                Text("\(board.scopeLabel) · \(board.placedCount) / \(board.itemIds.count) 振り分け済み")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("名前と段を編集")
    }

    // MARK: - 段

    private func tierRow(_ tier: TierDef) -> some View {
        let theme = ImasTheme.derive(seed: tier.colorSeed, scheme: scheme)
        let ids = board.ids(inTier: tier.id)
        return HStack(alignment: .top, spacing: 0) {
            Button {
                if let id = selectedId { move(id, to: tier.id) }
            } label: {
                TierLabelText(label: tier.label, large: 24, small: 14)
                    .padding(.horizontal, 4)
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 60)
                    .frame(maxHeight: .infinity)
                    .background(theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(selectedId == nil)
            .accessibilityLabel("\(tier.label) \(ids.count)件")
            .accessibilityHint(selectedId == nil ? "" : "選んだものをここへ移す")

            itemsFlow(ids, emptyText: selectedId == nil ? nil : "ここへ移す")
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .background(DS.surface)
                .contentShape(Rectangle())
                .onTapGesture { if let id = selectedId { move(id, to: tier.id) } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .dropDestination(for: String.self) { dropped, _ in
            // 他のアプリから運ばれた文字列は受けない。
            guard let id = dropped.first, board.itemIds.contains(id) else { return false }
            move(id, to: tier.id)
            return true
        }
    }

    /// 未分類のうち、絞り込みに当たるもの (並びは対象の並びのまま)。
    private var visibleUnplacedIds: [String] {
        let unplaced = board.unplacedIds
        let needle = unplacedQuery.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty, let catalog else { return unplaced }
        let hits = Set(catalog.filter(board.itemIds, needle: needle))
        return unplaced.filter { hits.contains($0) }
    }

    private var unplacedSection: some View {
        let total = board.unplacedIds.count
        let ids = visibleUnplacedIds
        return VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text("未分類").font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                Text(unplacedQuery.isEmpty ? "\(total)" : "\(ids.count) / \(total)")
                    .font(.imasCaption).foregroundStyle(DS.ink3).monospacedDigit()
                Spacer()
            }
            if total > 12 {
                ImasNameFilterField(prompt: subject == .song ? "曲名・歌唱で絞り込み" : "名前で絞り込み", text: $unplacedQuery)
            }
            unplacedGrid(ids, emptyText: total == 0 ? "全部振り分けました" : (ids.isEmpty ? "当てはまるものがありません" : nil))
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { if let id = selectedId { move(id, to: nil) } }
                .dropDestination(for: String.self) { dropped, _ in
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
                    chip(id)
                }
            }
            .padding(6)
        }
    }

    /// 未分類は数千件になりうる (全曲) ので、見えている分だけ描く格子にする。
    @ViewBuilder
    private func unplacedGrid(_ ids: [String], emptyText: String?) -> some View {
        if ids.isEmpty {
            Text(emptyText ?? "")
                .font(.imasCaption).foregroundStyle(DS.ink3)
                .padding(DS.sp4)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    chip(id)
                }
            }
            .padding(6)
        }
    }

    private func chip(_ id: String) -> some View {
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

    // MARK: - 移すバー

    private func moveBar(_ item: SortMakerItem) -> some View {
        // 段は最大 10。6 個ずつ折り返す (1 行に詰めると押せない幅になる)。
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(6, board.tiers.count + 1))
        return VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text("「\(item.title)」をどこへ？")
                    .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Spacer(minLength: DS.sp2)
                Button("やめる") { selectedId = nil }
                    .font(.imasSubhead).foregroundStyle(DS.ink2)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(board.tiers) { tier in
                    let theme = ImasTheme.derive(seed: tier.colorSeed, scheme: scheme)
                    Button { move(item.id, to: tier.id) } label: {
                        TierLabelText(label: tier.label, large: 18, small: 11)
                            .padding(.horizontal, 2)
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

    private func move(_ id: String, to tierId: String?) {
        moveFeedback += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            update { $0.placements[id] = tierId }
            selectedId = nil
        }
    }

    private func update(_ change: (inout TierListBoard) -> Void) {
        change(&board)
        board.savedAt = Date()
        store.save(board)
    }
}

/// 段の名前。短い名前 (S / 神) は大きく、長い名前は小さくして 2 行まで。
struct TierLabelText: View {
    let label: String
    let large: CGFloat
    let small: CGFloat

    var body: some View {
        Text(label)
            .font(.imasScaled(label.count <= 2 ? large : small, weight: .black))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }
}

/// ティアー表の 1 枚 (ジャケ / アイコン + 名前)。
struct TierListChip: View {
    let item: SortMakerItem?
    let isSelected: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: item?.seed, brand: BrandColors.hex(for: item?.brandId), scheme: scheme)
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

/// 表の名前と段 (名前・色・並び・数) を編集するシート。保存を押すまで表は変わらない。
struct TierListEditSheet: View {
    let board: TierListBoard
    let onSave: (_ title: String?, _ tiers: [TierDef]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var title: String
    @State private var tiers: [TierDef]

    private let titleMax = Int(tierListTitleMaxChars())
    private let labelMax = Int(tierListTierLabelMaxChars())
    private let minTiers = Int(tierListMinTiers())
    private let maxTiers = Int(tierListMaxTiers())

    init(board: TierListBoard, onSave: @escaping (String?, [TierDef]) -> Void) {
        self.board = board
        self.onSave = onSave
        _title = State(initialValue: board.title ?? "")
        _tiers = State(initialValue: board.tiers)
    }

    private var removedWithItems: Int {
        let kept = Set(tiers.map(\.id))
        return board.placements.values.filter { !kept.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(board.defaultTitle, text: $title)
                        .onChange(of: title) { _, v in if v.count > titleMax { title = String(v.prefix(titleMax)) } }
                } header: {
                    Text("表の名前")
                } footer: {
                    Text("画像の見出しになります。空にすると「\(board.defaultTitle)」に戻ります。")
                }

                Section {
                    ForEach($tiers) { $tier in
                        HStack(spacing: DS.sp3) {
                            let theme = ImasTheme.derive(seed: tier.colorSeed, scheme: scheme)
                            Button {
                                tier.colorSeed = tierListCycleColor(current: tier.colorSeed)
                            } label: {
                                TierLabelText(label: tier.label.isEmpty ? "?" : tier.label, large: 16, small: 10)
                                    .foregroundStyle(theme.onAccent)
                                    .frame(width: 48, height: 34)
                                    .background(theme.accent, in: RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("色を変える")
                            TextField("段の名前", text: $tier.label)
                                .onChange(of: tier.label) { _, v in
                                    if v.count > labelMax { tier.label = String(v.prefix(labelMax)) }
                                }
                        }
                    }
                    .onMove { tiers.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        guard tiers.count - offsets.count >= minTiers else { return }
                        tiers.remove(atOffsets: offsets)
                    }
                    .deleteDisabled(tiers.count <= minTiers)

                    Button {
                        let tier = tierListNewTier(index: UInt32(tiers.count), existingColorSeeds: tiers.map(\.colorSeed))
                        tiers.append(TierDef(label: tier.label, colorSeed: tier.colorSeed))
                    } label: {
                        Label("段を追加", systemImage: "plus.circle.fill")
                    }
                    .disabled(tiers.count >= maxTiers)
                } header: {
                    Text("段 (\(tiers.count) / \(maxTiers))")
                } footer: {
                    Text(footer)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("名前と段を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var footer: String {
        var text = "色の札をタップすると色が変わります。名前は\(labelMax)文字まで (「神」「沼」「好き」など)。右の三本線で並べ替え、左の赤丸で削除できます。"
        if removedWithItems > 0 {
            text += "\n削除する段にいる \(removedWithItems) 件は未分類に戻ります。"
        }
        return text
    }

    private func save() {
        // 名前の整え方 (空白・改行・上限) はコアの規則。空の段名はその位置の既定名にする。
        let cleaned = tiers.enumerated().map { i, t in
            var t = t
            t.label = tierListNormalizeTierLabel(input: t.label)
                ?? tierListNewTier(index: UInt32(i), existingColorSeeds: []).label
            return t
        }
        onSave(tierListNormalizeTitle(input: title), cleaned)
        dismiss()
    }
}
