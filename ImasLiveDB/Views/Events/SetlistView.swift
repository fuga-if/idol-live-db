import MusicKit
import os
import SwiftUI

struct SetlistView: View {
    @Environment(AppDatabase.self) private var database
    let show: Show
    /// DetailSheetView の NavigationStack 内に置かれた時に渡される push クロージャ。
    /// 非 nil なら遷移は自前 sheet ではなく共有 path への push にする (sheet 多重化回避)。
    /// nil の時 (タブ内 standalone) は従来どおり自前 sheet。
    var navigate: ((DetailDestination) -> Void)? = nil
    @State private var setlist: [SetlistRow] = []
    /// 会場マスタ。当時名とキャパの解決に使う。
    @State private var venueDirectory: VenueDirectory = .empty
    /// 予想/実セトリ両方ある時の内部タブ (0=セットリスト / 1=予想)。
    @State private var contentTab = 0
    /// シンプル表示 (番号・曲名・演者だけ)。 20 曲超のセトリを 1 枚のスクショに
    /// 収めたい用途向け。 公演をまたいで保持したいので AppStorage。
    @AppStorage("setlist_simple_mode") private var simpleMode = false
    @State private var performersByItemId: [String: [PerformerRow]] = [:]
    @State private var originalIdsBySongId: [String: Set<String>] = [:]
    @State private var idolsById: [String: Idol] = [:]
    @State private var showPlaylistAlert = false
    @State private var playlistMessage = ""
    @State private var isCreatingPlaylist = false
    @State private var playlistProgress: (current: Int, total: Int) = (0, 0)
    @State private var sheetDestination: DetailDestination?
    @State private var unitIndex: UnitIndex? = nil
    @State private var showAllCastIds: Set<String> = []
    /// この公演で「ユニット単独曲」として披露されたユニット ID 集合。
    /// 偶然メンバーが揃った合唱曲で誤検出されないよう、unit chip 表示はこの集合内に限定する。
    @State private var activeUnitIds: Set<String> = []
    @State private var showEditSheet = false
    /// 未ログイン時のログイン誘導 sheet。ログイン後にセトリ編集を再開する。
    @State private var showLoginPrompt = false
    /// Good 投票で未ログインだった時のログイン誘導 (編集とは別。再開副作用なし)。
    @State private var showVoteLoginPrompt = false
    /// 参加種別 (現地/配信) を選ぶダイアログ。
    @State private var showAttendanceDialog = false
    /// 参加変更後に UserMarkBar の表示を更新するためのバージョン。
    @State private var attendanceVersion = 0
    /// 担当アイドル ID 集合。 担当認知はアバターの二重輪 (isPick) に委ねる。
    @State private var myPickIdolIds: Set<String> = []
    /// brand_id → イメージカラー hex。曲のフォールバックジャケ/チップ色のシードに使う。
    @State private var brandHexById: [String: String] = [:]
    /// この公演自体のブランド色 hex (会場/日付の lcRow シード)。
    @State private var showBrandHex: String? = nil
    /// イベント名 (シェア文を「イベント名 + 公演名」にするため保持)。
    @State private var eventName: String? = nil
    /// 開催形態フォールバック用に親イベントを保持 (参加形態の出し分け)。
    @State private var event: Event? = nil
    /// 公演内の各曲への「良かった」 like 状態 (post-vote)。 song_id 索引。
    @State private var likesBySongId: [String: SetlistLikeService.LikeEntry] = [:]
    /// 予想セトリの「曲を追加」picker。安定した List 上で presentation するため親が保持する
    /// (Section に sheet を付けると初回 presentation が行再評価で即閉じするため)。
    @State private var songPicker: SongPickerRequest?

    /// 公演が未来か (今日も含む)。 セトリ未登録時の文言出し分けに使う。
    /// 端末ローカルのタイムゾーンで「今日」を判定する (`EventListView.todayKey` /
    /// `EventDetailView.isFutureEvent` / `AttendanceStatus.derive` と同じ方式に統一。
    /// `ISO8601DateFormatter` は既定 GMT 基準になるため、ここでは使わない)。
    private var isFutureShow: Bool {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return show.date >= today
    }

