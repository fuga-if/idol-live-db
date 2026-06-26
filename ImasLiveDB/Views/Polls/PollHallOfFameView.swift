import SwiftUI

/// 殿堂 — 終了したお題の優勝者 (曲/アイドル) を一覧する。
/// 「みんなの投票」で盛り上がった結果を振り返るための画面。各行から曲/アイドル詳細へ遷移できる。
struct PollHallOfFameView: View {
    @Environment(AppDatabase.self) private var database

    @State private var vm = PollHallOfFameViewModel(voting: AppContainer.shared.communityVoting)
    @State private var destination: DetailDestination?

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError = vm.loadError {
                ImasEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "読み込みに失敗しました",
                    message: loadError
                )
            } else if vm.results.isEmpty {
                ImasEmptyState(
                    systemImage: "crown",
                    title: "まだ優勝者がいません",
                    message: "お題が終了すると、ここに優勝した曲やアイドルが並びます。"
                )
            } else {
                List {
                    ImasListContainer {
                        ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, result in
                            if index > 0 {
                                Divider().background(DS.sep).padding(.leading, DS.sp5)
                            }
                            Button {
                                AppAnalytics.tap("poll_hall_of_fame.view_result")
                                Task { await navigate(result) }
                            } label: {
                                HallOfFameRow(result: result)
                            }
                            .buttonStyle(.plain)
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
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("殿堂")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $destination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .trackScreen("poll_hall_of_fame")
    }

    private func navigate(_ result: PollResult) async {
        if result.targetType == .song {
            if let song = try? await AppContainer.shared.songReading.song(id: result.entityId) {
                destination = .song(song)
            }
        } else {
            if let idol = try? await AppContainer.shared.idolReading.idol(id: result.entityId) {
                destination = .idol(idol)
            }
        }
    }
}

// MARK: - HallOfFameRow

private struct HallOfFameRow: View {
    let result: PollResult

    @State private var resolvedSong: Song?
    @State private var resolvedIdol: Idol?

    var body: some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "crown.fill")
                .font(.imasScaled(16))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .yellow],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 30, alignment: .center)

            VStack(alignment: .leading, spacing: DS.sp2) {
                Text(result.title)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
                    .lineLimit(1)
                entityView
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: DS.sp2) {
                Text("優勝")
                    .font(.imasCaption.weight(.bold))
                    .foregroundStyle(.orange)
                Text("\(result.voteCount)票")
                    .font(.imasCaption.monospacedDigit())
                    .foregroundStyle(DS.ink3)
            }
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .contentShape(Rectangle())
        .task { await resolveEntity() }
    }

    @ViewBuilder
    private var entityView: some View {
        if result.targetType == .song {
            if let song = resolvedSong {
                SongTitleRow(song: song, showsChevron: false)
            } else {
                fallbackName
            }
        } else {
            if let idol = resolvedIdol {
                IdolNameRow(idol: idol, showsChevron: false)
            } else {
                fallbackName
            }
        }
    }

    private var fallbackName: some View {
        Text(result.entityId)
            .font(.imasSubhead.weight(.semibold))
            .foregroundStyle(DS.ink)
            .lineLimit(1)
    }

    private func resolveEntity() async {
        if result.targetType == .song {
            resolvedSong = try? await AppContainer.shared.songReading.song(id: result.entityId)
        } else {
            resolvedIdol = try? await AppContainer.shared.idolReading.idol(id: result.entityId)
        }
    }
}
