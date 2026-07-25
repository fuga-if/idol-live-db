import os
import SwiftUI
import PhotosUI

/// アイドル詳細 (新デザインシステム / 内部セグメント版)。
/// ヒーロー (アバター + 名前 + ブランド + CV + 担当/お気に入りアクション) を固定し、
/// その下のボディを ImasSegmented で [ライブ][楽曲][プロフィール][コミュニティ] に切り替える。
struct IdolDetailView: View {
    @Environment(AppDatabase.self) private var database
    let idol: Idol
    /// DetailSheetView の NavigationStack 内で表示された時に渡される push クロージャ。
    /// 非 nil なら子遷移は自前 sheet ではなく共有 path に push する (sheet 多重化回避)。
    /// nil (一覧からの standalone push) のときは自前 sheet で遷移する。
    var navigate: ((DetailDestination) -> Void)? = nil

    @State private var vm = IdolDetailViewModel()
    @State private var showEmptyUnits = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// ギャラリーへのまとめ追加 (複数選択)。
    @State private var galleryPicks: [PhotosPickerItem] = []
    @State private var imageService = CustomImageService.shared
    @State private var markService = UserMarkService.shared
    @State private var sheetDestination: DetailDestination?
    @State private var editIdol: Idol?
    @State private var showLoginPrompt = false
    @State private var segment = 0
    /// コミュニティタブ: このアイドルに付いたタグ (自分が付けたタグ含む)。
    @State private var idolTagData: IdolTagListResponse?
    @State private var showIdolTagPicker = false
    /// コミュニティタブ: タグが似ているアイドル (サーバ算出、共有タグ数の降順を維持)。
    @State private var similarTagIdols: [Idol] = []
    @State private var similarSharedTags: [String: Int] = [:]
    @State private var showCommunityLoginPrompt = false
    @State private var showingNote = false
    @State private var noteDraft = ""
    @State private var personalTagService = PersonalTagService.shared
    @State private var newPersonalTagName = ""

    @Environment(\.colorScheme) private var scheme

    // MARK: - Theme / derived

    private var seed: String? { idol.color }
    private var brandColor: String? { vm.brand?.color }

    private var isPick: Bool { markService.bool(.myPick, entity: .idol, id: idol.id) }
    private var isFavorite: Bool { markService.bool(.favorite, entity: .idol, id: idol.id) }
    private var hasNote: Bool { !(markService.note(entity: .idol, id: idol.id) ?? "").isEmpty }

    /// 出演履歴のうち今日以降で最も近い公演 (= 次の出演)。無ければ nil。
    private var nextShow: CastShowRow? {
        let today = Self.todayString
        return vm.castShows
            .filter { $0.date >= today }
            .min { $0.date < $1.date }
    }