    /// シェア文に使う公演の表示名。イベント名が取れていれば「イベント名 公演名」、
    /// 公演名が既にイベント名を含む場合は重複させない。
    private var shareName: String {
        if let eventName, !show.name.contains(eventName) {
            return "\(eventName) \(show.name)"
        }
        return show.name
    }

    /// 遷移の単一窓口。sheet 内 (navigate 非 nil) は共有 path に push、standalone は自前 sheet。
    private func go(_ dest: DetailDestination) {
        if let navigate {
            navigate(dest)
        } else {
            sheetDestination = dest
        }
    }

    /// 曲のフォールバックジャケ/チップ色シード。曲のブランド色 → 公演ブランド色の順。
    /// セトリ 1 行。 通常表示とシンプル表示の分岐ごと ForEach の外に出す。
    /// ForEach のクロージャ内に両方の巨大な View 生成式を並べると
    /// 「unable to type-check this expression in reasonable time」で通らなくなる。
    @ViewBuilder
    private func setlistRow(item: SetlistRow, index: Int) -> some View {
        let performers = performersByItemId[item.id] ?? []
        let performerIdolIds = Set(performers.compactMap(\.idolId))
        if simpleMode {
            SetlistSimpleRowView(
                item: item,
                displayNumber: index + 1,
                performerLabel: performerLabel(performers: performers, idolIds: performerIdolIds),
                brandHex: brandHex(for: item)
            )
            .onTapGesture {
                // 通常行と同じで、 曲は id だけ持っているので取得してから遷移する。
                Task {
                    if let song = try? await AppContainer.shared.songReading.song(id: item.songId) {
                        go(.song(song))
                    }
                }
            }
        } else {
            let originalIds = originalIdsBySongId[item.songId] ?? []
            SetlistRowView(
                item: item,
                displayNumber: index + 1,
                performers: performers,
                idolsById: idolsById,
                unitIndex: unitIndex,
                showAllCastIds: showAllCastIds,
                activeUnitIds: activeUnitIds,
                coverType: classifyCover(originalIds: originalIds, performerIds: performerIdolIds),
                myPickIdolIds: myPickIdolIds,
                showId: show.id,
                showName: shareName,
                showDate: show.date,
                likeEntry: likesBySongId[item.songId],
                onToggleLike: { entry in
                    likesBySongId[item.songId] = SetlistLikeService.LikeEntry(
                        songId: item.songId,
                        likeCount: entry.likeCount,
                        hasUserLiked: entry.liked
                    )
                },
                brandHex: brandHex(for: item),
                navigate: navigate,
                onRequireLogin: { showVoteLoginPrompt = true }
            )
        }
    }

    /// シンプル表示の演者ラベル。 通常行の performerMeta と同じ優先順で決める:
    /// ユニット単独曲ならユニット名 → 出演者全員なら「全員」→ それ以外は名前を「／」で連結。
    /// 名前の区切りは公式のセトリ画像に合わせて全角スラッシュ。
    private func performerLabel(performers: [PerformerRow], idolIds: Set<String>) -> String {
        if let unitIndex {
            let units = unitIndex.exactMatchingUnits(for: idolIds, requireSongs: true)
                .filter { activeUnitIds.isEmpty || activeUnitIds.contains($0.id) }
            if !units.isEmpty { return units.map(\.name).joined(separator: "／") }
        }
        // showAllCastIds は cast_id 集合。 PerformerRow.id が cast_id なのでそのまま比較できる。
        if showAllCastIds.count >= 2, Set(performers.map(\.id)) == showAllCastIds { return "全員" }
        let names = performers.compactMap { $0.idolId.flatMap { idolsById[$0]?.name } }
        if !names.isEmpty { return names.joined(separator: "／") }
        return performers.map(\.name).joined(separator: "／")
    }

