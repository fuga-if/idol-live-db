import SwiftUI

/// お題詳細・ランキング・投票。
struct PollDetailView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PollDetailViewModel
    @State private var showVotePicker = false
    @State private var showLogin = false
    /// 削除ボタンタップ→即実行を防ぐ確認ダイアログの表示状態。
    @State private var showDeleteConfirm = false
    /// 未ログイン時のログイン誘導シートを初回表示でのみ出すためのガード
    /// (pull-to-refresh のたびに再ポップしないように)。
    @State private var didPromptLogin = false
    /// ランキングの曲/アイドルをタップで開く詳細シート。
    @State private var sheetDestination: DetailDestination?
    /// 結果の画像をシェアするシート。
    @State private var showResultShare = false

    // 投票用アイドル一覧（アイドルお題時に事前ロード）。master 参照なので View 側に残す。
    @State private var allIdols: [Idol] = []
    // 投票用ユニット一覧（ユニットお題時に事前ロード）。
    @State private var allUnits: [Unit] = []
    /// スコープ表示用のブランド辞書 (brand スコープ時のみ使う)。
    @State private var brandsById: [String: Brand] = [:]
    /// 自分が投票した候補の表示名 (シェア文面用)。entityId は不透明キーなので master で解決する。
    @State private var myVoteNames: [String] = []

    init(pollId: String) {
        _vm = State(initialValue: PollDetailViewModel(pollId: pollId, voting: AppContainer.shared.communityVoting))
    }

    private var poll: Poll? { vm.poll }

    var body: some View {
        Group {
            if vm.isLoading {
                ImasLoadingState()
            } else if let detail = vm.detail {
                contentView(detail: detail)
            } else {
                ImasEmptyState(systemImage: "exclamationmark.triangle", title: "読み込みに失敗しました")
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(poll?.title ?? "お題")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .trackScreen("poll_detail")
        .sheet(isPresented: $showLogin) {
            // ログイン完了で再ロード → myVoteCount 反映 + 投票可能に。
            LoginToEditSheet(onSignedIn: { Task { await loadDetail() } })
        }
        .sheet(isPresented: $showResultShare) {
            if let detail = vm.detail {
                PollResultShareSheet(poll: detail.poll, entries: detail.entries)
            }
        }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .toolbar {
            if let poll {
                ToolbarItem(placement: .topBarTrailing) {
                    // 結果の画像 (票が入ってから) と、お題そのもののシェア (「このお題に投票しよう！」、常に出す)。
                    Menu {
                        if vm.detail?.entries.isEmpty == false {
                            Section {
                                Button {
                                    AppAnalytics.tap("poll_detail.share_result_image")
                                    showResultShare = true
                                } label: {
                                    Label("結果を画像でシェア", systemImage: "photo")
                                }
                            }
                        }
                        Section {
                            SocialShareMenuItems(payload: .pollInvite(poll: poll), analyticsKey: "poll_detail.share_poll")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("シェア")
                }
            }
            if let poll, canDelete(poll: poll) {
                ToolbarItem(placement: .topBarTrailing) {
                    deleteButton(poll: poll)
                }
            }
        }
        // 自分の票が変わるたびに表示名を解決し直す (シェア文面の候補名に使う)。
        .task(id: myVotedEntityIds) { await loadMyVoteNames() }
        .imasErrorAlert("エラー", message: Binding(
            get: { vm.deleteErrorMessage },
            set: { vm.deleteErrorMessage = $0 }
        ))
        .confirmationDialog(
            "このお題を削除しますか？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { performDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ランキング・投票データも一緒に削除され、元に戻せません。")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(detail: PollDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sp5) {
                pollHeader(poll: detail.poll)
                rankingSection(detail: detail)
                voteSection(detail: detail)
                // 自分の投票のシェアは締切後も残す (結果が出てからの方が話題になる)。
                myVoteShareBar(poll: detail.poll)
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
        .refreshable { await loadDetail() }
    }

    // MARK: - Header

    private func pollHeader(poll: Poll) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            Text(poll.title).imasText(.sectionTitle)

            if let desc = poll.description, !desc.isEmpty {
                Text(desc).imasText(.body, color: DS.ink2)
            }

            HStack(spacing: DS.sp2) {
                ImasChip(text: poll.targetType.label)
                ImasChip(text: poll.statusLabel)
            }

            scopeChips(poll: poll)
        }
    }

    /// 候補スコープを表す小さなチップ列 (all は何も出さない)。
    @ViewBuilder
    private func scopeChips(poll: Poll) -> some View {
        switch poll.scope {
        case .all:
            EmptyView()
        case .brand:
            let ids = poll.scopeBrandIds ?? []
            if !ids.isEmpty {
                HStack(spacing: DS.sp2) {
                    Image(systemName: "tag.fill")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.sp2) {
                            ForEach(ids, id: \.self) { id in
                                if let brand = brandsById[id] {
                                    ImasChip(text: brand.shortName, seed: brand.color)
                                } else {
                                    ImasChip(text: id)
                                }
                            }
                        }
                    }
                }
                .padding(.top, DS.sp1)
            }
        case .manual:
            let count = poll.scopeEntityIds?.count ?? 0
            HStack(spacing: DS.sp2) {
                Image(systemName: "list.bullet")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
                ImasChip(text: "候補\(count)件から選択")
            }
            .padding(.top, DS.sp1)
        }
    }

    // MARK: - Share

    /// 自分が投票した候補の entityId (ランキング順)。シェア文面と名前解決のキー。
    private var myVotedEntityIds: [String] {
        vm.detail?.entries.filter(\.hasUserVoted).map(\.entityId) ?? []
    }

    /// 「〇〇に投票しました！」のシェア内容。名前が1つも解決できていなければ nil。
    private func myVotePayload(poll: Poll) -> SharePayload? {
        guard !myVoteNames.isEmpty else { return nil }
        return sharePollVotesPayload(pollId: poll.id, pollTitle: poll.title, entityNames: myVoteNames)
    }

    @ViewBuilder
    private func myVoteShareBar(poll: Poll) -> some View {
        if let payload = myVotePayload(poll: poll) {
            HStack(spacing: DS.sp2) {
                Text("あなたの投票 \(myVoteNames.count)/\(CommunityVoteLimit.perTarget)")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
                Spacer(minLength: 8)
                SocialShareMenu(payload: payload, analyticsKey: "poll_detail.share_votes") {
                    SocialShareChipLabel(title: "投票をシェア")
                }
                .accessibilityLabel("自分の投票をシェア")
            }
        }
    }

    /// entityId (不透明キー) を master から表示名に解決する。解決できない候補は落とす
    /// (シェア文面に生 ID が出るより、その候補が抜けている方がマシ)。
    private func loadMyVoteNames() async {
        let ids = myVotedEntityIds
        guard !ids.isEmpty, let targetType = vm.poll?.targetType else {
            myVoteNames = []
            return
        }
        // マイ投票一覧 (MyVotesView) と同じくバッチ解決する。1件ずつ await すると票数分の
        // ラウンドトリップになるうえ、名前の出どころが2系統に割れる。
        let namesById: [String: String]
        switch targetType {
        case .song:
            let songs = (try? await AppContainer.shared.songReading.songs(ids: ids)) ?? []
            namesById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0.title) })
        case .idol:
            let idols = (try? await AppContainer.shared.idolReading.idols(ids: ids)) ?? []
            namesById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0.name) })
        case .unit:
            let units = (try? await AppContainer.shared.unitReading.allUnits()) ?? []
            namesById = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0.displayName) })
        }
        myVoteNames = ids.compactMap { namesById[$0] }
    }

    // MARK: - Ranking

    private func rankingSection(detail: PollDetail) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(
                title: "ランキング",
                count: detail.entries.isEmpty ? nil : "\(detail.entries.count)\(entryCountUnit(for: detail.poll.targetType))"
            )

            if detail.entries.isEmpty {
                ImasEmptyState(systemImage: "chart.bar", title: "まだ票がありません", message: "最初の一票を入れましょう！")
            } else {
                // 同票は同じ順位 (結果の画像と同じ数え方、コアの pollCompetitionRanks)。
                let ranks = pollCompetitionRanks(votes: detail.entries.map { UInt32(clamping: $0.voteCount) })
                ImasCardList {
                    ForEach(Array(detail.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            ImasRowDivider(inset: 56)
                        }
                        PollEntryRow(
                            rank: Int(ranks[index]),
                            entry: entry,
                            targetType: detail.poll.targetType,
                            canVote: AuthService.shared.isSignedIn && detail.poll.isActive,
                            remaining: vm.remaining,
                            isAnyVoting: vm.isVoting,
                            onVote: { await vm.vote(entityId: entry.entityId) },
                            onUnvote: { await vm.unvote(entityId: entry.entityId) },
                            onOpenDetail: { sheetDestination = $0 }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Vote Section

    @ViewBuilder
    private func voteSection(detail: PollDetail) -> some View {
        if !AuthService.shared.isSignedIn {
            ImasSignInPrompt(message: "投票にはログインが必要です")
        } else if detail.poll.isActive {
            let remaining = vm.remaining
            let scope = detail.poll.scope
            VStack(spacing: DS.sp3) {
                if let msg = vm.errorMessage {
                    Text(msg).imasText(.note, color: DS.danger)
                }

                // ランキングの各行で直接投票できるので、このボタンは「新しい候補を追加」専用。
                ImasNote("👍 上のランキングをタップで投票/取消（残り\(remaining)/\(CommunityVoteLimit.perTarget)）")

                // manual スコープは候補がすでにランキングに全件並んでいるので「候補を追加」ボタン不要。
                if scope != .manual {
                    ImasButton(
                        title: remaining > 0
                            ? "候補を追加して投票（残り\(remaining)/\(CommunityVoteLimit.perTarget)）"
                            : "投票済み（\(CommunityVoteLimit.perTarget)/\(CommunityVoteLimit.perTarget)）",
                        systemImage: "plus.circle.fill",
                        size: .large
                    ) {
                        AppAnalytics.tap("poll_detail.add_vote")
                        showVotePicker = true
                    }
                    .disabled(remaining <= 0 || vm.isVoting)
                }
            }
            .sheet(isPresented: $showVotePicker) {
                votePicker(detail: detail)
            }
        }
        // 終了済みの場合は投票 UI なし（ランキングのみ表示）
    }

    @ViewBuilder
    private func votePicker(detail: PollDetail) -> some View {
        let scope = detail.poll.scope
        let brandIds = scope == .brand ? Set(detail.poll.scopeBrandIds ?? []) : nil
        switch detail.poll.targetType {
        case .song:
            // 投票済みの曲は除き、残票分だけ入れる (選び方はコアの planVoteSelection)。
            SongSearchPickerView(restrictedBrandIds: brandIds) { songs in
                showVotePicker = false
                let plan = planVoteSelection(
                    alreadyVoted: detail.entries.filter(\.hasUserVoted).map(\.entityId),
                    selectedInOrder: songs.map(\.id),
                    myVoteCount: UInt32(clamping: detail.myVoteCount), unvoteDeselected: false)
                Task { await vm.voteForEntities(plan.toVote) }
            }
            .environment(database)
        case .idol:
            let pickIdols: [Idol] = {
                if let allowed = brandIds {
                    return allIdols.filter { allowed.contains($0.brandId) }
                }
                return allIdols
            }()
            IdolPickerView(
                title: "投票する",
                idols: pickIdols,
                selected: Set(detail.entries.filter(\.hasUserVoted).map(\.entityId))
            ) { selectedIds in
                showVotePicker = false
                Task { await vm.applyPickerSelection(selectedIds, ordered: pickIdols.map(\.id)) }
            }
            .environment(database)
        case .unit:
            let pickUnits: [Unit] = {
                if let allowed = brandIds {
                    return allUnits.filter { allowed.contains($0.brandId) }
                }
                return allUnits
            }()
            UnitMultiPickerView(
                selected: Set(detail.entries.filter(\.hasUserVoted).map(\.entityId)),
                units: pickUnits
            ) { selectedIds in
                showVotePicker = false
                Task { await vm.applyPickerSelection(selectedIds, ordered: pickUnits.map(\.id)) }
            }
        }
    }


    /// ランキング件数表示の単位。お題の対象種別で数え方の助数詞が変わる (曲/人/組)。
    private func entryCountUnit(for targetType: PollTargetType) -> String {
        switch targetType {
        case .song: return "曲"
        case .idol: return "人"
        case .unit: return "組"
        }
    }

    // MARK: - Delete

    /// 自分のお題かはサーバ (`is_own_poll`) が決める。admin はどのお題でも消せる。
    private func canDelete(poll: Poll) -> Bool {
        AuthService.shared.isAdmin || poll.isOwnPoll == true
    }

    private func deleteButton(poll: Poll) -> some View {
        ImasIconButton(systemImage: "trash", label: "このお題を削除", style: .plain, isLoading: vm.isDeleting) {
            AppAnalytics.tap("poll_detail.delete")
            showDeleteConfirm = true
        }
        .disabled(vm.isDeleting)
    }

    private func performDelete() {
        Task {
            if await vm.delete() {
                // 削除成功時のみ pop。一覧側は PollListView の再表示時 (.onAppear) の
                // 再ロードで自動的に消える。
                dismiss()
            }
        }
    }

    // MARK: - Data Loading

    /// 投票ロジックは VM。ここでは VM のロードに加え、アイドルお題のピッカー用に
    /// master (AppDatabase) から全アイドルを事前ロードする (master 参照は View 側の責務)。
    private func loadDetail() async {
        await vm.load()
        if vm.poll?.targetType == .idol {
            allIdols = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
        }
        if vm.poll?.targetType == .unit {
            allUnits = (try? await AppContainer.shared.unitReading.unitsWithSongs()) ?? []
        }
        if vm.poll?.scope == .brand, brandsById.isEmpty {
            let list = (try? await AppContainer.shared.brandReading.brands()) ?? []
            brandsById = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
        // アクティブなお題を未ログインで開いたら、表示時点でログイン誘導 (投票はログイン必須)。
        // 「投票しようとして初めてログイン判定」を避け、最初に意図を明示する。
        // ただし初回のみ (didPromptLogin) — さもないと refreshable/再 loadDetail のたびに
        // ログインシートが再ポップしてしまう。
        if vm.poll?.isActive == true, !AuthService.shared.isSignedIn, !didPromptLogin {
            didPromptLogin = true
            showLogin = true
            AppAnalytics.event("login_prompt", ["where": "poll"])
        }
    }
}

// MARK: - PollEntryRow

private struct PollEntryRow: View {
    let rank: Int
    let entry: PollEntry
    let targetType: PollTargetType
    /// 投票トグルを出すか (= ログイン済み かつ 開催中)。未ログイン/終了時は読み取り専用。
    let canVote: Bool
    /// 残り投票可能数 (未投票の候補に投票できるか判定)。
    let remaining: Int
    /// 画面内のいずれかの投票/取消が進行中か。連打防止のため他の行をロックする。
    let isAnyVoting: Bool
    let onVote: () async -> Void
    let onUnvote: () async -> Void
    /// 曲/アイドル名をタップしたとき、解決済みの詳細を開く。
    let onOpenDetail: (DetailDestination) -> Void

    @State private var resolvedSong: Song?
    @State private var resolvedIdol: Idol?
    @State private var resolvedUnit: Unit?
    @State private var isBusy = false
    @State private var imageService = CustomImageService.shared

    /// 未投票だが残票が無い (この候補にはこれ以上投票できない)。
    private var voteDisabled: Bool { !entry.hasUserVoted && remaining <= 0 }

    /// 他の行/ボタンが投票処理中 (自分が処理中の場合は除く) なので操作をロックする。
    private var lockedByOther: Bool { isAnyVoting && !isBusy }

    private var title: String {
        switch targetType {
        case .song: return resolvedSong?.title ?? entry.entityId
        case .idol: return resolvedIdol?.name ?? entry.entityId
        case .unit: return resolvedUnit?.displayName ?? entry.entityId
        }
    }

    /// アイドル候補は写真があれば写真、無ければ `ImasAvatar` 自身の判子 (アイコンを消さない)。
    /// 判子の文字は前どおり略称。ユニット候補は `ImasForecastRow` に `unit:` を渡して解決する。
    private var avatar: (label: String, imageURL: URL?, seed: String?)? {
        guard targetType == .idol, let resolvedIdol else { return nil }
        return (resolvedIdol.shortName, imageService.imageURL(for: resolvedIdol.id), resolvedIdol.color)
    }

    /// 曲の副題 (ユニット名、無ければ歌唱者の表記)。アイドル・ユニット候補には付けない (前どおり)。
    private var subtitle: String? {
        guard targetType == .song, let resolvedSong else { return nil }
        return resolvedSong.unitName ?? resolvedSong.singerLabel
    }

    /// ジャケが無いときの面の色 (曲のブランド色)。
    private var brandHex: String? {
        guard targetType == .song else { return nil }
        return resolvedSong.flatMap { BrandColors.hex(for: $0.brandId) }
    }

    /// 曲の試聴の配線 (楽曲一覧の行と同じ MusicKitService)。
    private var previewURL: URL? {
        guard targetType == .song else { return nil }
        return resolvedSong.flatMap { URL.safeHTTP(string: $0.previewUrl) }
    }

    private var isPreviewing: Bool {
        guard targetType == .song, let resolvedSong else { return false }
        return MusicKitService.shared.isPlaying(songId: resolvedSong.id)
    }

    private func onPreviewTap() {
        guard let resolvedSong, let previewURL else { return }
        MusicKitService.shared.togglePreview(url: previewURL, songId: resolvedSong.id)
    }

    /// 長押しでコピーできる項目 (曲名・よみ・歌唱者 / アイドル名・よみ)。ユニットは前どおり無し。
    var body: some View {
        ImasForecastRow(
            rank: rank,
            title: title,
            subtitle: subtitle,
            artworkURL: targetType == .song ? resolvedSong?.artworkUrl.flatMap(URL.init(string:)) : nil,
            brand: brandHex,
            avatar: avatar,
            unit: targetType == .unit ? resolvedUnit : nil,
            previewURL: previewURL,
            isPreviewing: isPreviewing,
            onPreviewTap: onPreviewTap,
            measure: .votes(entry.voteCount, share: 0),
            showsProportionLine: false,
            isMine: entry.hasUserVoted,
            onVote: canVote ? {
                guard !isBusy, !voteDisabled, !lockedByOther else { return }
                isBusy = true
                Task {
                    if entry.hasUserVoted { await onUnvote() } else { await onVote() }
                    isBusy = false
                }
            } : nil,
            voteLabel: "投票する",
            votedLabel: "投票済み",
            voteAccessibilityLabel: "投票",
            votedAccessibilityLabel: "投票を取消",
            voteDisabled: voteDisabled || lockedByOther,
            isVoteLoading: isBusy,
            showsChevron: true,
            combineAccessibility: false
        )
        // Button でラップすると内側のジャケ写プレビュー再生タップが吸われてしまう
        // (SongListView と同じ iOS 18 の button-in-button 問題)。行全体は onTapGesture
        // で遷移を受け、投票ボタン自身のタップは独立して機能させる。
        .contentShape(Rectangle())
        .onTapGesture {
            if detailDestination != nil { openDetail() }
        }
        .accessibilityAction {
            if detailDestination != nil { openDetail() }
        }
        .task { await resolveEntity() }
    }

    /// 解決済みの曲/アイドル/ユニットから詳細遷移先を作る (未解決なら nil)。
    private var detailDestination: DetailDestination? {
        if targetType == .song, let song = resolvedSong { return .song(song) }
        if targetType == .idol, let idol = resolvedIdol { return .idol(idol) }
        if targetType == .unit, let unit = resolvedUnit { return .unit(unit) }
        return nil
    }

    private func openDetail() {
        guard let dest = detailDestination else { return }
        AppAnalytics.tap("poll_detail.open_entity")
        onOpenDetail(dest)
    }

    private func resolveEntity() async {
        switch targetType {
        case .song:
            resolvedSong = try? await AppContainer.shared.songReading.song(id: entry.entityId)
        case .idol:
            resolvedIdol = try? await AppContainer.shared.idolReading.idol(id: entry.entityId)
        case .unit:
            resolvedUnit = try? await AppContainer.shared.unitReading.unit(id: entry.entityId)
        }
    }
}
