import MusicKit
import SwiftUI

struct SetlistView: View {

    /// カタログから 1 曲を引く。
    ///
    /// `MusicCatalogResourceRequest` は非 Sendable なので、@MainActor の View 側で作って
    /// await すると隔離境界を越えて Swift 6 の厳格チェックに引っかかる。
    /// nonisolated なここでリクエストを作り、Sendable な結果だけを返す。
    nonisolated static func fetchCatalogSong(id: MusicItemID) async throws -> MusicKit.Song? {
        let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
        return try await request.response().items.first
    }

    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    let show: Show
    /// DetailSheetView の NavigationStack 内に置かれた時に渡される push クロージャ。
    /// 非 nil なら遷移は自前 sheet ではなく共有 path への push にする (sheet 多重化回避)。
    /// nil の時 (タブ内 standalone) は従来どおり自前 sheet。
    var navigate: ((DetailDestination) -> Void)? = nil
    /// 公演の画面の内部タブ。セットリスト (未来の公演でまだ無ければ出さない)・予想 (未来の公演だけ)・情報。
    private enum ShowTab: Hashable {
        case setlist, prediction, info

        var label: String {
            switch self {
            case .setlist: "セットリスト"
            case .prediction: "予想"
            case .info: "情報"
            }
        }
    }

    /// 選んでいるタブ。「次のライブ」の「セトリを予想」からは予想で開く。
    @State private var selectedTab: ShowTab
    @State private var tabsScrolledPast = false

    init(show: Show, navigate: ((DetailDestination) -> Void)? = nil, opensPrediction: Bool = false) {
        self.show = show
        self.navigate = navigate
        _selectedTab = State(initialValue: opensPrediction ? .prediction : .setlist)
    }
    /// 読み込み (単位ごとに失敗を独立させてある)。表示は下の同じ名前の値から読む。
    @State private var model = SetlistViewModel()
    private var setlist: [SetlistRow] { model.setlist }
    private var venueDirectory: VenueDirectory { model.venueDirectory }
    private var performersByItemId: [String: [PerformerRow]] { model.performersByItemId }
    private var idolsById: [String: Idol] { model.idolsById }
    private var rowMetaByItemId: [String: SetlistRowMetaRecord] { model.rowMetaByItemId }
    private var collectionSummary: ShowCollectionRecord? { model.collectionSummary }
    private var tickets: [ShowTicket] { model.tickets }
    private var brandHexById: [String: String] { model.brandHexById }
    private var brandNameById: [String: String] { model.brandNameById }
    private var showBrandHex: String? { model.showBrandHex }
    private var event: Event? { model.event }
    private var eventName: String? { model.event?.name }
    private var likesBySongId: [String: SetlistLikeService.LikeEntry] { model.likesBySongId }
    /// セトリの詳しさ (シンプル / 普通 / 詳細)。公演をまたいで保持したいので AppStorage。
    /// 保存値は文字列 (**序数で保存しない** — 並べ替えた瞬間に化ける)。
    @AppStorage("setlist_display_mode") private var displayModeRaw = ""
    /// 3 値にする前の保存値 (Bool)。**読むのは移行のためだけで、二度と書かない。**
    @AppStorage("setlist_simple_mode") private var legacySimpleMode = false

    /// 解決済みの表示モード。**移行の判断も含めて imas-core が決める**
    /// (`screen_composition::setlist_display_mode_from_stored`)。
    private var displayMode: SetlistDisplayMode {
        setlistDisplayModeFromStored(
            raw: displayModeRaw.isEmpty ? nil : displayModeRaw,
            legacySimpleMode: legacySimpleMode
        )
    }