    private func brandHex(for item: SetlistRow) -> String? {
        if let bid = item.songBrandId, let hex = brandHexById[bid] { return hex }
        return showBrandHex
    }

    private var sections: [SetlistSection] {
        var result: [SetlistSection] = []
        for item in setlist {
            let sectionName = item.section ?? "本編"
            if result.last?.sectionName == sectionName {
                result[result.count - 1].items.append(item)
            } else {
                result.append(SetlistSection(id: item.position, sectionName: sectionName, items: [item]))
            }
        }
        return result
    }

    var body: some View {
        List {
            // 公演名 大見出し (デザイン 03: 本文先頭の t-title2)。ナビは「セットリスト」。
            Section {
                Text(show.name)
                    .font(.imasTitle2)
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            // シンプル表示では会場カードとマークバーを畳み、 会場・日付だけの 1 行にする。
            // ここが 280pt 前後あり、 残したままだと 20 曲超のセトリが 1 枚のスクショに
            // 収まらない (シンプル表示を作った意味が無くなる)。
            if simpleMode {
                Section {
                    Text([venueDirectory.displayName(for: show), show.date]
                        .compactMap { $0 }.joined(separator: " ・ "))
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }

            // 会場 / 日付 カード
            if !simpleMode {
            Section {
                ImasListContainer {
                    // 会場は ID で持つ。表示は公演日時点の名前 (改名前の公演は当時名)。
                    if let venueLabel = venueDirectory.displayName(for: show) {
                        ImasLabeledRow(key: "会場", value: venueLabel, showChevron: true, tappable: true, seed: showBrandHex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let vid = show.venueId { go(.filteredShows(.venue(vid))) }
                            }
                            .imasCopyable(venueLabel, label: "会場名をコピー")
                        ImasRowDivider(inset: 16)
                    }
                    // キャパが分かる会場では規模も出す (ホール指定があればホール側を優先)。
                    if let cap = venueDirectory.capacity(for: show) {
                        ImasLabeledRow(key: "キャパ", value: "\(cap.formatted(.number.grouping(.automatic)))人", seed: showBrandHex)
                        ImasRowDivider(inset: 16)
                    }
                    if let stream = show.streamPlatform, !stream.isEmpty {
                        ImasLabeledRow(key: "配信", value: stream, seed: showBrandHex)
                        ImasRowDivider(inset: 16)
                    }
                    ImasLabeledRow(key: "日付", value: show.date, showChevron: true, tappable: true, seed: showBrandHex)
                        .contentShape(Rectangle())
                        .onTapGesture { go(.filteredShows(.date(show.date))) }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            }

            Section {
                UserMarkBar(
                    entity: .show,
                    entityId: show.id,
                    kinds: [.attended, .favorite, .note, .seat],
                    seed: showBrandHex,
                    onAttendedTap: { showAttendanceDialog = true },
                    attendedIsOn: UserMarkService.shared.attendance(entity: .show, id: show.id) != nil
                )
                .id(attendanceVersion)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16))
            }

            // 予想と実セトリが両方あるときは内部タブで切替 (実セトリ確定後も予想を見られる)。
            if isFutureShow && !setlist.isEmpty {
                Section {
                    ImasSegmented(labels: ["セットリスト", "予想"], selection: $contentTab, seed: showBrandHex)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }

            // 予想: 未来公演で、(実セトリ未登録) または (両方ありで予想タブ選択時)。
            if isFutureShow && (setlist.isEmpty || contentTab == 1) {
                SetlistPredictionView(
                    showId: show.id,
                    showName: show.name,
                    seed: showBrandHex,
                    presentSongPicker: { onSelect in
                        songPicker = SongPickerRequest(showId: show.id, onSelect: onSelect)
                    }
                )
                .environment(database)
            }

            if setlist.isEmpty {
                Section {
                    ImasEmptyState(
                        systemImage: isFutureShow ? "calendar.badge.clock" : "music.note.list",
                        title: isFutureShow ? "公演前です" : "セトリ未登録",
                        message: isFutureShow
                            ? "セトリは公演後に登録されます"
                            : "このライブのセトリはまだ登録されていません。ログインして編集に参加できます",
                        actionTitle: (isFutureShow || !EditPermission.showEditAffordance) ? nil : "セトリを追加",
                        action: (isFutureShow || !EditPermission.showEditAffordance) ? nil : { startEdit() },
                        seed: showBrandHex
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // 良かった曲に投票しよう Note / 未ログインはログイン導線 (実セトリ表示中のみ)。
            // シンプル表示では出さない。 投票導線はシンプル表示に 👍 自体が無いので意味が無く、
            // スクショに誘導文が写り込むだけになる。
            if !simpleMode && !setlist.isEmpty && !(isFutureShow && contentTab == 1) {
                Section {
                    Group {
                        if AuthService.shared.isSignedIn {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.thumbsup.fill").font(.imasCaption).foregroundStyle(DS.pick)
                                Text("良かったと思った曲に 👍 で投票しよう！")
                                    .font(.imasCaption).foregroundStyle(DS.ink2)
                            }
                        } else {
                            InlineLoginPrompt(message: "👍 で投票するにはログインが必要です", seed: showBrandHex)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }

            // 実セトリ: 両方ありで予想タブ選択中は隠す。それ以外は表示。
            ForEach((isFutureShow && !setlist.isEmpty && contentTab == 1) ? [] : sections) { section in
                Section(header: ImasSectionHeader(title: section.sectionName, tight: true).textCase(nil)) {
                    // セクションの曲を 1 枚の角丸カード (ImasListContainer) にまとめる (デザイン 03 の .list)。
                    ImasListContainer {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { ImasRowDivider(inset: simpleMode ? 34 : 66) }
                            setlistRow(item: item, index: index)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 16, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("セットリスト")
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .confirmationDialog("この公演への参加", isPresented: $showAttendanceDialog, titleVisibility: .visible) {
            // そのライブに実在した形態だけ提示 (show優先・eventフォールバック)。
            ForEach(AttendanceAvailability.options(show: show, event: event), id: \.self) { type in
                Button("\(type.label)で参加") { setAttendance(type) }
            }
            if UserMarkService.shared.attendance(entity: .show, id: show.id) != nil {
                Button("参加を取り消す", role: .destructive) { setAttendance(nil) }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // SNS シェア (Universal Links)。リンクを踏むとこの公演セトリに直接着地する。
                ShareLink(
                    item: DeeplinkBuilder.shareText(
                        name: shareName,
                        url: DeeplinkBuilder.showURL(id: show.id)
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("この公演をシェア")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        AppAnalytics.tap("setlist.toggle_simple")
                        withAnimation(.easeInOut(duration: 0.15)) { simpleMode.toggle() }
                    } label: {
                        Label(
                            simpleMode ? "通常表示に戻す" : "シンプル表示",
                            systemImage: simpleMode ? "list.bullet.rectangle" : "list.bullet"
                        )
                    }

                    if EditPermission.showEditAffordance {
                        Button { startEdit() } label: {
                            Label("セトリを編集", systemImage: "pencil")
                        }
                    }
                    // セトリ編集は show 単位スナップショット (ShowSetlist) として履歴化される。
                    NavigationLink {
                        EditHistoryView(recordType: "ShowSetlist", recordName: show.id, title: show.name)
                    } label: {
                        Label("セトリの編集履歴", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await addToAppleMusicPlaylist() }
                    } label: {
                        Label("Apple Musicプレイリストに追加", systemImage: "music.note.list")
                    }

                    Button {
                        Task { await playAllPreview() }
                    } label: {
                        Label("全曲プレビュー再生", systemImage: "play.fill")
                    }

                    if MusicKitService.shared.isPlaying {
                        Button {
                            MusicKitService.shared.stop()
                        } label: {
                            Label("再生停止", systemImage: "stop.fill")
                        }
                    }
                } label: {
                    Image(systemName: "music.note.list")
                }
            }
        }
        .alert("プレイリスト", isPresented: $showPlaylistAlert) {
            Button("OK") {}
        } message: {
            Text(playlistMessage)
        }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            Task { await loadSetlist() }
        }) {
            SetlistEditView(show: show)
                .environment(database)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { showEditSheet = true } })
        }
        .sheet(isPresented: $showVoteLoginPrompt) {
            LoginToEditSheet()
        }
        .sheet(item: $songPicker) { req in
            SongSearchPickerView(showId: req.showId) { songs in req.onSelect(songs) }
                .environment(database)
        }
        .overlay {
            if isCreatingPlaylist {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                        Text(playlistProgress.total > 0
                             ? "プレイリスト作成中… \(playlistProgress.current)/\(playlistProgress.total)"
                             : "プレイリスト作成中…")
                            .font(.imasSubhead)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isCreatingPlaylist)
        .task { await loadSetlist() }
        .task {
            venueDirectory = (try? await AppContainer.shared.showReading.venueDirectory()) ?? .empty
        }
        .trackScreen("setlist")
    }

    /// セトリ編集導線。ログイン済みなら編集 sheet、未ログインならログイン誘導 → ログイン後再開。
    private func startEdit() {
        if EditPermission.canEdit {
            showEditSheet = true
        } else {
            showLoginPrompt = true
        }
    }

    /// この公演の参加種別を設定 (nil=取消)。UserMarkBar 表示を更新。
    private func setAttendance(_ type: AttendanceType?) {
        try? UserMarkService.shared.setAttendance(entity: .show, id: show.id, type: type)
        attendanceVersion &+= 1
    }

    private func loadSetlist() async {
        do {
            let showReading = AppContainer.shared.showReading
            setlist = try await showReading.setlist(showId: show.id)
            performersByItemId = try await showReading.allPerformers(showId: show.id)
            let songIds = setlist.map(\.songId)
            originalIdsBySongId = try await showReading.originalArtistIds(songIds: songIds)

            // 全 performer の idolId を収集して一括 fetch（N+1 解消）
            let allIdolIds = Array(Set(
                performersByItemId.values
                    .flatMap { $0 }
                    .compactMap(\.idolId)
            ))
            let fetchedIdols = try await AppContainer.shared.idolReading.idols(ids: allIdolIds)
            idolsById = Dictionary(uniqueKeysWithValues: fetchedIdols.map { ($0.id, $0) })

            // Unit 逆引き用インデックス
            unitIndex = try await AppContainer.shared.unitReading.unitIndex()

            // この公演の全出演キャスト集合 (「全員」表記の判定用)
            showAllCastIds = try await showReading.showIdolIds(showId: show.id)

            // この公演で 1-unit exact 一致した = ユニット単独曲として披露された ユニット集合
            activeUnitIds = computeActiveUnitIds(unitIndex: unitIndex)

            myPickIdolIds = Set(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol))

            // ブランド色 (フォールバックジャケ/チップのシード)。
            let brands = try await AppContainer.shared.brandReading.brands()
            brandHexById = Dictionary(uniqueKeysWithValues: brands.compactMap { brand in
                brand.color.map { (brand.id, $0) }
            })
            if let event = try await AppContainer.shared.eventReading.event(id: show.eventId) {
                self.event = event
                eventName = event.name
                if let bid = event.brandId {
                    showBrandHex = brandHexById[bid]
                }
            }

            // セトリが埋まっている公演のみ like を取得 (空 setlist は意味なし)。
            if !setlist.isEmpty {
                do {
                    let entries = try await SetlistLikeService.shared.fetch(showId: show.id)
                    likesBySongId = Dictionary(uniqueKeysWithValues: entries.map { ($0.songId, $0) })
                } catch {
                    Logger.database.warning("setlist_likes_fetch_failed: \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.database.error("load_failed setlist: \(error.localizedDescription)")
        }
    }

    private func computeActiveUnitIds(unitIndex: UnitIndex?) -> Set<String> {
        guard let unitIndex else { return [] }
        var active: Set<String> = []
        for item in setlist {
            let performers = performersByItemId[item.id] ?? []
            let perfIds = Set(performers.compactMap(\.idolId))
            guard perfIds.count >= 2 else { continue }
            for unit in unitIndex.units {
                guard let members = unitIndex.memberIds[unit.id], members.count >= 2 else { continue }
                if members == perfIds {
                    active.insert(unit.id)
                }
            }
        }
        return active
    }

    private func classifyCover(originalIds: Set<String>, performerIds: Set<String>) -> CoverType {
        if originalIds.isEmpty || performerIds.isEmpty { return .unknown }
        if originalIds == performerIds { return .original }
        if originalIds.isSubset(of: performerIds) { return .originalPlus }
        if !originalIds.isDisjoint(with: performerIds) { return .partial }
        return .cover
    }

    /// Apple Music にプレイリストを作成してセトリの曲を追加
    private func addToAppleMusicPlaylist() async {
        guard MusicKitService.shared.hasAppleMusicSubscription else {
            playlistMessage = "Apple Musicのサブスクリプションが必要です"
            showPlaylistAlert = true
            return
        }

        let songIds: [MusicItemID] = setlist.compactMap { item in
            guard let amId = item.appleMusicId, !amId.isEmpty else { return nil }
            return MusicItemID(rawValue: amId)
        }

        guard !songIds.isEmpty else {
            playlistMessage = "Apple Music IDが登録されている曲がありません"
            showPlaylistAlert = true
            return
        }

        isCreatingPlaylist = true
        playlistProgress = (0, songIds.count)
        defer { isCreatingPlaylist = false }

        do {
            // 楽曲を取得 (進捗反映)
            var songs: [MusicKit.Song] = []
            for (index, id) in songIds.enumerated() {
                let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
                if let song = try await request.response().items.first {
                    songs.append(song)
                }
                playlistProgress = (index + 1, songIds.count)
            }

            // プレイリスト作成 + 楽曲追加
            playlistProgress = (0, songs.count)
            let playlist = try await MusicLibrary.shared.createPlaylist(
                name: show.name,
                description: "アイドルライブDB から作成"
            )
            for (index, song) in songs.enumerated() {
                try await MusicLibrary.shared.add(song, to: playlist)
                playlistProgress = (index + 1, songs.count)
            }

            playlistMessage = "「\(show.name)」プレイリストを作成しました（\(songs.count)曲）"
            showPlaylistAlert = true
        } catch {
            playlistMessage = "プレイリスト作成に失敗しました: \(error.localizedDescription)"
            showPlaylistAlert = true
        }
    }

    /// 全曲プレビューを順番に再生
    private func playAllPreview() async {
        for item in setlist {
            let info = await MusicKitService.shared.fetchSongInfo(
                title: item.songTitle,
                appleMusicId: item.appleMusicId
            )
            if let previewURL = info?.previewURL {
                MusicKitService.shared.togglePreview(url: previewURL, title: item.songTitle)
                // プレビューは約30秒、次の曲まで待つ
                try? await Task.sleep(for: .seconds(32))
                if !MusicKitService.shared.isPlaying { break } // 手動停止された
            }
        }
    }
}

enum CoverType {
    case original    // オリメン完全一致
    case originalPlus // オリメン+α
    case partial     // オリメン一部
    case cover       // 完全カバー
    case unknown     // 判定不可
}

private struct SetlistSection: Identifiable {
    var id: Int
    var sectionName: String
    var items: [SetlistRow]
}

/// 予想セトリの曲追加 picker presentation 要求。`.sheet(item:)` 用に Identifiable。
/// タップごとに新インスタンス (新 id) を生成して presentation をトリガする。
struct SongPickerRequest: Identifiable {
    let id = UUID()
    /// 「出演者のオリ曲のみ」トグルの対象公演。 nil なら絞り込みトグルを出さない。
    let showId: String?
    let onSelect: ([Song]) -> Void
}
