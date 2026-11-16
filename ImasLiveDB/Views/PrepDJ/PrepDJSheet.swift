import os
import SwiftUI

/// シートに渡す公演 (`.sheet(item:)` 用)。
struct PrepDJTarget: Identifiable {
    let id = UUID()
    let showId: String
}

/// 予習 DJ / 復習 DJ。公演 1 つぶんの曲を、本番の流れに並べて続けて流す。
///
/// 並べ方はコア (`prepDjPlan`)。開催前は機械予測の上位を流れに並べ直し、セトリがあれば披露順のまま。
/// ChatGPT とつないでいれば、注文を聞いて組み直し、1 曲ごとに語りを付けられる (`PrepDJRunner.modelPlan`)。
/// 語りはモデルの文なので、事実の行 (コアが作る) と分けて出す。
struct PrepDJSheet: View {
    let showId: String

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var order = ""
    @State private var asking: String?
    @State private var askError: String?
    @State private var askTask: Task<Void, Never>?
    /// いまの頼みの印。やめた頼みの後始末が、次の頼みの表示に触らないようにする。
    @State private var askID: UUID?
    @State private var playFailed = false
    @State private var savedNote: String?

    private var session: ChatGPTPlanSession { .shared }
    private var music: MusicKitService { .shared }

    private enum Phase {
        case loading
        case loaded(PrepDjPlan)
        /// 流れを組めない公演 (予測の対象でない)。
        case unavailable
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ImasPage {
                switch phase {
                case .loading:
                    ImasInlineLoading().frame(maxWidth: .infinity)
                case .unavailable:
                    ImasEmptyState(systemImage: "music.note.list", title: "この公演の流れは組めません",
                                   message: "セトリが無く、予測もできない公演です")
                case .failed(let message):
                    ImasEmptyState(.failed, title: "読み込めませんでした", message: message,
                                   actionTitle: "もう一度") { Task { await load() } }
                case .loaded(let plan):
                    header(plan)
                    djSection(plan)
                    trackSections(plan)
                    if plan.byModel {
                        ImasNote("語りは ChatGPT が書いています。事実と違うことがあります。", systemImage: "exclamationmark.circle")
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
        .task { await load() }
        .task(id: loadedTrackAppleMusicIds) { await music.checkStreamable(loadedTrackAppleMusicIds) }
        .onDisappear { askTask?.cancel() }
        .trackScreen("prep_dj")
    }

    /// 組んだ流れの曲の Apple Music の id (聴き放題で鳴らせるかを調べ直す鍵)。
    private var loadedTrackAppleMusicIds: [String?] {
        if case .loaded(let plan) = phase { return plan.tracks.map(\.appleMusicId) }
        return []
    }

    private var title: String {
        if case .loaded(let plan) = phase { return plan.heading }
        return "予習 DJ"
    }

    // MARK: - 頭

    @ViewBuilder
    private func header(_ plan: PrepDjPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            Text(plan.title).imasText(.cardTitle)
            ImasNote(plan.summary, systemImage: "music.note.list")
            if !plan.note.isEmpty {
                ImasNote(plan.note, systemImage: "exclamationmark.circle")
            }
            ImasButton(title: "流す", systemImage: "play.fill", role: .primary, size: .large, fillsWidth: true) {
                AppAnalytics.tap("prep_dj.play_all")
                play(plan, from: 0)
            }
            if playFailed {
                ImasNote("続けて流すには Apple Music の契約か Spotify の連携が要ります。", systemImage: "music.note")
            }
            let unplayable = unplayableCount(plan)
            if unplayable > 0 {
                ImasNote("Apple Music で聴けない \(unplayable) 曲は飛ばします。", systemImage: "forward.end")
            }
            if let talk = nowTalk(plan) {
                ImasNote(talk, systemImage: "waveform")
            }
            ImasButton(title: "プレイリストに保存", systemImage: "plus.rectangle.on.rectangle", role: .secondary, size: .small) {
                Task { await save(plan) }
            }
            if let savedNote {
                ImasNote(savedNote, systemImage: "checkmark")
            }
        }
    }

    /// いま流れている曲の語り (この流れの曲で、語りがあるときだけ)。
    private func nowTalk(_ plan: PrepDjPlan) -> String? {
        guard music.isPlaying, let id = music.nowPlayingSongId,
              let track = plan.tracks.first(where: { $0.songId == id }), !track.talk.isEmpty else { return nil }
        return track.talk
    }

    // MARK: - ChatGPT

    @ViewBuilder
    private func djSection(_ plan: PrepDjPlan) -> some View {
        ImasSection("DJ に頼む", style: .small) {
            if !session.canUsePlan {
                ImasNote("マイページで ChatGPT とつなぐと、注文どおりに組み直して 1 曲ごとの語りが付きます。",
                         systemImage: "text.magnifyingglass")
            } else if let asking {
                VStack(spacing: DS.Space.gap) {
                    ImasInlineLoading(tint: DS.sys)
                    Text(asking).imasText(.note)
                    ImasButton(title: "やめる", systemImage: "xmark", role: .secondary, size: .small) { cancelAsk() }
                }
                .frame(maxWidth: .infinity)
            } else {
                ImasFormTextField(label: "注文", systemImage: "text.bubble", text: $order, prompt: "無くても頼めます")
                    .onSubmit { ask() }
                    .onChange(of: order) { _, new in
                        // 上限はコアの値。超えたぶんはコアでも切られるので、打てないようにしておく。
                        let limit = Int(prepDjMaxOrderChars())
                        if new.count > limit { order = String(new.prefix(limit)) }
                    }
                ImasChipRow {
                    ForEach(prepDjOrderExamples(), id: \.self) { example in
                        ImasFilterChip(text: example, isSelected: order == example) { order = example }
                    }
                }
                ImasButton(title: plan.byModel ? "組み直してもらう" : "語りを付けてもらう", systemImage: "waveform",
                           role: .secondary, fillsWidth: true) { ask() }
                if let askError {
                    ImasNotice(kind: .error, message: askError)
                }
            }
        }
    }

    // MARK: - 曲

    @ViewBuilder
    private func trackSections(_ plan: PrepDjPlan) -> some View {
        ForEach(Self.groups(plan.tracks), id: \.offset) { group in
            ImasSection(group.label, count: "\(group.tracks.count)曲", style: .small) {
                ImasCardList(group.tracks, id: \.track.songId) { item in
                    Button { play(plan, from: item.index) } label: {
                        ImasSongRow(
                            title: item.track.title,
                            subtitle: item.track.fact.isEmpty ? nil : item.track.fact,
                            artworkURL: item.track.artworkUrl.flatMap(URL.init(string:)),
                            brandHex: BrandColors.hex(for: item.track.brandId),
                            trailing: music.isPlayingFull(songId: item.track.songId) ? .value("再生中")
                                : music.fullPlaySkips(item.track.appleMusicId) ? .value("聴けない") : .none,
                            density: .compact,
                            emphasis: music.fullPlaySkips(item.track.appleMusicId) ? .dimmed : .normal
                        ) {
                            if !item.track.talk.isEmpty {
                                Text(item.track.talk)
                                    .imasText(.note)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .buttonStyle(.imasRow)
                }
            }
        }
    }

    private struct Group {
        let offset: Int
        let label: String
        var tracks: [(index: Int, track: PrepDjTrack)]
    }

    /// 塊の頭の印 (コアの `startsPart`) で切るだけ。
    private static func groups(_ tracks: [PrepDjTrack]) -> [Group] {
        var out: [Group] = []
        for (index, track) in tracks.enumerated() {
            if track.startsPart || out.isEmpty {
                out.append(Group(offset: index, label: track.partLabel, tracks: []))
            }
            out[out.count - 1].tracks.append((index, track))
        }
        return out
    }

    // MARK: - 処理

    private func load() async {
        do {
            phase = try await PrepDJRunner.basePlan(showId: showId).map(Phase.loaded) ?? .unavailable
        } catch {
            Logger.database.error("prep_dj_failed show=\(showId, privacy: .public): \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func ask() {
        guard session.canUsePlan, asking == nil else { return }
        AppAnalytics.tap("prep_dj.ask")
        askError = nil
        asking = "流れを考えています…"
        let note = order
        let id = UUID()
        askID = id
        askTask = Task {
            defer { if askID == id { asking = nil } }
            do {
                let plan = try await PrepDJRunner.modelPlan(showId: showId, order: note) { label in
                    if askID == id { asking = label }
                }
                if Task.isCancelled || askID != id { return }
                savedNote = nil
                phase = .loaded(plan)
            } catch is CancellationError {
                // やめた。
            } catch {
                if Task.isCancelled || askID != id { return }
                Logger.database.error("prep_dj_ask_failed: \(error.localizedDescription)")
                askError = error.localizedDescription
            }
        }
    }

    private func cancelAsk() {
        askTask?.cancel()
        askTask = nil
        askID = nil
        asking = nil
    }

    private func play(_ plan: PrepDjPlan, from index: Int) {
        Task {
            playFailed = !(await music.playFullSongs(plan.tracks.map { (songId: $0.songId, appleMusicId: $0.appleMusicId) },
                                                     startAt: index))
        }
    }

    /// フル尺で鳴らせず飛ばす曲の数 (Apple Music に無い曲と、聴き放題に無い版の曲)。
    /// Spotify は曲名で探すので、鳴らしてみるまで分からない (0)。
    private func unplayableCount(_ plan: PrepDjPlan) -> Int {
        music.fullPlaySkipCount(plan.tracks.map(\.appleMusicId))
    }

    private func save(_ plan: PrepDjPlan) async {
        AppAnalytics.tap("prep_dj.save_playlist")
        do {
            let store = AppContainer.shared.playlists
            let created = try await store.create(name: plan.title)
            try await store.setSongIds(playlistId: created.id, songIds: plan.tracks.map(\.songId))
            savedNote = "プレイリスト「\(plan.title)」に保存しました。"
        } catch {
            savedNote = "保存できませんでした。\(error.localizedDescription)"
        }
    }
}