    /// 曲名と歌唱者だけに絞る形か。**どのモードがそれに当たるかもコアが決める。**
    private var simpleMode: Bool { setlistDisplayModeIsCompact(mode: displayMode) }
    /// 歌唱者をどの名前で出すか。マイページの設定と同じ鍵を読む
    /// (公演をまたいで効く「表示の好み」なので画面には持たせない)。
    @AppStorage(PerformerNamePref.storageKey) private var performerNameRaw = PerformerNamePref.defaultRaw
    /// 保存値から解決したモード。行ごとに解決し直さないよう 1 箇所で持つ。
    private var performerName: PerformerNameMode { PerformerNamePref.mode(performerNameRaw) }
    @State private var showPlaylistAlert = false
    @State private var playlistMessage = ""
    @State private var isCreatingPlaylist = false
    @State private var playlistProgress: (current: Int, total: Int) = (0, 0)
    @State private var sheetDestination: DetailDestination?
    @State private var showEditSheet = false
    /// 未ログイン時のログイン誘導 sheet。ログイン後にセトリ編集を再開する。
    @State private var showLoginPrompt = false
    /// Good 投票で未ログインだった時のログイン誘導 (編集とは別。再開副作用なし)。
    @State private var showVoteLoginPrompt = false
    /// 参加種別 (現地/配信) を選ぶダイアログ。
    @State private var showAttendanceDialog = false
    /// 参加変更後に UserMarkBar の表示を更新するためのバージョン。
    @State private var attendanceVersion = 0
    /// 「配信参加も回収に含める」設定。**回収の答えが変わる**ので、変わったら読み直す。
    @AppStorage(AppDatabase.collectionIncludeStreamKey) private var collectionIncludeStream = false
    /// 担当アイドル ID 集合。 担当認知はアバターの二重輪 (isPick) に委ねる。
    @State private var myPickIdolIds: Set<String> = []
    /// 予想セトリの「曲を追加」picker。安定した List 上で presentation するため親が保持する
    /// (Section に sheet を付けると初回 presentation が行再評価で即閉じするため)。
    @State private var songPicker: SongPickerRequest?

    /// 公演が未来か (今日も含む)。 セトリ未登録時の文言出し分けに使う。
    /// 「今日」は JST 固定 (`JSTDay`)。公演日は日本のライブの開催日なので、
    /// 端末ローカル TZ で判定すると海外にいるユーザーだけ 1 日ずれる。
    private var isFutureShow: Bool {
        JSTDay.isTodayOrLater(show.date)
    }

    /// 感想カード (行の長押し) に載せる公演の表示名。イベント名が取れていれば
    /// 「イベント名 公演名」、公演名が既にイベント名を含む場合は重複させない。
    /// ⚠️ シェア文 (`shareSetlistText`) の 1 行目と同じ規則をコアも持っている
    /// (`setlist_share_name`)。FFI になったら、これもそちらを呼ぶ。
    private var shareName: String {
        if let eventName, !show.name.contains(eventName) {
            return "\(eventName) \(show.name)"
        }
        return show.name
    }

