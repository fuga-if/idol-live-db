import os
import SwiftUI

// MARK: - Brand Filter Section (shared across filter sheets)

/// ブランドを丸アイコンの格子で選ぶ素のグリッド。 List/Form/ScrollView いずれでも置ける。
/// 「全て」セルの有無は `includeAllOption` で切り替える (絞り込み画面では出し、
/// 投票候補のブランド限定では出さない＝必ず1つは選ばせる)。
struct BrandGridPicker: View {
    let brands: [Brand]
    /// 空集合 = `includeAllOption` 時は全ブランド対象、それ以外は未選択。 複数選択は OR (= IN) で結合。
    @Binding var selectedBrandIds: Set<String>
    var includeAllOption: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
            if includeAllOption {
                BrandIconCell(
                    brandId: nil,
                    label: "全て",
                    iconText: "全",
                    color: nil,
                    isSelected: selectedBrandIds.isEmpty
                ) { selectedBrandIds = [] }
            }

            ForEach(brands) { brand in
                BrandIconCell(
                    brandId: brand.id,
                    label: brand.shortName,
                    iconText: brand.iconText,
                    color: brand.color,
                    isSelected: selectedBrandIds.contains(brand.id)
                ) {
                    if !selectedBrandIds.insert(brand.id).inserted {
                        selectedBrandIds.remove(brand.id)
                    }
                }
            }
        }
    }
}

struct BrandFilterSection: View {
    let brands: [Brand]
    /// 空集合 = 全ブランド対象。 複数選択は OR (= IN) で結合される。
    @Binding var selectedBrandIds: Set<String>

    var body: some View {
        Section {
            BrandGridPicker(brands: brands, selectedBrandIds: $selectedBrandIds, includeAllOption: true)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("ブランド")
        } footer: {
            Text("複数選択可能").font(.imasScaled(11)).foregroundStyle(.tertiary)
        }
    }
}

/// ブランド 1 件分。CustomImageService に画像があれば優先表示し、無ければ
/// ブランドカラー円 + 短いテキスト (765 / ミリ 等) を fallback として描画する。
/// 版権上、公式ロゴは使わずユーザー側で gist 経由 import した画像を使う。
struct BrandIconCell: View {
    let brandId: String?
    let label: String
    let iconText: String
    let color: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var imageService = CustomImageService.shared

    private var background: Color {
        color.map { Color(hexString: $0) } ?? .accentColor
    }

    private var fontSize: CGFloat {
        switch iconText.count {
        case 0...2: return 18
        case 3:     return 14
        case 4:     return 12
        default:    return 10
        }
    }

    private var customImageURL: URL? {
        brandId.flatMap { imageService.brandImageURL(for: $0) }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                iconView
                Text(label)
                    .font(.imasScaled(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var iconView: some View {
        if let url = customImageURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? background : Color.clear, lineWidth: 2)
                )
                .opacity(isSelected ? 1.0 : 0.55)
        } else {
            ZStack {
                Circle()
                    .fill(isSelected ? background : background.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? .clear : background.opacity(0.4), lineWidth: 1.5)
                    )
                Text(iconText)
                    .font(.imasScaled( fontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? .white : background)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 42)
            }
        }
    }
}

// MARK: - Event Filter Sheet

