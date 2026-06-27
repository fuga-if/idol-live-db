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
                    Spacer()
                    ProgressView()
                    Spacer()
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: PollRoute.hallOfFame) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if AuthService.shared.isSignedIn {
                        Button {
                            AppAnalytics.tap("poll_list.create")
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
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
            .task { await vm.load(active: segmentIndex == 0) }
            .onChange(of: segmentIndex) { _, _ in Task { await vm.load(active: segmentIndex == 0) } }
            .refreshable { await vm.load(active: segmentIndex == 0) }
            .trackScreen("poll_list")
    }

    private var pollList: some View {
        List {
            ImasListContainer {
                ForEach(currentPolls.indexed(), id: \.element.id) { index, poll in
                    if index > 0 {
                        Divider().background(DS.sep).padding(.leading, DS.sp5)
                    }
                    // NavigationLink を可視ラベルで使うと List 文脈でシステムの開示シェブロンが
                    // 重複表示される (PollRowView 自前の > と二重)。不可視リンクを overlay して
                    // 行全体をタップ可能にしつつ、見た目は自前の > だけにする。
                    PollRowView(poll: poll)
                        .contentShape(Rectangle())
                        .overlay {
                            NavigationLink(value: PollRoute.detail(poll.id)) { EmptyView() }
                                .opacity(0)
                        }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - PollRowView

private struct PollRowView: View {
    let poll: Poll

    var body: some View {
        HStack(spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: DS.sp2) {
                Text(poll.title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)

                HStack(spacing: DS.sp2) {
                    ImasChip(text: poll.targetType == .song ? "曲" : "アイドル")
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
            Image(systemName: "chevron.right")
                .font(.imasScaled( 13, weight: .semibold))
                .foregroundStyle(DS.ink3)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .contentShape(Rectangle())
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
}
