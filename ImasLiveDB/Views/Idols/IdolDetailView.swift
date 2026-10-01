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
    @State private var imageService = CustomImageService.shared
    @State private var markService = UserMarkService.shared
    @State private var sheetDestination: DetailDestination?
    @State private var editIdol: Idol?
    @State private var showLoginPrompt = false
    @State private var segment = 0
    /// 楽曲タブの小タブ (節) の選択。節の heading を選択値に使う (節ごとに一意)。
    @State private var selectedSongSection: String?
    /// コミュニティタブ: このアイドルに付いたタグ (自分が付けたタグ含む)。
    @State private var idolTagData: IdolTagListResponse?
    @State private var showIdolTagPicker = false
    /// コミュニティタブ: タグが似ているアイドル (サーバ算出、共有タグ数の降順を維持)。
    @State private var similarTagIdols: [Idol] = []
    @State private var similarSharedTags: [String: Int] = [:]
    @State private var showCommunityLoginPrompt = false
    @State private var personalTagService = PersonalTagService.shared
    @State private var newPersonalTagName = ""
    /// 「タグが似ているアイドル」横スクロールの名札 1 枚の幅。
    @ScaledMetric(relativeTo: .caption) private var similarIdolCellWidth: CGFloat = 84

    @Environment(\.colorScheme) private var scheme

    // MARK: - Theme / derived

    private var seed: String? { idol.color }
    private var brandColor: String? { vm.brand?.color }

    private var isPick: Bool { markService.bool(.myPick, entity: .idol, id: idol.id) }

    /// 出演履歴のうち今日以降で最も近い公演 (= 次の出演)。無ければ nil。
    /// 選び方 (日付の精度を揃えて今日以降か・同じ日なら先の方) はコアの `next_show_index`。
    private var nextShow: CastShowRow? {
        let shows = vm.castShows
        return nextShowIndex(dates: shows.map(\.date), todayKey: JSTDay.today()).map { shows[Int($0)] }
    }

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
        .task { await vm.loadDetails(idol: idol) }
        .trackScreen("idol_detail")
    }

    // MARK: - Fixed header (hero + segmented)

    private var fixedHeader: some View {
        VStack(spacing: 0) {
            heroView
            UserMarkBar(entity: .idol, entityId: idol.id, kinds: [.favorite, .note], seed: seed, brand: brandColor)
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, DS.Space.gap)
            segmentedBar
        }
        .background(DS.bg)
    }

    /// よみ・CV・誕生日 (誕生日の整形はコア `idolProfileRowsFromSource` の行を借りる。
    /// 見出し文字列ではなく、誕生日の行だけが持つ構造上の action (`filterByBirthMonth`) で拾う)。
    private var heroSubtitle: String? {
        let birthday = profileRowModels.first {
            if case .filterByBirthMonth = $0.action { return true }
            return false
        }?.value
        let parts = [idol.nameKana, VoiceActorDirectory.shared.current(for: idol.id).map { "CV \($0)" }, birthday]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var heroView: some View {
        ImasIdolHeader(
            imprint: vm.brand?.shortName ?? "",
            onImprintTap: vm.brand.map { brand in { go(.filteredIdols(.brand(id: brand.id, label: brand.shortName))) } },
            name: idol.name,
            subtitle: heroSubtitle,
            seed: seed,
            brand: brandColor,
            iconLabel: idol.shortName,
            imageURL: imageService.imageURL(for: idol.id),
            isPick: isPick,
            onTogglePick: togglePick,
            copyItems: [
                CopyItem("アイドル名をコピー", idol.name, key: "idol_name"),
                CopyItem("よみをコピー", idol.nameKana, key: "kana"),
                CopyItem("CV名をコピー", VoiceActorDirectory.shared.current(for: idol.id), key: "voice_actor"),
            ],
            // 読み込みが終わるまでは出さない (0 / 0 の瞬間表示を防ぐ)。
            stats: vm.hasLoadedDetails ? [
                ImasBoard.Cell(value: "\(vm.castShows.count)", label: "出演"),
                ImasBoard.Cell(value: "\(vm.performedSongs.count)", label: "歌唱曲"),
            ] : []
        ) {
            // PhotosPicker の label は Sendable の closure なので、MainActor の値は先に取り出して渡す。
            let badgeSeed = seed
            let badgeBrand = brandColor
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ImasIconBadge(systemImage: "camera.fill", label: "写真を選ぶ", seed: badgeSeed, brand: badgeBrand)
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.gapLoose)
    }

    /// 担当の切り替え。
    private func togglePick() {
        do {
            try markService.toggle(.myPick, entity: .idol, id: idol.id)
        } catch {
            LocalWriteFailure.report(error, action: "担当の切り替え")
        }
    }

    private var segmentedBar: some View {
        ImasTabs(
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
                    ImasCardList {
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
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "出演履歴", count: "\(vm.castShows.count)", tight: true)
                    ForEach(castShowYearGroups, id: \.year) { group in
                        ImasDateHeader(big: group.year, imprint: "\(group.rows.count) 件")
                        ImasCardList {
                            ForEach(Array(group.rows.enumerated()), id: \.offset) { idx, row in
                                if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                                eventRow(row)
                            }
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

    /// 次の出演。紙のチケットで見せる。
    private func upcomingCard(_ row: CastShowRow) -> some View {
        ImasTicket(
            label: "次の出演",
            imprint: nil,
            title: eventDisplayName(row.eventName),
            metaImprint: dateLabel(date: row.date, today: JSTDay.today()),
            meta: [row.venue, row.showName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            seed: seed,
            brand: brandColor
        ) {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    go(.show(show))
                }
            }
        }
    }

    // MARK: - 楽曲

    /// 選択中の小タブに対応する節。選択が節の並びから外れていたら先頭に落ちる
    /// (再読み込みで節の顔ぶれが変わった場合の保険)。
    private var currentSongSection: IdolSongSection? {
        vm.originalSongSections.first { $0.heading == selectedSongSection } ?? vm.originalSongSections.first
    }

    /// `ImasSegmented` の選択値 (String)。この Binding は節が 2 つ以上あるときだけ使われるので、
    /// フォールバックの既定値 (先頭節の見出し) は常に存在する。
    private var songSectionSelectionBinding: Binding<String> {
        Binding<String>(
            get: { selectedSongSection ?? vm.initialSongSectionHeading ?? "" },
            set: { selectedSongSection = $0 }
        )
    }

    /// 小タブに出す文言 (「ソロ 12」のように短い見出し + 件数)。
    private func songSectionTabLabel(forHeading heading: String) -> String {
        guard let section = vm.originalSongSections.first(where: { $0.heading == heading }) else {
            return heading
        }
        return "\(section.shortHeading) \(section.songs.count)"
    }

    @ViewBuilder
    private var songsBody: some View {
        VStack(spacing: DS.sp4) {
            if !vm.originalSongSections.isEmpty {
                // 枠が 1 つしか無いときは小タブを出さず一覧だけを出す。
                if vm.originalSongSections.count > 1 {
                    ImasSegmented(
                        options: vm.originalSongSections.map(\.heading),
                        selection: songSectionSelectionBinding,
                        seed: seed,
                        brand: brandColor,
                        label: songSectionTabLabel(forHeading:)
                    )
                    .padding(.horizontal, DS.sp5)
                }
                if let section = currentSongSection {
                    ImasCardList {
                        ForEach(Array(section.songs.enumerated()), id: \.element.id) { idx, song in
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
                    .padding(.horizontal, DS.sp5)
                }
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
        // 節の顔ぶれが変わったら (初回読み込み・再読み込み)、選択が無効なら先頭節に戻す。
        .onChange(of: vm.originalSongSections.map(\.heading)) { _, headings in
            if let selectedSongSection, headings.contains(selectedSongSection) { return }
            selectedSongSection = vm.initialSongSectionHeading
        }
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
                        withAnimation(.imasStandard) { showEmptyUnits.toggle() }
                    } label: {
                        HStack(spacing: DS.Space.gapTight) {
                            Text("曲なしユニット").imasText(.sectionLabel)
                            Text("\(vm.unitsWithoutSongs.count)").imasText(.meta)
                            Spacer(minLength: DS.Space.gapTight)
                            ImasRowChevron()
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

            ImasCardList {
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
                        Label("タグ", systemImage: "plus")
                    }
                    .buttonStyle(.imas(.plain, size: .small))
                }
            }
            if let tagData = idolTagData, !tagData.tags.isEmpty {
                FlowLayout(spacing: DS.sp3) {
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
                                        try? await AppContainer.shared.communityTagWriting.removeIdolTag(idolId: idol.id, tagId: tag.id)
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
            VStack(alignment: .leading, spacing: DS.sp1) {
                HStack(spacing: DS.Space.gapTight) {
                    Image(systemName: "lock.fill").imasText(.note)
                    Text("マイタグ").imasText(.cardTitle)
                }
                Text("自分だけに表示されます (コミュニティには公開されません)").imasText(.note)
            }
            if !tags.isEmpty {
                FlowLayout(spacing: DS.sp3) {
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
            ImasChipInputField(text: $newPersonalTagName, prompt: "マイタグを追加 (例: 聞いた)", limit: 30,
                              isEnabled: canAddPersonalTag, submitAccessibilityLabel: "マイタグを追加",
                              onSubmit: addPersonalTag)
        }
    }

    private var canAddPersonalTag: Bool {
        !newPersonalTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addPersonalTag() {
        guard canAddPersonalTag else { return }
        if personalTagService.addTag(entityType: "idol", entityId: idol.id, name: newPersonalTagName) {
            newPersonalTagName = ""
        }
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
        idolTagData = try? await AppContainer.shared.communityTagReading.idolTags(idolId: idol.id)
    }

    /// このアイドルが好きな人にはこれもおすすめ — タグが似ているアイドル (サーバ算出)。
    @ViewBuilder
    private var communitySimilarIdols: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("タグが似ているアイドル").imasText(.cardTitle)
                Text("つけられたタグが似ているアイドル").imasText(.note)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                    ForEach(similarTagIdols) { other in
                        Button {
                            go(.idol(other))
                        } label: {
                            // metric の枠を借りて「タグ N 個一致」を名札の下段に出す。
                            ImasIdolCell(idol: other, isPick: false,
                                        metric: similarSharedTags[other.id].map { "タグ\($0)個一致" })
                                .frame(width: similarIdolCellWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// タグ類似のおすすめアイドルをサーバから取得し、ローカル DB で Idol に解決する。
    /// 返却順 (共有タグ数の降順) を維持する。
    private func loadSimilarIdols() async {
        // サーバ (D1) には idols が無く外部ゲストを除けないので多めに頼み (件数はコア)、
        // 手元で除いて表示する数だけ選ぶ (選び方もコア)。
        guard let response = try? await AppContainer.shared.communityTagReading.similarIdolsByTags(
            idolId: idol.id, limit: Int(similarIdolsFetchLimit())
        ) else { return }
        let candidates = response.idols.map {
            SimilarIdolCandidate(idolId: $0.idolId, sharedTags: UInt32(clamping: $0.sharedTags))
        }
        guard !candidates.isEmpty,
              let picked = try? await AppContainer.shared.idolReading.similarIdols(from: candidates) else { return }
        similarSharedTags = Dictionary(response.idols.map { ($0.idolId, $0.sharedTags) }) { a, _ in a }
        similarTagIdols = picked
    }

    // MARK: - 画像ギャラリー (ユーザーがローカルに持たせる複数画像)

    private var gallerySection: some View {
        // Unit 詳細と共通の `GallerySectionView` (写真1枚目がアイコンになる・スライドショー対象の
        // 切り替えも idol kind では引き続き出す)。
        GallerySectionView(kind: .idol, entityId: idol.id, entityLabel: "アイコン", onChange: syncWidget)
    }

    /// ギャラリー変更後にウィジェットへ反映する (App Group ミラー + タイムライン再読込)。
    private func syncWidget() {
        Task { await WidgetImageBridge.sync(database: database) }
    }

    /// プロフィール行は整形 (「4月3日」「160cm」) も並べる判断も共有コアが持つ
    /// (`idolProfileRowsFromSource`)。ここは生の値を渡すだけ。
    ///
    /// 1 画面 = 1 呼び出し。行ごとに FFI を跨がない。
    private var profileRowModels: [ScreenRow] {
        idolProfileRowsFromSource(source: IdolProfileSource(
            nameKana: idol.nameKana,
            nameRomaji: idol.nameRomaji,
            birthday: idol.birthday,
            age: idol.age.map(Int64.init),
            height: idol.height,
            weight: idol.weight,
            bust: idol.bust,
            waist: idol.waist,
            hip: idol.hip,
            bloodType: idol.bloodType,
            constellation: idol.constellation,
            birthPlace: idol.birthPlace,
            handedness: idol.handedness,
            hobbies: idol.hobbies,
            talents: idol.talents,
            color: idol.color
        ))
    }

    /// コアの `RowAction` を iOS の操作に落とす。**遷移/複写の実行はこちらの責務**。
    ///
    /// `navigates` は「押せる見た目」(accent 文字色 + chevron) を出すか。
    /// 複写は押せるが行先が無いので、矢印を出すと嘘になる。
    private func profileRowTap(_ row: ScreenRow) -> (navigates: Bool, run: (() -> Void)?) {
        switch row.action {
        case let .filterByBirthMonth(month):
            return (true, { go(.filteredIdols(.birthMonth(Int(month)))) })
        // カラーは押すと写せる (配信や実況で色コードを使う人が居る)。
        case RowAction.copyValue:
            return (false, { UIPasteboard.general.string = row.value })
        // 展開は ImasLabeledRow が自前の状態で行うので、行の action としては持たせない。
        case RowAction.toggleExpansion, RowAction.none:
            return (false, nil)
        }
    }

    @ViewBuilder
    private var profileRows: some View {
        let models = profileRowModels
        // label はコアが返す固定の見出しで重複しないため、そのまま同一性に使える。
        ForEach(Array(models.enumerated()), id: \.element.label) { idx, row in
            if idx > 0 { ImasRowDivider() }
            let tap = profileRowTap(row)
            let content = ImasLabeledRow(
                key: row.label,
                value: row.value,
                showChevron: tap.navigates,
                showSwatch: row.style == .colorSwatch,
                // 色コードは桁を揃えたいので ColorSwatch も等幅で出す。
                mono: row.style == .monospaced || row.style == .colorSwatch,
                tappable: tap.navigates,
                // 遷移/複写を持たない行 (よみ/趣味・特技 等) はタップで全文展開できるようにする。
                expandable: tap.run == nil,
                seed: seed,
                brand: brandColor
            )
            if let run = tap.run {
                Button(action: run) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    // MARK: - Shared rows

    /// 楽曲行 (現地回収✓ / 披露回数バッジ付き)。歌唱者アバターはこの画面では本人なので省略し、
    /// リードバー + ジャケ + 曲名 + ユニット名 + 回収マーク に集約する。
    /// 試聴 (タップで再生・停止) は `ArtworkImageView` 固有の機能で `ImasArtwork` にまだ無いため、
    /// ここは `ImasRow` の先頭を `.custom` で差し替えて組む (曲一覧領域の GAP 解消を待つ)。
    private func songRow(
        song: Song,
        detailLabel: String,
        performCount: Int?,
        action: @escaping () -> Void
    ) -> some View {
        let collected = markService.bool(.collected, entity: .song, id: song.id)
        let artURL = song.artworkUrl.flatMap { URL(string: $0) }
        let prevURL = song.previewUrl.flatMap { URL(string: $0) }
        return Button(action: action) {
            ImasRow(
                title: song.title,
                subtitle: detailLabel.isEmpty ? nil : detailLabel,
                leading: .custom(AnyView(
                    ArtworkImageView(url: artURL, size: 44, previewURL: prevURL, songTitle: song.title,
                                     songId: song.id, seed: seed ?? brandColor)
                ), width: 44),
                leadBar: ImasRowLeadBar(seed: seed, brand: brandColor),
                density: .compact
            ) {
                if collected || performCount != nil {
                    HStack(spacing: DS.Space.gap) {
                        if collected { ImasBadge(text: "回収済", kind: .positive) }
                        if let performCount { ImasMetric(value: "\(performCount)", unit: "回", size: .small) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 出演履歴を年ごとの塊に (新しい年が先)。見出しと並びはコアの `group_indices_by_year_desc`
    /// (ライブ一覧 `FilteredShowsView` と同じ規則)。
    private var castShowYearGroups: [(year: String, rows: [CastShowRow])] {
        groupIndicesByYearDesc(dates: vm.castShows.map(\.date)).map { group in
            (year: group.label, rows: group.indices.map { vm.castShows[Int($0)] })
        }
    }

    /// 出演履歴。半券の行 (左に日付、右にライブ名・会場・公演名)。主演/ゲストは札で添える。
    private func eventRow(_ row: CastShowRow) -> some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    go(.show(show))
                }
            }
        } label: {
            ImasStubRow(
                date: ImasStubDate(row.date),
                title: eventDisplayName(row.eventName),
                subtitle: [row.venue, row.showName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                seed: seed,
                brand: brandColor,
                badges: row.isLead ? [ImasBadgeSpec(text: "主演", kind: .lead)]
                    : row.isGuest ? [ImasBadgeSpec(text: "ゲスト", kind: .guest)] : [],
                spokenDate: spokenDate(date: row.date)
            )
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