struct EventFilterSheet: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedBrandIds: Set<String>
    /// 除外する EventKind の rawValue を CSV で保持
    @Binding var excludedKindsRaw: String
    @Binding var showEmptyEvents: Bool
    /// 参加状態フィルタ ("all" / "attended" / "not_attended")
    @Binding var attendanceFilter: String
    @Binding var requireFavorite: Bool
    @Binding var requireNote: Bool

    @State private var brands: [Brand] = []
    @State private var localBrandIds: Set<String> = []
    @State private var localExcluded: Set<EventKind> = []
    @State private var localShowEmpty: Bool = false
    @State private var localAttendance: String = "all"
    @State private var localFavorite: Bool = false
    @State private var localNote: Bool = false

    var body: some View {
        NavigationStack {
            List {
                BrandFilterSection(brands: brands, selectedBrandIds: $localBrandIds)

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(EventKind.allCases, id: \.rawValue) { kind in
                            EventKindChip(
                                kind: kind,
                                isOn: !localExcluded.contains(kind)
                            ) {
                                if localExcluded.contains(kind) {
                                    localExcluded.remove(kind)
                                } else {
                                    localExcluded.insert(kind)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("種別")
                } footer: {
                    if localExcluded.isEmpty {
                        Text("全て表示中")
                    } else {
                        Text("除外: \(localExcluded.map(\.displayLabel).sorted().joined(separator: " / "))")
                    }
                }

                Section("参加状態") {
                    Picker("参加", selection: $localAttendance) {
                        Text("すべて").tag("all")
                        Text("参加済み").tag("attended")
                        Text("未参加").tag("not_attended")
                    }
                    .pickerStyle(.segmented)
                }

                Section("マイマーク") {
                    Toggle(isOn: $localFavorite) {
                        Label("お気に入りのみ", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    Toggle(isOn: $localNote) {
                        Label("メモがあるイベントのみ", systemImage: "note.text")
                            .foregroundStyle(.orange)
                    }
                }

                Section("表示設定") {
                    Toggle("セトリ情報がないイベントも表示", isOn: $localShowEmpty)
                        .tint(.green)
                }

                if !localBrandIds.isEmpty || !localExcluded.isEmpty || localShowEmpty || localAttendance != "all" || localFavorite || localNote {
                    Section {
                        Button(role: .destructive) {
                            AppAnalytics.tap("filter_sheet.reset")
                            localBrandIds = []
                            localExcluded = []
                            localShowEmpty = false
                            localAttendance = "all"
                            localFavorite = false
                            localNote = false
                        } label: {
                            Label("リセット", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .navigationTitle("フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("リセット") {
                        AppAnalytics.tap("filter_sheet.reset")
                        localBrandIds = []
                        localExcluded = []
                        localShowEmpty = false
                        localAttendance = "all"
                        localFavorite = false
                        localNote = false
                    }
                    .disabled(localBrandIds.isEmpty && localExcluded.isEmpty && !localShowEmpty && localAttendance == "all" && !localFavorite && !localNote)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        AppAnalytics.tap("filter_sheet.apply")
                        selectedBrandIds = localBrandIds
                        excludedKindsRaw = localExcluded.map(\.rawValue).sorted().joined(separator: ",")
                        showEmptyEvents = localShowEmpty
                        attendanceFilter = localAttendance
                        requireFavorite = localFavorite
                        requireNote = localNote
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                do {
                    brands = try await AppContainer.shared.brandReading.brands()
                } catch {
                    Logger.database.error("load_failed brands (FilterSheet/event): \(error.localizedDescription)")
                }
                localBrandIds = selectedBrandIds
                localExcluded = Set(excludedKindsRaw.split(separator: ",")
                    .compactMap { EventKind(rawValue: String($0)) })
                localShowEmpty = showEmptyEvents
                localAttendance = attendanceFilter
                localFavorite = requireFavorite
                localNote = requireNote
            }
            .trackScreen("event_filter_sheet")
        }
    }
}

/// 種別 (EventKind) の on/off chip。
struct EventKindChip: View {
    let kind: EventKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: kind.iconName)
                    .font(.imasCaption)
                Text(kind.displayLabel)
                    .font(.imasCaption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isOn ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isOn ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isOn ? .clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.displayLabel) \(isOn ? "表示" : "除外")")
    }
}

// MARK: - Idol Filter Sheet

/// ブランドごとのサブカテゴリ属性 (idols.attribute) 定義。
/// (内部値, 表示ラベル) のペア。順序が UI 表示順。
private let brandAttributes: [String: [(value: String, label: String)]] = [
    "cg":    [("cute", "キュート"), ("cool", "クール"), ("passion", "パッション")],
    "ml":    [("princess", "プリンセス"), ("fairy", "フェアリー"), ("angel", "エンジェル")],
    "765as": [("princess", "プリンセス"), ("fairy", "フェアリー"), ("angel", "エンジェル")],
    "sidem": [("intelli", "インテリ"), ("physical", "フィジカル"), ("mental", "メンタル")],
    "sc":    [("sol", "Sol"), ("luna", "Luna"), ("stella", "Stella")],
]

struct IdolFilterSheet: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedBrandIds: Set<String>
    @Binding var selectedAttribute: String?
    @Binding var displayMode: IdolDisplayMode
    @Binding var showCV: Bool
    @Binding var requireMyPick: Bool
    @Binding var requireFavorite: Bool
    @Binding var requireNote: Bool

    @State private var brands: [Brand] = []
    @State private var localBrandIds: Set<String> = []
    @State private var localAttribute: String?
    @State private var localMyPick: Bool = false
    @State private var localFavorite: Bool = false
    @State private var localNote: Bool = false

    /// 属性チップは「単一ブランドが選択されている」場合のみ表示。
    /// 0 件 or 複数ブランドではブランド共通のサブ属性が無いので空。
    private var attributesForBrand: [(value: String, label: String)] {
        guard localBrandIds.count == 1, let bid = localBrandIds.first else { return [] }
        return brandAttributes[bid] ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section("表示形式") {
                    Picker("名前表示", selection: $displayMode) {
                        ForEach(IdolDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    // アイドル名表示のとき、CV 名を別行で併記するか。CV 名表示中は CV がタイトルなので無効。
                    Toggle("CV名を併記", isOn: $showCV)
                        .disabled(displayMode == .cvName)
                }

                BrandFilterSection(brands: brands, selectedBrandIds: $localBrandIds)
                    .onChange(of: localBrandIds) { _, _ in
                        // ブランド変更時は属性絞り込みリセット
                        localAttribute = nil
                    }

                if !attributesForBrand.isEmpty {
                    Section("属性") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                attributeChip(value: nil, label: "全て")
                                ForEach(attributesForBrand, id: \.value) { item in
                                    attributeChip(value: item.value, label: item.label)
                                }
                            }
                        }
                    }
                }

                Section("マイマーク") {
                    Toggle(isOn: $localMyPick) {
                        Label("担当のみ", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                    Toggle(isOn: $localFavorite) {
                        Label("お気に入りのみ", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    Toggle(isOn: $localNote) {
                        Label("メモがあるアイドルのみ", systemImage: "note.text")
                            .foregroundStyle(.orange)
                    }
                }

                if !localBrandIds.isEmpty || localAttribute != nil || localMyPick || localFavorite || localNote {
                    Section {
                        Button(role: .destructive) {
                            AppAnalytics.tap("filter_sheet.reset")
                            localBrandIds = []
                            localAttribute = nil
                            localMyPick = false
                            localFavorite = false
                            localNote = false
                        } label: {
                            Label("リセット", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .navigationTitle("フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("リセット") {
                        AppAnalytics.tap("filter_sheet.reset")
                        localBrandIds = []
                        localAttribute = nil
                        localMyPick = false
                        localFavorite = false
                        localNote = false
                    }
                    .disabled(localBrandIds.isEmpty && localAttribute == nil && !localMyPick && !localFavorite && !localNote)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        AppAnalytics.tap("filter_sheet.apply")
                        selectedBrandIds = localBrandIds
                        selectedAttribute = localAttribute
                        requireMyPick = localMyPick
                        requireFavorite = localFavorite
                        requireNote = localNote
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                do {
                    brands = try await AppContainer.shared.brandReading.brands()
                } catch {
                    Logger.database.error("load_failed brands (FilterSheet/idol): \(error.localizedDescription)")
                }
                localBrandIds = selectedBrandIds
                localAttribute = selectedAttribute
                localMyPick = requireMyPick
                localFavorite = requireFavorite
                localNote = requireNote
            }
            .trackScreen("idol_filter_sheet")
        }
    }

    private func attributeChip(value: String?, label: String) -> some View {
        let isSelected = localAttribute == value
        return Button {
            localAttribute = value
        } label: {
            Text(label)
                .font(.imasCaption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Filter Sheet

struct TagFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [(value: String, label: String)]
    let sortOptions: [(value: String, label: String)]

    @Binding var selectedCategory: String
    @Binding var selectedSort: String

    @State private var localCategory: String = ""
    @State private var localSort: String = "popular"

    var activeFilterCount: Int {
        (selectedCategory.isEmpty ? 0 : 1)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("カテゴリ") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.value) { cat in
                                categoryChip(value: cat.value, label: cat.label)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("並び順") {
                    Picker("並び順", selection: $localSort) {
                        ForEach(sortOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if !localCategory.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            AppAnalytics.tap("filter_sheet.reset")
                            localCategory = ""
                            localSort = "popular"
                        } label: {
                            Label("リセット", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .navigationTitle("フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("リセット") {
                        AppAnalytics.tap("filter_sheet.reset")
                        localCategory = ""
                        localSort = "popular"
                    }
                    .disabled(localCategory.isEmpty && localSort == "popular")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        AppAnalytics.tap("filter_sheet.apply")
                        selectedCategory = localCategory
                        selectedSort = localSort
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                localCategory = selectedCategory
                localSort = selectedSort
            }
            .trackScreen("tag_filter_sheet")
        }
    }

    private func categoryChip(value: String, label: String) -> some View {
        let isSelected = localCategory == value
        return Button {
            localCategory = value
        } label: {
            Text(label)
                .font(.imasCaption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Badge Button

/// ナビバーのフィルタアイコン。activeCount > 0 なら赤バッジを表示。
struct FilterBarButton: View {
    let activeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: activeCount > 0
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.imasScaled(11).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(.red)
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
    }
}