    /// シェア文。セトリ画面なので **セトリ本文まで載せる** (公演名・日付と会場・曲目・リンク)。
    /// 曲目を何曲で畳むかも、公演名とイベント名の重ね方も、コアが決める。
    private var shareText: String {
        shareSetlistText(input: SetlistShareInput(
            showId: show.id,
            showName: show.name,
            eventName: eventName,
            date: show.date,
            venue: venueDirectory.displayName(for: show) ?? show.venue,
            songTitles: setlist.map(\.songTitle)))
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
    /// セトリ 1 行。 シンプル表示とそれ以外の分岐ごと ForEach の外に出す。
    /// ForEach のクロージャ内に両方の巨大な View 生成式を並べると
    /// 「unable to type-check this expression in reasonable time」で通らなくなる。
    @ViewBuilder
    private func setlistRow(item: SetlistRow, index: Int) -> some View {
        let performers = performersByItemId[item.id] ?? []
        let meta = rowMetaByItemId[item.id]
        if simpleMode {
            SetlistSimpleRowView(
                item: item,
                displayNumber: index + 1,
                performerLabel: meta?.performerLabel ?? "",
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
            SetlistRowView(
                item: item,
                displayNumber: index + 1,
                performers: performers,
                idolsById: idolsById,
                unitNames: meta?.unitNames ?? [],
                isFullCast: meta?.isFullCast ?? false,
                noteGroups: meta?.noteGroups ?? [],
                performerName: performerName,
                isCharacterLive: show.isCharacterLive,
                lineup: meta?.lineup,
                performerNotes: meta?.performerNotes ?? [],
                absentOriginals: meta?.absentOriginals ?? [],
                absentHeading: meta?.absentOriginalsHeading ?? "",
                myPickIdolIds: myPickIdolIds,
                showId: show.id,
                showName: shareName,
                showDate: show.date,
                likeEntry: likesBySongId[item.songId],
                onToggleLike: { entry in
                    model.setLike(songId: item.songId, likeCount: entry.likeCount, hasUserLiked: entry.liked)
                },
                brandHex: brandHex(for: item),
                navigate: navigate,
                onRequireLogin: { showVoteLoginPrompt = true }
            )
        }
    }

    /// 表示モードのピッカーに渡す束縛。選ばれた保存値をそのまま書く
    /// (文字列 → モードの解釈はコアがやるので、ここで enum に直さない)。
    ///
    /// get 側が `displayModeRaw` そのままでないのは、移行直後 (保存値が空で
    /// 旧 Bool から解決している状態) にピッカーの選択が外れないようにするため。
    private var displayModeBinding: Binding<String> {
        Binding(
            get: { setlistDisplayModes().first { $0.mode == displayMode }?.raw ?? "" },
            set: { raw in
                AppAnalytics.tap("setlist.display_mode.\(raw)")
                withAnimation(.easeInOut(duration: 0.15)) { displayModeRaw = raw }
            }
        )
    }


    /// ブランド → イベント のパンくず。現在地 (公演) はすぐ下の大見出しが言うので、
    /// ここには出さない (同じ名前を 2 度書かない)。
    ///
    /// 名前が長いイベント (「THE IDOLM@STER MILLION LIVE! 14thLIVE」等) があるので、
    /// 1 行に収めて末尾を詰める。畳んだ先は見出しと会場カードが補う。
    @ViewBuilder
    private var breadcrumb: some View {
        if let event {
            let accent = ImasTheme.derive(seed: showBrandHex, brand: nil, scheme: scheme).accent
            HStack(spacing: DS.Space.gapTight) {
                if let brandId = event.brandId, let brandName = brandNameById[brandId] {
                    Button {
                        AppAnalytics.tap("setlist.breadcrumb.brand")
                        go(.filteredEvents(.brand(id: brandId, label: brandName)))
                    } label: {
                        Text(brandName)
                            .font(.imasCaption)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                    Image(systemName: "chevron.right")
                        .font(.imasCaption2.weight(.semibold))
                        .foregroundStyle(DS.ink3)
                }
                Button {
                    AppAnalytics.tap("setlist.breadcrumb.event")
                    go(.event(event))
                } label: {
                    Text(event.name)
                        .font(.imasCaption)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("上の階層")
        }
    }

    private func brandHex(for item: SetlistRow) -> String? {
        if let bid = item.songBrandId, let hex = brandHexById[bid] { return hex }
        return showBrandHex
    }

    /// 区切りの塊。どこで切るか・見出し (「アンコール」への畳み・区切り無しの「本編」) は
    /// imas-core (`SetlistRowMetaRecord.startsSection` / `sectionHeading`) が決める。
    /// 行の添え物がまだ無い間は、全体を 1 つの「本編」にしておく。
    private var sections: [SetlistSection] {
        var result: [SetlistSection] = []
        for item in setlist {
            let meta = rowMetaByItemId[item.id]
            if let last = result.indices.last, meta?.startsSection != true {
                result[last].items.append(item)
            } else {
                result.append(SetlistSection(
                    id: item.position, sectionName: meta?.sectionHeading ?? "本編", items: [item]))
            }
        }
        return result
    }

    /// チケット価格の表。価格帯 (複数券種) は内訳行を従える。並びと価格帯の作り方は
    /// コア (`domain/ticket_prices.rs`) 一本、ここは `ImasPriceList.Row` に写すだけ。
    private var priceRows: [ImasPriceList.Row] {
        var rows: [ImasPriceList.Row] = []
        for range in ticketPriceRanges(tickets: tickets) {
            if range.count > 1 {
                rows.append(ImasPriceList.Row(
                    id: "range-\(range.kind)",
                    label: ticketKindLabel(kind: range.kind),
                    amount: range.label,
                    note: range.hasEstimate ? "推定含む" : nil
                ))
            }
            for ticket in ticketsForKind(tickets: tickets, kind: range.kind) {
                let label = range.count > 1
                    ? (ticket.isEstimate ? "\(ticket.name) (推定)" : ticket.name)
                    : "\(ticketKindLabel(kind: range.kind))・\(ticket.name)"
                // 配信の視聴期間の注記 (公開中/終了などの判定と文言はコア)。
                let archive = ticketArchive(ticket: ticket, nowEpochSeconds: Int64(Date().timeIntervalSince1970))
                rows.append(ImasPriceList.Row(
                    id: ticket.id, label: label, amount: formatYen(amount: ticket.price),
                    note: archive?.note,
                    indented: range.count > 1
                ))
            }
        }
        return rows
    }

    /// 出すタブ。セトリのある公演・過去の公演はセットリスト、未来の公演は予想、どの公演にも情報。
    private var tabs: [ShowTab] {
        var tabs: [ShowTab] = []
        if !setlist.isEmpty || !isFutureShow { tabs.append(.setlist) }
        if isFutureShow { tabs.append(.prediction) }
        tabs.append(.info)
        return tabs
    }

    /// いま中身を出すタブ。選んでいたタブが出せないとき (未来の公演でセトリがまだ無い等) は先頭。
    /// シンプル表示はタブを畳むので、情報ではなくセトリ (無ければ予想) を出す。
    private var currentTab: ShowTab {
        let candidates = simpleMode ? tabs.filter { $0 != .info } : tabs
        return candidates.contains(selectedTab) ? selectedTab : (candidates.first ?? .setlist)
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabs.firstIndex(of: currentTab) ?? 0 },
            set: { index in
                if tabs.indices.contains(index) { selectedTab = tabs[index] }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            heroSection

            if !simpleMode {
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

                Section {
                    ImasTabs(labels: tabs.map(\.label), selection: tabSelection, seed: showBrandHex)
                        .id("show_tabs")
                        .imasTracksScrolledPast(in: "show_scroll", $tabsScrolledPast)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }

            switch currentTab {
            case .setlist: setlistContent
            case .prediction: predictionContent
            case .info: infoContent
            }
        }
        .coordinateSpace(name: "show_scroll")
        // 前のタブで下まで流していたら、次のタブは頭 (タブの見出しの下) から見せる。
        .onChange(of: selectedTab) { _, _ in
            if tabsScrolledPast { proxy.scrollTo("show_tabs", anchor: .top) }
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
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("この公演をシェア")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // 3 値なのでトグルではなく選ぶ形にする。Menu の中の Picker なので
                    // 画面の行は 1 行も増えず、いま選んでいるものにチェックが付く。
                    // 並びも文言も imas-core (`setlistDisplayModes`) が持つ。
                    Picker("表示", selection: displayModeBinding) {
                        ForEach(setlistDisplayModes(), id: \.raw) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                    .pickerStyle(.inline)

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
        .imasSavingOverlay(
            isCreatingPlaylist,
            label: playlistProgress.total > 0
                ? "プレイリスト作成中… \(playlistProgress.current)/\(playlistProgress.total)"
                : "プレイリスト作成中…"
        )
        .imasLoadAfterTransition { await loadSetlist() }
        // 参加の付け外しと「配信も回収に含める」設定で回収の札と要約が変わるので、
        // それも鍵に含める (表示モードと歌唱者の設定と同じ扱い)。
        .task(
            id: "\(performerNameRaw)|\(displayModeRaw)|\(legacySimpleMode)|\(attendanceVersion)|\(collectionIncludeStream)"
        ) {
            await loadRowMeta()
        }
        .task { await model.loadVenueDirectory() }
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
        do {
            try UserMarkService.shared.setAttendance(entity: .show, id: show.id, type: type)
        } catch {
            LocalWriteFailure.report(error, action: "参加の記録")
        }
        attendanceVersion &+= 1
    }

    // MARK: - 頭

    /// 上の階層 (ブランド → イベント) へのパンくず + 公演名の大見出し + 会場と日付の 1 行。
    /// ナビの戻るは「どこから来たか」しか辿れない (深リンクや検索から直接開くと
    /// 戻り先が無い)。この画面がライブの木のどこに居るのかを示して、
    /// 上の階層へ直接行けるようにする。会場の詳しいこと (キャパ・配信) とチケットは情報タブ。
    @ViewBuilder
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                breadcrumb
                Text(show.name)
                    .imasText(.heroTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
        }
        Section {
            ImasNote([venueDirectory.displayName(for: show), show.date]
                .compactMap { $0 }.joined(separator: " ・ "))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - セットリスト

    @ViewBuilder
    private var setlistContent: some View {
        if setlist.isEmpty {
            Section {
                ImasEmptyState(
                    systemImage: "music.note.list",
                    title: "セトリ未登録",
                    message: "このライブのセトリはまだ登録されていません。ログインして編集に参加できます",
                    actionTitle: EditPermission.showEditAffordance ? "セトリを追加" : nil,
                    action: EditPermission.showEditAffordance ? { startEdit() } : nil,
                    seed: showBrandHex
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } else {
            // 良かった曲に投票しよう Note / 未ログインはログイン導線。
            // シンプル表示では出さない。 投票導線はシンプル表示に 👍 自体が無いので意味が無く、
            // スクショに誘導文が写り込むだけになる。
            if !simpleMode {
                Section {
                    Group {
                        if AuthService.shared.isSignedIn {
                            ImasNote("良かったと思った曲に 👍 で投票しよう！", systemImage: "hand.thumbsup.fill")
                        } else {
                            ImasSignInPrompt(message: "👍 で投票するにはログインが必要です")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }

            collectionSummarySection

            ForEach(sections) { section in
                Section(header: ImasSectionHeader(section.sectionName, style: .small).textCase(nil)) {
                    // セクションの曲を 1 枚の紙にまとめ、切り取り線で区切る (セトリ・申込書と同じ紙面)。
                    ImasCardList(style: .sheet) {
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
    }

    // MARK: - 予想

    /// 未来の公演の予想。セトリがまだ無ければ「公演前です」も添える。
    @ViewBuilder
    private var predictionContent: some View {
        SetlistPredictionView(
            showId: show.id,
            showName: show.name,
            seed: showBrandHex,
            presentSongPicker: { onSelect in
                songPicker = SongPickerRequest(showId: show.id, onSelect: onSelect)
            }
        )
        .environment(database)

        if setlist.isEmpty {
            Section {
                ImasEmptyState(
                    systemImage: "calendar.badge.clock",
                    title: "公演前です",
                    message: "セトリは公演後に登録されます",
                    seed: showBrandHex
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - 情報

    /// 会場・キャパ・配信・日付と、チケットの価格。
    @ViewBuilder
    private var infoContent: some View {
        Section {
            ImasCardList {
                // 会場は ID で持つ。表示は公演日時点の名前 (改名前の公演は当時名)。
                if let venueLabel = venueDirectory.displayName(for: show) {
                    if let vid = show.venueId {
                        Button { go(.filteredShows(.venue(vid))) } label: {
                            ImasValueRow(key: "会場", value: venueLabel, isLink: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ImasValueRow(key: "会場", value: venueLabel)
                    }
                    ImasRowDivider(inset: 16)
                }
                // キャパが分かる会場では規模も出す (ホール指定があればホール側を優先)。
                if let cap = venueDirectory.capacity(for: show) {
                    ImasValueRow(key: "キャパ", value: "\(cap.formatted(.number.grouping(.automatic)))人", monospaced: true)
                    ImasRowDivider(inset: 16)
                }
                if let stream = show.streamPlatform, !stream.isEmpty {
                    ImasValueRow(key: "配信", value: stream)
                    ImasRowDivider(inset: 16)
                }
                Button { go(.filteredShows(.date(show.date))) } label: {
                    ImasValueRow(key: "日付", value: show.date, isLink: true)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
        }

        if !tickets.isEmpty {
            Section {
                ImasSectionHeader("チケット", style: .small)
                ImasPriceList(rows: priceRows)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
        }
    }

    /// 自分の回収の要約。セトリの真上に置いて、この下の並びの読み方を先に言う。
    ///
    /// **文言も出す/出さないも imas-core が決める** (`collectionSummary` が nil なら
    /// 何も出さない)。ここが持つのは「参加した公演は済んだ記録の札」という見た目だけ。
    @ViewBuilder
    private var collectionSummarySection: some View {
        if let summary = collectionSummary, !setlist.isEmpty {
            Section {
                // 札 (ImasBadge) は 1 行の短い値向けで、長い文だと大きい文字設定で切れる。
                // ここは文なので折り返す ImasNote を使う。
                ImasNote(summary.label, systemImage: summary.attended ? "checkmark.seal.fill" : "circle.dashed")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func loadSetlist() async {
        await model.load(show: show)
        myPickIdolIds = Set(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol))
    }

    /// 行の添え物と回収の要約を読み直す。**歌唱者の表示名の設定・表示モード・参加記録・
    /// 「配信も回収に含める」設定で答えが変わる**ので、それらを鍵にした `.task(id:)` から
    /// 呼ぶ (画面を開き直さなくても追従する)。
    private func loadRowMeta() async {
        await model.loadRowMeta(showId: show.id, nameMode: performerName, displayMode: displayMode)
    }

    /// Apple Music にプレイリストを作成してセトリの曲を追加
    private func addToAppleMusicPlaylist() async {
        // 認可は起動時に取らないので、使う直前に取る (契約の有無もここで読み直す)。
        await MusicKitService.shared.requestAuthorization()
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
                // MusicCatalogResourceRequest は非 Sendable。@MainActor の文脈で作って
                // await すると隔離境界を越えるので、nonisolated な口の中で作って返す。
                if let song = try await Self.fetchCatalogSong(id: id) {
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
            let info = await MusicKitService.shared.fetchSongInfo(appleMusicId: item.appleMusicId)
            if let previewURL = info?.previewURL {
                MusicKitService.shared.togglePreview(url: previewURL, songId: item.songId)
                // プレビューは約30秒、次の曲まで待つ
                try? await Task.sleep(for: .seconds(32))
                if !MusicKitService.shared.isPlaying { break } // 手動停止された
            }
        }
    }
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
