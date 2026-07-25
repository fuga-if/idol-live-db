import SwiftUI

/// みんなの投票の push 遷移先。すべて値ベース push にして、親 (ProduceTabView) の
/// 単一 NavigationStack 上で「一覧→詳細」を一貫した順序で積む (destination クロージャ式と
/// 混在させない。混在すると詳細の上に一覧が二重表示される)。
enum PollRoute: Hashable {
    case list           // みんなの投票一覧 (PollListView)
    case detail(String) // pollId
    case hallOfFame
}

/// みんなの投票 — お題一覧。[開催中 / 終了] タブ切替。
struct PollListView: View {
    @State private var segmentIndex = 0
    @State private var vm = PollListViewModel(voting: AppContainer.shared.communityVoting)
    @State private var showCreateSheet = false

    private var currentPolls: [Poll] { vm.polls(active: segmentIndex == 0) }

    var body: some View {
        // 親 (ProduceTabView) の NavigationStack 内に push される前提。
        // 自前 NavigationStack を持つとネストして、詳細 push 時に空画面がフラッシュするため持たない。
        VStack(spacing: 0) {
                ImasSegmented(labels: ["開催中", "終了"], selection: $segmentIndex)
                    .padding(.horizontal, DS.sp5)
                    .padding(.vertical, DS.sp3)

                if vm.isLoading && currentPolls.isEmpty {
                    ImasLoadingState()
                } else if !currentPolls.isEmpty {
                    // 既にデータがあれば、リロードが一時的に失敗してもリストは消さない
                    // (引っ張って更新が通信エラーで全消えになる UX を防ぐ)。
                    pollList
                } else if let loadError = vm.loadError {
                    Spacer()
                    ImasEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "読み込みに失敗しました",
                        message: loadError
                    )
                    Spacer()
                } else {
                    Spacer()
                    ImasEmptyState(
                        systemImage: "chart.bar.doc.horizontal",
                        title: segmentIndex == 0 ? "開催中のお題がありません" : "終了したお題がありません",
                        message: segmentIndex == 0 ? "右上の「＋」から新しいお題を投稿できます。" : nil
                    )
                    Spacer()
                }
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("みんなの投票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: PollRoute.hallOfFame) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(DS.warning)
                    }
                    .accessibilityLabel("殿堂を見る")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if AuthService.shared.isSignedIn {
                        Button {
                            AppAnalytics.tap("poll_list.create")
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("お題を作成")
                    } else {
                        EmptyView()
                    }
                }
            }
            // PollRoute の遷移先は親 (ProduceTabView) の1スタックに登録済み。
            // ここ (push される側) で navigationDestination を宣言すると親スタックに
            // 登録されず詳細へ飛べなくなるため宣言しない。
            .sheet(isPresented: $showCreateSheet) {
                PollCreateSheet { newPoll in
                    vm.insertCreated(newPoll)
                }
            }
            // .task ではなく .onAppear にして、詳細画面 (削除・投票) から戻ってきた際にも
            // 再ロードされるようにする (削除したお題が一覧から消える等)。
            .onAppear { Task { await vm.load(active: segmentIndex == 0) } }
            .onChange(of: segmentIndex) { _, _ in Task { await vm.load(active: segmentIndex == 0) } }
            .refreshable { await vm.load(active: segmentIndex == 0) }
            .trackScreen("poll_list")
    }

    private var pollList: some View {
        // List ではなく ScrollView を使う。List の中に ImasListContainer (VStack) を
        // 入れると、List は ImasListContainer 全体を「1つのセル」として扱うため、
        // その1セル内に N 個の NavigationLink が詰め込まれた状態になる。
        // この状態だと、詳細から戻る時に List が「セル」を再評価する際に複数の
        // NavigationLink が同時にアクティブ状態として復元されてしまい、「戻ると
        // 隣のお題も開く」現象が起きる。ScrollView ならセル概念が無いので回避できる。
        ScrollView {
            ImasListContainer {
                ForEach(currentPolls) { poll in
                    if poll.id != currentPolls.first?.id {
                        ImasRowDivider(inset: DS.sp5)
                    }
                    NavigationLink(value: PollRoute.detail(poll.id)) {
                        PollRowView(poll: poll)
                    }
                    .buttonStyle(.plain)
                    // 一覧から直接お題を拡散できるように (詳細を開かずに誘える)。
                    .contextMenu {
                        SocialShareMenuItems(payload: .pollInvite(poll: poll), analyticsKey: "poll_list.share")
                    }
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp3)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - PollRowView

private struct PollRowView: View {
    let poll: Poll
    @Environment(\.colorScheme) private var scheme

    @State private var topSong: Song?
    @State private var topIdol: Idol?
    @State private var topUnit: Unit?

    /// 曲/アイドルで安定して塗り分けるアクセント (両者に固有色は無いので categoryKey 由来)。
    /// 1位の実写が引ければそちらを優先するので、これは無投票時のフォールバックのみで使う。
    private var accent: Color {
        ImasTheme.derive(categoryKey: poll.targetType.rawValue, scheme: scheme).accent
    }

    @ViewBuilder
    private var scopeBadge: some View {
        if let label = poll.scopeShortLabel, let icon = poll.scopeShortIcon {
            ImasChip(text: label, systemImage: icon)
        }
    }

    /// 先頭サムネイル。1位が解決できていれば曲ジャケ/アイドル写真の「実写」、
    /// まだ無投票 (topEntityId なし) ならジャンルアイコンにフォールバックする。
    @ViewBuilder
    private var thumbnail: some View {
        if poll.targetType == .song, let topSong {
            ImasArtwork(title: topSong.title, size: 42, imageURL: topSong.artworkUrl.flatMap(URL.init))
        } else if poll.targetType == .idol, let topIdol {
            IdolAvatarView(idol: topIdol, size: 42)
        } else if poll.targetType == .unit, let topUnit {
            UnitAvatarView(unit: topUnit, size: 42)
        } else {
            Image(systemName: thumbnailFallbackIcon)
                .font(.imasTitle3)
                .foregroundStyle(ColorMath.onColor(accent))
                .frame(width: 42, height: 42)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var thumbnailFallbackIcon: String {
        switch poll.targetType {
        case .song: return "music.note"
        case .idol: return "person.fill"
        case .unit: return "person.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: DS.sp3) {
            thumbnail

            VStack(alignment: .leading, spacing: DS.sp2) {
                Text(poll.title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)

                HStack(spacing: DS.sp2) {
                    scopeBadge
                    Text(poll.statusLabel)
                        .font(.imasCaption)
                        .foregroundStyle(poll.isActive ? DS.success : DS.ink3)
                    if let totalVotes = poll.totalVotes, totalVotes > 0 {
                        Text("計\(totalVotes)票")
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                    }
                }
            }
            Spacer(minLength: 8)
            ImasRowChevron()
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .contentShape(Rectangle())
        .task { await resolveTopEntity() }
    }

    private func resolveTopEntity() async {
        guard let topEntityId = poll.topEntityId else { return }
        switch poll.targetType {
        case .song:
            topSong = try? await AppContainer.shared.songReading.song(id: topEntityId)
        case .idol:
            topIdol = try? await AppContainer.shared.idolReading.idol(id: topEntityId)
        case .unit:
            topUnit = try? await AppContainer.shared.unitReading.unit(id: topEntityId)
        }
    }
}

// MARK: - Poll helpers

extension Poll {
    var isActive: Bool {
        status == "active" && endsAt > Date()
    }

    var statusLabel: String {
        if !isActive { return "終了" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endsAt).day ?? 0
        if days == 0 { return "本日締切" }
        return "残り\(days)日"
    }

    /// 一覧・ヘッダで使う、スコープを一目で示すバッジ用ラベル。 `.all` は nil。
    var scopeShortLabel: String? {
        switch scope {
        case .all:
            return nil
        case .brand:
            let count = scopeBrandIds?.count ?? 0
            return count <= 1 ? "ブランド限定" : "ブランド限定×\(count)"
        case .manual:
            let count = scopeEntityIds?.count ?? 0
            return "指定候補\(count)件"
        }
    }

    /// `scopeShortLabel` と対になる SF Symbol 名。 `.all` は nil。
    var scopeShortIcon: String? {
        switch scope {
        case .all: return nil
        case .brand: return "tag.fill"
        case .manual: return "list.bullet"
        }
    }
}
