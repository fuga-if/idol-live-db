import SwiftUI

/// お題詳細・ランキング・投票。
struct PollDetailView: View {
    @Environment(AppDatabase.self) private var database
    @State private var vm: PollDetailViewModel
    @State private var showVotePicker = false
    @State private var showLogin = false

    // 投票用アイドル一覧（アイドルお題時に事前ロード）。master 参照なので View 側に残す。
    @State private var allIdols: [Idol] = []

    init(pollId: String) {
        _vm = State(initialValue: PollDetailViewModel(pollId: pollId, voting: AppContainer.shared.communityVoting))
    }

    private var poll: Poll? { vm.poll }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .toolbar {
            if let poll, canDelete(poll: poll) {
                ToolbarItem(placement: .topBarTrailing) {
                    deleteButton(poll: poll)
                }
            }
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
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
    }

    // MARK: - Header

    private func pollHeader(poll: Poll) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            Text(poll.title)
                .font(.imasTitle2.weight(.bold))
                .foregroundStyle(DS.ink)

            if let desc = poll.description, !desc.isEmpty {
                Text(desc)
                    .font(.imasBody)
                    .foregroundStyle(DS.ink2)
            }

            HStack(spacing: DS.sp2) {
                ImasChip(text: poll.targetType == .song ? "曲" : "アイドル")
                ImasChip(text: poll.statusLabel)
            }
        }
    }

    // MARK: - Ranking

    private func rankingSection(detail: PollDetail) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ランキング", count: detail.entries.isEmpty ? nil : "\(detail.entries.count)曲")

            if detail.entries.isEmpty {
                ImasEmptyState(systemImage: "chart.bar", title: "まだ票がありません", message: "最初の一票を入れましょう！")
            } else {
                ImasListContainer {
                    ForEach(Array(detail.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().background(DS.sep).padding(.leading, 56)
                        }
                        PollEntryRow(
                            rank: index + 1,
                            entry: entry,
                            targetType: detail.poll.targetType,
                            canVote: AuthService.shared.isSignedIn && detail.poll.isActive,
                            remaining: vm.remaining,
                            isAnyVoting: vm.isVoting,
                            onVote: { await vm.vote(entityId: entry.entityId) },
                            onUnvote: { await vm.unvote(entityId: entry.entityId) }
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
            InlineLoginPrompt(message: "投票にはログインが必要です")
        } else if detail.poll.isActive {
            let remaining = vm.remaining
            VStack(spacing: DS.sp3) {
                if let msg = vm.errorMessage {
                    Text(msg)
                        .font(.imasFootnote)
                        .foregroundStyle(DS.danger)
                }

                // ランキングの各行で直接投票できるので、このボタンは「新しい候補を追加」専用。
                Text("👍 上のランキングをタップで投票/取消（残り\(remaining)/3）")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    AppAnalytics.tap("poll_detail.add_vote")
                    showVotePicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(remaining > 0 ? "候補を追加して投票（残り\(remaining)/3）" : "投票済み（3/3）")
                            .font(.imasSubhead.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.sp3)
                    .background(remaining > 0 ? DS.sys : DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                    .foregroundStyle(remaining > 0 ? DS.bg : DS.ink3)
                }
                .disabled(remaining <= 0 || vm.isVoting)
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showVotePicker) {
                if detail.poll.targetType == .song {
                    SongSearchPickerView { songs in
                        showVotePicker = false
                        let ids = Array(songs.prefix(remaining)).map(\.id)
                        Task { await vm.voteForEntities(ids) }
                    }
                    .environment(database)
                } else {
                    IdolMultiPickerView(
                        selected: Set(detail.entries.filter(\.hasUserVoted).map(\.entityId)),
                        idols: allIdols
                    ) { selectedIds in
                        showVotePicker = false
                        let alreadyVoted = Set(detail.entries.filter(\.hasUserVoted).map(\.entityId))
                        let newIds = Array(Array(selectedIds.subtracting(alreadyVoted)).prefix(remaining))
                        Task { await vm.voteForEntities(newIds) }
                    }
                    .environment(database)
                }
            }
        }
        // 終了済みの場合は投票 UI なし（ランキングのみ表示）
    }

    // MARK: - Delete

    private func canDelete(poll: Poll) -> Bool {
        guard let userId = AuthService.shared.userId else { return false }
        return AuthService.shared.isAdmin || poll.createdBy == userId
    }

    private func deleteButton(poll: Poll) -> some View {
        Button(role: .destructive) {
            AppAnalytics.tap("poll_detail.delete")
            // ナビゲーションスタックを戻る（dismiss はここでは不可なのでフラグ等で制御）
            Task { await vm.delete() }
        } label: {
            Image(systemName: "trash")
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
        // アクティブなお題を未ログインで開いたら、表示時点でログイン誘導 (投票はログイン必須)。
        // 「投票しようとして初めてログイン判定」を避け、最初に意図を明示する。
        if vm.poll?.isActive == true, !AuthService.shared.isSignedIn {
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

    @State private var resolvedSong: Song?
    @State private var resolvedIdol: Idol?
    @State private var isBusy = false

    /// 未投票だが残票が無い (この候補にはこれ以上投票できない)。
    private var voteDisabled: Bool { !entry.hasUserVoted && remaining <= 0 }

    /// 他の行/ボタンが投票処理中 (自分が処理中の場合は除く) なので操作をロックする。
    private var lockedByOther: Bool { isAnyVoting && !isBusy }

    var body: some View {
        HStack(spacing: DS.sp3) {
            TagRankBadge(rank: rank)
                .frame(width: 30, alignment: .center)

            entityView

            Spacer(minLength: 8)

            HStack(spacing: DS.sp2) {
                Text("\(entry.voteCount)票")
                    .font(.imasCaption.monospacedDigit())
                    .foregroundStyle(DS.ink2)

                if canVote {
                    // ワンタップ投票/取消トグル。未投票=アウトライン、投票済み=塗り。
                    Button {
                        guard !isBusy, !voteDisabled, !lockedByOther else { return }
                        isBusy = true
                        Task {
                            if entry.hasUserVoted { await onUnvote() } else { await onVote() }
                            isBusy = false
                        }
                    } label: {
                        Image(systemName: isBusy ? "hourglass" : (entry.hasUserVoted ? "hand.thumbsup.fill" : "hand.thumbsup"))
                            .font(.imasScaled(18))
                            .foregroundStyle(entry.hasUserVoted ? DS.success : (voteDisabled || lockedByOther ? DS.ink3 : DS.sys))
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(voteDisabled || lockedByOther)
                } else if entry.hasUserVoted {
                    Image(systemName: "hand.thumbsup.fill")
                        .foregroundStyle(DS.ink3)
                        .font(.imasScaled(18))
                }
            }
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .task { await resolveEntity() }
    }

    @ViewBuilder
    private var entityView: some View {
        if targetType == .song, let song = resolvedSong {
            SongTitleRow(song: song, showsChevron: false)
        } else if targetType == .idol, let idol = resolvedIdol {
            IdolNameRow(idol: idol, showsChevron: false)
        } else {
            Text(entry.entityId)
                .font(.imasSubhead.weight(.semibold))
                .foregroundStyle(DS.ink)
                .lineLimit(1)
        }
    }

    private func resolveEntity() async {
        if targetType == .song {
            resolvedSong = try? await AppContainer.shared.songReading.song(id: entry.entityId)
        } else {
            resolvedIdol = try? await AppContainer.shared.idolReading.idol(id: entry.entityId)
        }
    }
}
