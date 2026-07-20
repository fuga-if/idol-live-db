import SwiftUI

/// ユニット詳細 (IdolDetailView と同じ内部セグメント方式)。
/// ヒーロー (アバター + 名前 + ブランド) を固定し、その下のボディを ImasSegmented で
/// [楽曲][メンバー][コミュニティ] に切り替える。ユニットには横断的な出演履歴クエリが無いため
/// 「ライブ」タブは無く、担当/お気に入り/メモも UserMark が unit を扱わないため無い。
struct UnitDetailView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    let unit: Unit
    /// DetailSheetView の NavigationStack 内で表示された時に渡される push クロージャ。
    /// 非 nil なら子遷移は自前 sheet ではなく共有 path に push する (sheet 多重化回避)。
    /// nil (一覧からの standalone push) のときは自前 sheet で遷移する。
    var navigate: ((DetailDestination) -> Void)? = nil

    @State private var vm = UnitDetailViewModel()
    @State private var markService = UserMarkService.shared
    @State private var sheetDestination: DetailDestination?
    @State private var segment = 0
    /// コミュニティタブ: このユニットに付いたタグ (自分が付けたタグ含む)。
    @State private var unitTagData: UnitTagListResponse?
    @State private var showUnitTagPicker = false
    @State private var showCommunityLoginPrompt = false
    /// コミュニティタブ: タグが似ているユニット (サーバ算出、共有タグ数の降順を維持)。
    @State private var similarTagUnits: [Unit] = []
    @State private var similarSharedTags: [String: Int] = [:]
    @State private var personalTagService = PersonalTagService.shared
    @State private var newPersonalTagName = ""

    private var brandColor: String? { vm.brand?.color }

    /// 子遷移の単一窓口。sheet 内 (navigate 非 nil) は共有 path に push、standalone は自前 sheet。
    private func go(_ dest: DetailDestination) {
        if let navigate {
            navigate(dest)
        } else {
            sheetDestination = dest
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        segmentBody(for: segment)
                            .padding(.bottom, DS.sp7)
                    } header: {
                        fixedHeader
                            .id("unit_detail_top")
                    }
                }
            }
            .onChange(of: segment) { _, _ in
                proxy.scrollTo("unit_detail_top", anchor: .top)
            }
        }
        .background(DS.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle(unit.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            ImasTheme.derive(seed: nil, brand: brandColor, scheme: scheme).heroSurface,
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .task { await vm.loadDetails(unit: unit) }
        .trackScreen("unit_detail")
    }

    // MARK: - Fixed header (hero + segmented)

    private var fixedHeader: some View {
        VStack(spacing: 0) {
            heroView
            segmentedBar
        }
        .background(DS.bg)
    }

    private var heroView: some View {
        let t = ImasTheme.derive(seed: nil, brand: brandColor, scheme: scheme)
        return HStack(spacing: DS.sp5) {
            UnitAvatarView(unit: unit, size: 72)

            VStack(alignment: .leading, spacing: 3) {
                Text(unit.displayName)
                    .font(.imasTitle1.weight(.bold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let brand = vm.brand {
                    Button {
                        go(.filteredIdols(.brand(id: brand.id, label: brand.shortName)))
                    } label: {
                        Text(brand.shortName)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp4)
        .padding(.bottom, DS.sp5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.heroSurface)
    }

    private var segmentedBar: some View {
        ImasSegmented(
            labels: ["楽曲", "メンバー", "コミュニティ"],
            selection: $segment,
            seed: nil,
            brand: brandColor
        )
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp3)
        .padding(.bottom, DS.sp3)
    }

    // MARK: - Body switch

    @ViewBuilder
    private func segmentBody(for segment: Int) -> some View {
        switch segment {
        case 0: songsBody
        case 1: membersBody
        default: communityBody
        }
    }

    // MARK: - 楽曲

    @ViewBuilder
    private var songsBody: some View {
        VStack(spacing: DS.sp6) {
            if vm.isLoading {
                ImasListSkeleton(rows: 5, thumb: .square)
            } else if let loadError = vm.loadError {
                ImasEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "読み込みに失敗しました",
                    message: loadError,
                    actionTitle: "再試行",
                    action: { Task { await vm.loadDetails(unit: unit) } },
                    brand: brandColor
                )
            } else if !vm.songs.isEmpty {
                VStack(spacing: DS.sp3) {
                    ImasSectionHeader(title: "楽曲", count: "\(vm.songs.count)", tight: true)
                    ImasListContainer {
                        ForEach(Array(vm.songs.enumerated()), id: \.element.id) { idx, song in
                            if idx > 0 { Divider().overlay(DS.sep).padding(.leading, 66) }
                            songRow(song) {
                                go(.song(song))
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.sp5)
            } else {
                ImasEmptyState(
                    systemImage: "music.note.list",
                    title: "楽曲がありません",
                    message: "このユニットの楽曲情報はまだ登録されていません。",
                    brand: brandColor
                )
            }
        }
        .padding(.top, DS.sp4)
    }

    /// 楽曲行 (現地回収✓バッジ + お気に入りトグル)。IdolDetailView.songRow と同じ構成。
    private func songRow(_ song: Song, action: @escaping () -> Void) -> some View {
        let collected = markService.bool(.collected, entity: .song, id: song.id)
        let favorited = markService.bool(.favorite, entity: .song, id: song.id)
        let artURL = song.artworkUrl.flatMap { URL(string: $0) }
        let prevURL = song.previewUrl.flatMap { URL(string: $0) }
        return Button(action: action) {
            HStack(spacing: DS.sp3) {
                ImasLeadBar(seed: nil, brand: brandColor)
                ArtworkImageView(url: artURL, size: 44, previewURL: prevURL, songTitle: song.title, seed: brandColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.imasBody.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if collected {
                        Label("回収済", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .font(.imasCaption.weight(.semibold))
                            .foregroundStyle(DS.success)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    try? markService.toggle(.favorite, entity: .song, id: song.id)
                } label: {
                    Image(systemName: favorited ? "star.fill" : "star")
                        .font(.imasScaled( 18))
                        .foregroundStyle(favorited ? DS.favorite : DS.ink3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorited ? "お気に入り解除" : "お気に入りに追加")
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - メンバー

    @ViewBuilder
    private var membersBody: some View {
        VStack(spacing: DS.sp6) {
            GallerySectionView(kind: .unit, entityId: unit.id, entityLabel: "アイコン")
                .padding(.top, DS.sp2)

            if vm.isLoading {
                ImasListSkeleton(rows: 5, thumb: .circle)
            } else if let loadError = vm.loadError {
                ImasEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "読み込みに失敗しました",
                    message: loadError,
                    actionTitle: "再試行",
                    action: { Task { await vm.loadDetails(unit: unit) } },
                    brand: brandColor
                )
            } else if !vm.members.isEmpty {
                VStack(spacing: DS.sp3) {
                    ImasSectionHeader(title: "メンバー", count: "\(vm.members.count)", tight: true)
                    ImasListContainer {
                        ForEach(Array(vm.members.enumerated()), id: \.element.id) { idx, member in
                            if idx > 0 { Divider().overlay(DS.sep).padding(.leading, 66) }
                            memberRow(member)
                        }
                    }
                }
                .padding(.horizontal, DS.sp5)
            } else {
                ImasEmptyState(
                    systemImage: "person.3",
                    title: "メンバーがいません",
                    message: "メンバー情報はまだ登録されていません。",
                    brand: brandColor
                )
            }
        }
        .padding(.top, DS.sp4)
    }

    private func memberRow(_ member: Idol) -> some View {
        Button { go(.idol(member)) } label: {
            HStack(spacing: DS.sp3) {
                IdolAvatarView(idol: member, size: 44, isPick: markService.bool(.myPick, entity: .idol, id: member.id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.imasBody.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if !member.voiceActorList.isEmpty {
                        Text("CV \(member.voiceActorList.joined(separator: " / "))")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.imasScaled(13, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - コミュニティ (投票の優勝経験 + タグ)。IdolDetailView.communityBody と同型。

    @ViewBuilder
    private var communityBody: some View {
        VStack(spacing: DS.sp5) {
            PollAchievementBadges(entityId: unit.id)
            InlineLoginPrompt(message: "タグ付け・投票にはログインが必要です", seed: nil)
            communityUnitTags
            personalUnitTags
            if !similarTagUnits.isEmpty { communitySimilarUnits }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
        .task {
            await loadUnitTags()
            await loadSimilarUnits()
        }
        .sheet(isPresented: $showUnitTagPicker, onDismiss: { Task { await loadUnitTags() } }) {
            UnitTagPicker(unit: unit)
        }
        .sheet(isPresented: $showCommunityLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { showUnitTagPicker = true } })
        }
    }

    @ViewBuilder
    private var communityUnitTags: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                Text("タグ").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Spacer(minLength: 12)
                if EditPermission.showEditAffordance {
                    Button {
                        AppAnalytics.tap("unit_detail.tag_action")
                        startCommunityEdit { showUnitTagPicker = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.imasScaled( 13, weight: .semibold))
                            Text("タグ").font(.imasScaled( 14, weight: .semibold))
                        }
                        .foregroundStyle(ImasTheme.derive(seed: nil, brand: brandColor, scheme: scheme).accent)
                    }
                }
            }
            if let tagData = unitTagData, !tagData.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tagData.tags) { tag in
                        let isMine = Set(tagData.myTagIds).contains(tag.id)
                        Button { sheetDestination = .unitTagDetail(tag) } label: {
                            ImasChip(text: "\(tag.name) \(tag.voteCount)",
                                     style: isMine ? .selected : .themed,
                                     brand: brandColor)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if isMine {
                                Button(role: .destructive) {
                                    Task {
                                        try? await CommunityAPI.shared.removeUnitTag(unitId: unit.id, tagId: tag.id)
                                        await loadUnitTags()
                                    }
                                } label: { Label("タグを外す", systemImage: "tag.slash") }
                            }
                            Button { sheetDestination = .unitTagDetail(tag) } label: { Label("タグ詳細を見る", systemImage: "tag") }
                        }
                    }
                }
            } else {
                ImasEmptyState(systemImage: "tag", title: "タグはまだありません",
                               message: "このユニットを一言で表すタグを付けてみませんか？",
                               actionTitle: EditPermission.showEditAffordance ? "タグを追加" : nil,
                               action: EditPermission.showEditAffordance ? { startCommunityEdit { showUnitTagPicker = true } } : nil,
                               brand: brandColor)
            }
        }
    }

    /// マイタグ (個人用タグ)。コミュニティタグと違いローカル専用・サーバー非送信。
    @ViewBuilder
    private var personalUnitTags: some View {
        let tags = personalTagService.tags(for: "unit", entityId: unit.id)
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.imasScaled(13, weight: .semibold)).foregroundStyle(DS.ink3)
                    Text("マイタグ").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                }
                Text("自分だけに表示されます (コミュニティには公開されません)")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags) { tag in
                        ImasChip(text: tag.tagName, systemImage: "lock.fill", style: .neutral)
                            .contextMenu {
                                Button(role: .destructive) {
                                    personalTagService.removeTag(entityType: "unit", entityId: unit.id, name: tag.tagName)
                                } label: { Label("マイタグを削除", systemImage: "trash") }
                            }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("マイタグを追加 (例: 聞いた)", text: $newPersonalTagName)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(DS.fill, in: Capsule())
                    .onChange(of: newPersonalTagName) { _, new in
                        if new.count > 30 { newPersonalTagName = String(new.prefix(30)) }
                    }
                    .onSubmit(addPersonalTag)
                Button(action: addPersonalTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.imasScaled(26, weight: .semibold))
                        .foregroundStyle(canAddPersonalTag ? DS.ink : DS.ink3)
                }
                .buttonStyle(.plain)
                .disabled(!canAddPersonalTag)
                .accessibilityLabel("マイタグを追加")
            }
        }
    }

    private var canAddPersonalTag: Bool {
        !newPersonalTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addPersonalTag() {
        guard canAddPersonalTag else { return }
        personalTagService.addTag(entityType: "unit", entityId: unit.id, name: newPersonalTagName)
        newPersonalTagName = ""
    }

    /// 投稿/編集導線の共通ゲート (IdolDetailView.startCommunityEdit と同じ方針)。
    private func startCommunityEdit(_ present: () -> Void) {
        if EditPermission.canEdit {
            present()
        } else if EditPermission.shouldPromptLogin {
            showCommunityLoginPrompt = true
        }
    }

    private func loadUnitTags() async {
        unitTagData = try? await CommunityAPI.shared.unitTags(unitId: unit.id)
    }

    /// このユニットが好きな人にはこれもおすすめ — タグが似ているユニット (サーバ算出)。
    @ViewBuilder
    private var communitySimilarUnits: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("タグが似ているユニット")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("つけられたタグが似ているユニット")
                    .font(.imasCaption).foregroundStyle(DS.ink2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.sp4) {
                    ForEach(similarTagUnits) { other in
                        Button {
                            go(.unit(other))
                        } label: {
                            VStack(spacing: 4) {
                                UnitAvatarView(unit: other, size: 56)
                                Text(other.displayName)
                                    .font(.imasCaption.weight(.semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(DS.ink)
                                if let shared = similarSharedTags[other.id] {
                                    Text("タグ\(shared)個一致")
                                        .font(.imasScaled(10))
                                        .foregroundStyle(DS.ink3)
                                }
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// タグ類似のおすすめユニットをサーバから取得し、ローカル DB で Unit に解決する。
    /// 返却順 (共有タグ数の降順) を維持する。ユニットには is_external 相当の概念が無いため
    /// アイドルの similarIdolsByTags と異なり除外フィルタは不要。
    private func loadSimilarUnits() async {
        guard let response = try? await CommunityAPI.shared.similarUnitsByTags(unitId: unit.id) else { return }
        let ids = response.units.map(\.unitId)
        guard !ids.isEmpty,
              let index = try? await AppContainer.shared.unitReading.unitIndex() else { return }
        let byId = Dictionary(index.units.map { ($0.id, $0) }) { a, _ in a }
        similarSharedTags = Dictionary(response.units.map { ($0.unitId, $0.sharedTags) }) { a, _ in a }
        similarTagUnits = ids.compactMap { byId[$0] }
    }
}