    private static let todayString: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }()

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
                            .id("idol_detail_top")
                    }
                }
            }
            // タブ切替時にスクロールを先頭へリセット。
            // 共通 ScrollView を使っているとタブ間で offset が引き継がれてしまうため、
            // 切り替え時にヒーロー直下へ戻す (アニメーション無しで即時)。
            .onChange(of: segment) { _, _ in
                proxy.scrollTo("idol_detail_top", anchor: .top)
            }
        }
        .background(DS.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle(idol.name)
        .navigationBarTitleDisplayMode(.inline)
        // ナビバーをヒーロー色で不透明化。スクロール内容がヘッダー裏に透ける問題を防ぎ、
        // 固定ヒーローと色が繋がる。
        .toolbarBackground(ImasTheme.derive(seed: seed, brand: brandColor, scheme: scheme).heroSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarMenu }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .sheet(item: $editIdol) { i in
            IdolEditView(idol: i).environment(database)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { editIdol = idol } })
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    _ = try? await imageService.addImage(image, for: idol.id)
                    await WidgetImageBridge.sync(database: database)
                }
                selectedPhoto = nil
            }
        }
        .onChange(of: galleryPicks) { _, picks in
            guard !picks.isEmpty else { return }
            Task {
                for pick in picks {
                    if let data = try? await pick.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        _ = try? await imageService.addImage(image, for: idol.id)
                    }
                }
                galleryPicks = []
                await WidgetImageBridge.sync(database: database)
            }
        }
        .task { await vm.loadDetails(idol: idol) }
        .trackScreen("idol_detail")
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
        let t = ImasTheme.derive(seed: seed, brand: brandColor, scheme: scheme)
        return VStack(alignment: .leading, spacing: DS.sp5) {
            HStack(spacing: DS.sp5) {
                ZStack(alignment: .bottomTrailing) {
                    IdolAvatarView(idol: idol, size: 72, isPick: isPick)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.imasScaled( 11, weight: .semibold))
                            .foregroundStyle(t.onAccent)
                            .frame(width: 26, height: 26)
                            .background(t.accent, in: Circle())
                            .overlay(Circle().strokeBorder(DS.surface, lineWidth: 2))
                    }
                    // IdolAvatarView の外形フレームは isPick に関わらず一定 (担当リング込みサイズ) だが、
                    // isPick=false では可視アバターがその中央に余白 ImasAvatar.ringPadding 分だけ
                    // 小さく描画される。ボタンをリングの有無に関係なく可視アバターの縁に揃えるため補正する。
                    .offset(
                        x: isPick ? 4 : 4 - ImasAvatar.ringPadding,
                        y: isPick ? 4 : 4 - ImasAvatar.ringPadding
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(idol.name)
                        .font(.imasTitle1.weight(.bold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .imasCopyable([
                            ("アイドル名をコピー", idol.name),
                            ("よみをコピー", idol.nameKana),
                            ("CV名をコピー", idol.currentVoiceActor),
                        ])
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
                    if !idol.voiceActorList.isEmpty {
                        Text("CV \(idol.voiceActorList.joined(separator: " / "))")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: DS.sp3) {
                heroActionButton(
                    title: "担当",
                    activeTitle: "担当",
                    systemImage: isPick ? "heart.fill" : "heart",
                    isOn: isPick,
                    onColor: t.accent,
                    onText: t.onAccent
                ) {
                    try? markService.toggle(.myPick, entity: .idol, id: idol.id)
                }
                heroActionButton(
                    title: "お気に入り",
                    activeTitle: "お気に入り済",
                    systemImage: isFavorite ? "star.fill" : "star",
                    isOn: isFavorite,
                    onColor: t.chipBg,
                    onText: t.chipText,
                    ghost: true
                ) {
                    try? markService.toggle(.favorite, entity: .idol, id: idol.id)
                }
                Spacer(minLength: 0)
                // メモ。担当/お気に入りと同じピル型ボタンに揃える (UserMarkBar のタイル型は
                // 50pt四方+ラベルで縦に大きく、横並びだと担当/お気に入りより不釣り合いに高かった)。
                heroActionButton(
                    title: "メモ",
                    activeTitle: "メモあり",
                    systemImage: hasNote ? "note.text.badge.plus" : "note.text",
                    isOn: hasNote,
                    onColor: t.chipBg,
                    onText: t.chipText,
                    ghost: true
                ) {
                    noteDraft = markService.note(entity: .idol, id: idol.id) ?? ""
                    showingNote = true
                }
            }
        }
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp4)
        .padding(.bottom, DS.sp5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.heroSurface)
        .sheet(isPresented: $showingNote) {
            NoteEditorSheet(entity: .idol, entityId: idol.id, draft: $noteDraft)
        }
    }

    private func heroActionButton(
        title: String,
        activeTitle: String,
        systemImage: String,
        isOn: Bool,
        onColor: Color,
        onText: Color,
        ghost: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.imasScaled( 15, weight: .semibold))
                Text(isOn ? activeTitle : title)
                    .font(.imasSubhead.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 9)
            .foregroundStyle(isOn ? onText : (ghost ? DS.ink2 : onColor))
            .background(isOn ? onColor : DS.fill,
                        in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    private var segmentedBar: some View {
        ImasSegmented(
            labels: ["ライブ", "楽曲", "プロフィール", "コミュニティ"],
            selection: $segment,
            seed: seed,
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
        case 0: liveBody
        case 1: songsBody
        case 2: profileBody
        default: communityBody
        }
    }

    // MARK: - ライブ

    @ViewBuilder
    private var liveBody: some View {
        VStack(spacing: DS.sp6) {
            if let next = nextShow {
                upcomingCard(next).padding(.horizontal, DS.sp5)
            }

            if !vm.performedSongs.isEmpty {
                VStack(spacing: DS.sp3) {
                    ImasSectionHeader(title: "ライブ歌唱曲", count: "\(vm.performedSongs.count)", tight: true)
                    ImasListContainer {
                        ForEach(Array(vm.performedSongs.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { ImasRowDivider(inset: 66) }
                            songRow(
                                song: item.song,
                                detailLabel: item.song.unitName ?? "",
                                performCount: item.performCount
                            ) {
                                go(.idolSongHistory(idol, item.song))
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.sp5)
            }

            if !vm.castShows.isEmpty {
                VStack(spacing: DS.sp3) {
                    ImasSectionHeader(title: "出演履歴", count: "\(vm.castShows.count)", tight: true)
                    ImasListContainer {
                        ForEach(Array(vm.castShows.enumerated()), id: \.offset) { idx, row in
                            if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                            eventRow(row)
                        }
                    }
                }
                .padding(.horizontal, DS.sp5)
            }

            if vm.performedSongs.isEmpty && vm.castShows.isEmpty && nextShow == nil {
                ImasEmptyState(
                    systemImage: "music.mic",
                    title: "ライブ情報がありません",
                    message: "このアイドルのライブ出演・歌唱記録はまだ登録されていません。",
                    seed: seed,
                    brand: brandColor
                )
            }
        }
        .padding(.top, DS.sp4)
    }

    /// 次の出演カード (ucard)。
    private func upcomingCard(_ row: CastShowRow) -> some View {
        let t = ImasTheme.derive(seed: seed, brand: brandColor, scheme: scheme)
        return Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    go(.show(show))
                }
            }
        } label: {
            HStack(spacing: 0) {
                Rectangle().fill(t.accent).frame(width: 4)
                VStack(alignment: .leading, spacing: 5) {
                    Text("次の出演 ・ \(monthDay(row.date))")
                        .font(.imasDisplay(12, weight: .semibold))
                        .foregroundStyle(t.accent)
                    Text(eventDisplayName(row.eventName))
                        .font(.imasHeadline.weight(.bold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.imasScaled( 12))
                        Text([row.venue, row.showName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ "))
                            .lineLimit(1)
                    }
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                }
                .padding(.horizontal, DS.sp4)
                .padding(.vertical, DS.sp4)
                Spacer(minLength: 0)
            }
            .background(t.heroSurface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 楽曲

    @ViewBuilder
    private var songsBody: some View {
        VStack(spacing: DS.sp6) {
            if !vm.originalSongs.isEmpty {
                VStack(spacing: DS.sp3) {
                    ImasSectionHeader(title: "楽曲（原曲）", count: "\(vm.originalSongs.count)", tight: true)
                    ImasListContainer {
                        ForEach(Array(vm.originalSongs.enumerated()), id: \.element.id) { idx, song in
                            if idx > 0 { ImasRowDivider(inset: 66) }
                            songRow(
                                song: song,
                                detailLabel: song.unitName ?? "",
                                performCount: nil
                            ) {
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
                    message: "原曲の情報はまだ登録されていません。",
                    seed: seed,
                    brand: brandColor
                )
            }
        }
        .padding(.top, DS.sp4)
    }

    // MARK: - プロフィール

    @ViewBuilder
    private var profileBody: some View {
        VStack(spacing: DS.sp6) {
            if !vm.unitsWithSongs.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "所属ユニット", count: "\(vm.unitsWithSongs.count)", tight: true)
                    FlowChips(units: vm.unitsWithSongs, seed: seed, brand: brandColor) { unit in
                        go(.unit(unit))
                    }
                }
                .padding(.horizontal, DS.sp5)
            }

            if !vm.unitsWithoutSongs.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showEmptyUnits.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("曲なしユニット").font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink2)
                            Text("\(vm.unitsWithoutSongs.count)").font(.imasCaption).foregroundStyle(DS.ink3)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
                                .rotationEffect(.degrees(showEmptyUnits ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showEmptyUnits {
                        FlowChips(units: vm.unitsWithoutSongs, seed: seed, brand: brandColor) { unit in
                            go(.unit(unit))
                        }
                    }
                }
                .padding(.horizontal, DS.sp5)
            }

            ImasListContainer {
                profileRows
            }
            .padding(.horizontal, DS.sp5)

            if let desc = idol.description, !desc.isEmpty {
                Text(desc)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.sp5)
            }

            gallerySection
        }
        .padding(.top, DS.sp4)
    }

    // MARK: - コミュニティ (投票の優勝経験 + タグ)

    @ViewBuilder
    private var communityBody: some View {
        VStack(spacing: DS.sp5) {
            PollAchievementBadges(entityId: idol.id)
            InlineLoginPrompt(message: "タグ付け・投票にはログインが必要です", seed: seed)
            communityIdolTags
            personalIdolTags
            if !similarTagIdols.isEmpty { communitySimilarIdols }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
        .task {
            await loadIdolTags()
            await loadSimilarIdols()
        }
        .sheet(isPresented: $showIdolTagPicker, onDismiss: { Task { await loadIdolTags() } }) {
            IdolTagPicker(idol: idol)
        }
        .sheet(isPresented: $showCommunityLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { showIdolTagPicker = true } })
        }
    }

    @ViewBuilder
    private var communityIdolTags: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                Text("タグ").font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Spacer(minLength: 12)
                if EditPermission.showEditAffordance {
                    Button {
                        AppAnalytics.tap("idol_detail.tag_action")
                        startCommunityEdit { showIdolTagPicker = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.imasScaled( 13, weight: .semibold))
                            Text("タグ").font(.imasScaled( 14, weight: .semibold))
                        }
                        .foregroundStyle(ImasTheme.derive(seed: seed, brand: brandColor, scheme: scheme).accent)
                    }
                }
            }
            if let tagData = idolTagData, !tagData.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tagData.tags) { tag in
                        let isMine = Set(tagData.myTagIds).contains(tag.id)
                        Button { sheetDestination = .idolTagDetail(tag) } label: {
                            ImasChip(text: "\(tag.name) \(tag.voteCount)",
                                     style: isMine ? .selected : .themed,
                                     seed: seed)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if isMine {
                                Button(role: .destructive) {
                                    Task {
                                        try? await CommunityAPI.shared.removeIdolTag(idolId: idol.id, tagId: tag.id)
                                        await loadIdolTags()
                                    }
                                } label: { Label("タグを外す", systemImage: "tag.slash") }
                            }
                            Button { sheetDestination = .idolTagDetail(tag) } label: { Label("タグ詳細を見る", systemImage: "tag") }
                        }
                    }
                }
            } else {
                ImasEmptyState(systemImage: "tag", title: "タグはまだありません",
                               message: "このアイドルを一言で表すタグを付けてみませんか？",
                               actionTitle: EditPermission.showEditAffordance ? "タグを追加" : nil,
                               action: EditPermission.showEditAffordance ? { startCommunityEdit { showIdolTagPicker = true } } : nil,
                               seed: seed)
            }
        }
    }

    /// マイタグ (個人用タグ)。コミュニティタグと違いローカル専用・サーバー非送信。
    /// 見た目もコミュニティタグ (themed/selected の彩色チップ) とはっきり区別し、
    /// グレー系 + 鍵アイコンの neutral チップで「自分だけに見える」ことを示す。
    @ViewBuilder
    private var personalIdolTags: some View {
        let tags = personalTagService.tags(for: "idol", entityId: idol.id)
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
                                    personalTagService.removeTag(entityType: "idol", entityId: idol.id, name: tag.tagName)
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
            }
        }
    }

    private var canAddPersonalTag: Bool {
        !newPersonalTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addPersonalTag() {
        guard canAddPersonalTag else { return }
        personalTagService.addTag(entityType: "idol", entityId: idol.id, name: newPersonalTagName)
        newPersonalTagName = ""
    }

    /// 投稿/編集導線の共通ゲート (DetailSheet.startCommunityEdit と同じ方針)。
    private func startCommunityEdit(_ present: () -> Void) {
        if EditPermission.canEdit {
            present()
        } else if EditPermission.shouldPromptLogin {
            showCommunityLoginPrompt = true
        }
    }

    private func loadIdolTags() async {
        idolTagData = try? await CommunityAPI.shared.idolTags(idolId: idol.id)
    }

    /// このアイドルが好きな人にはこれもおすすめ — タグが似ているアイドル (サーバ算出)。
    @ViewBuilder
    private var communitySimilarIdols: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("タグが似ているアイドル")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("つけられたタグが似ているアイドル")
                    .font(.imasCaption).foregroundStyle(DS.ink2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.sp4) {
                    ForEach(similarTagIdols) { other in
                        Button {
                            go(.idol(other))
                        } label: {
                            VStack(spacing: 4) {
                                IdolAvatarView(idol: other, size: 56)
                                Text(other.shortName)
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

    /// 表示件数 (サーバー算出の共有タグ数上位から採用する件数)。
    private static let similarIdolsDisplayLimit = 10
    /// サーバーへの取得件数。D1 に idols テーブルが無く is_external フィルタをサーバー側で
    /// 適用できないため、クライアント側除外後に表示件数を確保できるよう多めに over-fetch する。
    private static let similarIdolsFetchLimit = 25

    /// タグ類似のおすすめアイドルをサーバから取得し、ローカル DB で Idol に解決する。
    /// 返却順 (共有タグ数の降順) を維持する。
    private func loadSimilarIdols() async {
        guard let response = try? await CommunityAPI.shared.similarIdolsByTags(
            idolId: idol.id, limit: Self.similarIdolsFetchLimit
        ) else { return }
        let ids = response.idols.map(\.idolId)
        guard !ids.isEmpty,
              let resolved = try? await AppContainer.shared.idolReading.idols(ids: ids) else { return }
        // サーバー (D1) には idols テーブルが無く is_external でのフィルタができないため、
        // ローカル DB 解決後にここで外部ゲスト演者を除外し、表示件数分だけ採用する。
        let byId = Dictionary(resolved.filter { !$0.isExternal }.map { ($0.id, $0) }) { a, _ in a }
        similarSharedTags = Dictionary(response.idols.map { ($0.idolId, $0.sharedTags) }) { a, _ in a }
        similarTagIdols = Array(ids.compactMap { byId[$0] }.prefix(Self.similarIdolsDisplayLimit))
    }

    // MARK: - 画像ギャラリー (ユーザーがローカルに持たせる複数画像)

    @ViewBuilder
    private var gallerySection: some View {
        // galleryVersion を読んで追加/削除/並べ替え後に再描画する。
        let _ = imageService.galleryVersion
        let urls = imageService.imageURLs(for: idol.id)
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                ImasSectionHeader(title: "ギャラリー", count: urls.isEmpty ? nil : "\(urls.count)", tight: true)
                Spacer()
                PhotosPicker(selection: $galleryPicks, maxSelectionCount: 10, matching: .images) {
                    Label("追加", systemImage: "plus")
                        .font(.imasSubhead.weight(.medium))
                }
            }
            .padding(.horizontal, DS.sp5)

            if urls.isEmpty {
                Text("画像を追加すると、先頭の1枚がアイコンになります。ホーム画面ウィジェットにも使えます。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.sp5)
            } else {
                galleryGrid(urls: urls)

                Text("長押しでアイコン設定・ウィジェットのスライドショー対象を切り替えられます。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
                    .padding(.horizontal, DS.sp5)
            }
        }
    }

    /// ギャラリー変更後にウィジェットへ反映する (App Group ミラー + タイムライン再読込)。
    private func syncWidget() {
        Task { await WidgetImageBridge.sync(database: database) }
    }

    /// ギャラリーを横3列で並べる。`LazyVGrid` + 貪欲セルの組み合わせだと flexible 列が
    /// 広がって列数が崩れる (実機で2列になる) ため、HStack で確実に3等分する。
    @ViewBuilder
    private func galleryGrid(urls: [URL]) -> some View {
        let spacing = DS.sp2
        let perRow = 3
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: urls.count, by: perRow)), id: \.self) { start in
                let end = min(start + perRow, urls.count)
                HStack(spacing: spacing) {
                    ForEach(start..<end, id: \.self) { i in
                        let url = urls[i]
                        galleryThumb(
                            url: url,
                            isPrimary: i == 0,
                            inSlideshow: imageService.isInSlideshow(url, for: idol.id))
                            .frame(maxWidth: .infinity)
                    }
                    // 端数行も 1/3 幅を保つよう空セルで埋める (左寄せ維持)。
                    ForEach(end..<(start + perRow), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, DS.sp5)
    }

    private func galleryThumb(url: URL, isPrimary: Bool, inSlideshow: Bool) -> some View {
        Color.clear
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DS.fill
                }
                // スライドショー対象外は淡く落として一目で分かるようにする。
                .opacity(inSlideshow ? 1 : 0.45)
            }
            // グリッドのセルは .fit で列幅に収める。.fill だと flexible 列が貪欲セルに
            // 合わせて広がり、count:3 指定でも 2 列しか並ばなくなる (SwiftUI のレイアウト罠)。
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
            .overlay(alignment: .topLeading) {
                if isPrimary {
                    Label("アイコン", systemImage: "star.fill")
                        .font(.imasScaled(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !inSlideshow {
                    Image(systemName: "play.slash.fill")
                        .font(.imasScaled(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(5)
                        .accessibilityLabel("スライドショー対象外")
                }
            }
            .contextMenu {
                if !isPrimary {
                    Button {
                        imageService.setPrimary(url, for: idol.id)
                        syncWidget()
                    } label: {
                        Label("アイコンにする", systemImage: "star")
                    }
                }
                Button {
                    imageService.setInSlideshow(!inSlideshow, url: url, for: idol.id)
                    syncWidget()
                } label: {
                    Label(inSlideshow ? "スライドショーから外す" : "スライドショーに入れる",
                          systemImage: inSlideshow ? "play.slash" : "play.rectangle")
                }
                Button(role: .destructive) {
                    Task {
                        try? await imageService.deleteImage(at: url, for: idol.id)
                        await WidgetImageBridge.sync(database: database)
                    }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }

    /// プロフィール行の宣言的モデル。divider は描画側でインデックスから判定する。
    private struct ProfileRow: Identifiable {
        let id = UUID()
        let key: String
        let value: String
        var chevron = false
        var mono = false
        var swatch = false
        var tappable = false
        var action: (() -> Void)? = nil
    }

    private var profileRowModels: [ProfileRow] {
        var rows: [ProfileRow] = []
        if let kana = idol.nameKana { rows.append(.init(key: "よみ", value: kana)) }
        if let romaji = idol.nameRomaji { rows.append(.init(key: "ローマ字", value: romaji, mono: true)) }
        if let bday = idol.birthdayDisplay {
            if let month = idol.birthMonth {
                rows.append(.init(key: "誕生日", value: bday, chevron: true, tappable: true) {
                    go(.filteredIdols(.birthMonth(month)))
                })
            } else {
                rows.append(.init(key: "誕生日", value: bday))
            }
        }
        if let v = ageHeightWeight { rows.append(.init(key: "年齢 / 身長 / 体重", value: v)) }
        if let v = idol.threeSizeDisplay { rows.append(.init(key: "スリーサイズ", value: v, mono: true)) }
        if let v = bloodConstellation { rows.append(.init(key: "血液型 / 星座", value: v)) }
        if let v = birthplaceHand { rows.append(.init(key: "出身 / 利き手", value: v)) }
        if let v = hobbyTalent { rows.append(.init(key: "趣味 / 特技", value: v)) }
        if let color = idol.color {
            rows.append(.init(key: "カラー", value: color, mono: true, swatch: true) {
                UIPasteboard.general.string = color
            })
        }
        return rows
    }

    @ViewBuilder
    private var profileRows: some View {
        let models = profileRowModels
        ForEach(Array(models.enumerated()), id: \.element.id) { idx, row in
            if idx > 0 { ImasRowDivider() }
            let content = ImasLabeledRow(
                key: row.key,
                value: row.value,
                showChevron: row.chevron,
                showSwatch: row.swatch,
                mono: row.mono,
                tappable: row.tappable,
                // action を持たない行 (よみ/趣味・特技 等) はタップで全文展開できるようにする。
                expandable: row.action == nil,
                seed: seed,
                brand: brandColor
            )
            if let action = row.action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    // 集約プロフィール値
    private var ageHeightWeight: String? {
        var parts: [String] = []
        if let age = idol.age { parts.append("\(age)歳") }
        if let h = idol.heightDisplay { parts.append(h) }
        if let w = idol.weight { parts.append("\(Int(w))kg") }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }
    private var bloodConstellation: String? {
        var parts: [String] = []
        if let bt = idol.bloodType { parts.append("\(bt)型") }
        if let c = idol.constellation { parts.append(c) }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }
    private var birthplaceHand: String? {
        var parts: [String] = []
        if let bp = idol.birthPlace { parts.append(bp) }
        if let h = idol.handedness { parts.append(h == "right" ? "右" : h == "left" ? "左" : h) }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }
    private var hobbyTalent: String? {
        var parts: [String] = []
        if let h = idol.hobbies { parts.append(h) }
        if let t = idol.talents { parts.append(t) }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    // MARK: - Shared rows

    /// 楽曲行 (現地回収✓ / 披露回数バッジ付き)。歌唱者アバターはこの画面では本人なので省略し、
    /// リードバー + ジャケ + 曲名 + ユニット名 + 回収マーク に集約する。
    private func songRow(
        song: Song,
        detailLabel: String,
        performCount: Int?,
        action: @escaping () -> Void
    ) -> some View {
        let collected = markService.bool(.collected, entity: .song, id: song.id)
        let favorited = markService.bool(.favorite, entity: .song, id: song.id)
        let artURL = song.artworkUrl.flatMap { URL(string: $0) }
        let prevURL = song.previewUrl.flatMap { URL(string: $0) }
        return Button(action: action) {
            HStack(spacing: DS.sp3) {
                ImasLeadBar(seed: seed, brand: brandColor)
                ArtworkImageView(url: artURL, size: 44, previewURL: prevURL, songTitle: song.title, seed: seed ?? brandColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.imasBody.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if !detailLabel.isEmpty {
                        Text(detailLabel)
                            .font(.imasFootnote)
                            .foregroundStyle(DS.ink2)
                            .lineLimit(1)
                    }
                    if collected || performCount != nil {
                        HStack(spacing: 8) {
                            if collected {
                                Label("回収済", systemImage: "checkmark")
                                    .labelStyle(.titleAndIcon)
                                    .font(.imasCaption.weight(.semibold))
                                    .foregroundStyle(DS.success)
                            }
                            if let performCount {
                                Text("\(performCount)回")
                                    .font(.imasDisplay(11, weight: .semibold))
                                    .foregroundStyle(DS.ink3)
                            }
                        }
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
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 出演履歴 (EventRow)。ブランド帯 + ライブ名 + 日付 + 会場。
    private func eventRow(_ row: CastShowRow) -> some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    go(.show(show))
                }
            }
        } label: {
            HStack(spacing: DS.sp3) {
                ImasLeadBar(seed: seed, brand: brandColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(eventDisplayName(row.eventName))
                            .font(.imasBody.weight(.semibold))
                            .foregroundStyle(DS.ink)
                            .lineLimit(1)
                        if row.isLead {
                            ImasTagChip(text: "主演", kind: .lead, seed: seed, brand: brandColor)
                        } else if row.isGuest {
                            ImasTagChip(text: "ゲスト", kind: .guest, seed: seed, brand: brandColor)
                        }
                    }
                    Text([row.date, row.venue, row.showName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ "))
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.imasScaled( 13, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if EditPermission.showEditAffordance {
                    Button { startEdit() } label: {
                        Label("編集", systemImage: "pencil")
                    }
                }
                NavigationLink {
                    EditHistoryView(recordType: "Idol", recordName: idol.id, title: idol.name)
                } label: {
                    Label("編集履歴", systemImage: "clock.arrow.circlepath")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// 編集導線。ログイン済みなら編集 sheet、未ログインならログイン誘導。
    private func startEdit() {
        if EditPermission.canEdit {
            editIdol = idol
        } else {
            showLoginPrompt = true
        }
    }

    // MARK: - Helpers

    /// "2026-06-21" → "6/21"
    private func monthDay(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return date }
        return "\(m)/\(d)"
    }

}

// MARK: - ユニット chips (折返しレイアウト)

/// 所属ユニットを themed チップで折返し表示。タップでユニット詳細シートへ。
private struct FlowChips: View {
    let units: [Unit]
    var seed: String?
    var brand: String?
    let onTap: (Unit) -> Void

    var body: some View {
        IdolFlowLayout(spacing: DS.sp2) {
            ForEach(units) { unit in
                Button { onTap(unit) } label: {
                    ImasChip(text: unit.displayName, style: .themed, seed: seed, brand: brand)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 単純な折返しレイアウト (iOS16+ Layout)。
private struct IdolFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
