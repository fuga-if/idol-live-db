import os
import NukeUI
import SwiftUI

/// 詳細表示用のモーダルシート（アプリ全体で共通利用）
enum DetailDestination: Identifiable, Hashable {
    case song(Song)
    /// 楽曲詳細を「披露履歴」タブで開く (一覧の披露/回収バッジから直接ジャンプ)。
    case songHistory(Song)
    case idol(Idol)
    case event(Event)
    case show(Show)
    case unit(Unit)
    case idolSongHistory(Idol, Song)
    case filteredSongs(SongFilterCriterion)
    case filteredIdols(IdolFilterCriterion)
    case filteredEvents(EventFilterCriterion)
    case filteredShows(ShowFilterCriterion)
    case tagDetail(SongTagEntry)

    var id: String {
        switch self {
        case .song(let s): return "song_\(s.id)"
        case .songHistory(let s): return "songHistory_\(s.id)"
        case .idol(let i): return "idol_\(i.id)"
        case .event(let e): return "event_\(e.id)"
        case .show(let s): return "show_\(s.id)"
        case .unit(let u): return "unit_\(u.id)"
        case .idolSongHistory(let i, let s): return "idolSongHistory_\(i.id)_\(s.id)"
        case .filteredSongs(let c): return "filteredSongs_\(c.navigationTitle)"
        case .filteredIdols(let c): return "filteredIdols_\(c.navigationTitle)"
        case .filteredEvents(let c): return "filteredEvents_\(c.navigationTitle)"
        case .filteredShows(let c): return "filteredShows_\(c.navigationTitle)"
        case .tagDetail(let t): return "tagDetail_\(t.id)"
        }
    }

    // NavigationStack(path:) で push する用の Hashable 実装。
    // 各 case の id (上記) は一意の文字列なので、 id ベースで等価判定 + ハッシュ化する。
    static func == (lhs: DetailDestination, rhs: DetailDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DetailSheetView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let destination: DetailDestination
    /// 詳細画面間の遷移は同一シート内の NavigationStack push で行う。
    /// 旧実装は sheet on sheet で重ねていたため画面が迷路化していた。
    @State private var path: [DetailDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            content(for: destination)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        dismissButton
                    }
                }
                .navigationDestination(for: DetailDestination.self) { dest in
                    content(for: dest)
                }
        }
    }

    @ViewBuilder
    private func content(for dest: DetailDestination) -> some View {
        switch dest {
        case .song(let song):
            SongSheetContent(song: song, navigate: { path.append($0) })
                .onAppear { RecentsService.shared.record(kind: .song, id: song.id, name: song.title) }
        case .songHistory(let song):
            SongSheetContent(song: song, initialSegment: 1, navigate: { path.append($0) })
                .onAppear { RecentsService.shared.record(kind: .song, id: song.id, name: song.title) }
        case .idol(let idol):
            // 共通のアイドル詳細 (一覧と同一コンポーネント)。子遷移は共有 path に push。
            IdolDetailView(idol: idol, navigate: { path.append($0) })
                .onAppear { RecentsService.shared.record(kind: .idol, id: idol.id, name: idol.name) }
        case .event(let event):
            EventDetailView(event: event, navigate: { path.append($0) })
        case .show(let show):
            SetlistView(show: show, navigate: { path.append($0) })
        case .unit(let unit):
            UnitSheetContent(unit: unit, navigate: { path.append($0) })
        case .idolSongHistory(let idol, let song):
            IdolSongHistoryView(idol: idol, song: song, navigate: { path.append($0) })
        case .filteredSongs(let criterion):
            FilteredSongsView(criterion: criterion, navigate: { path.append($0) })
        case .filteredIdols(let criterion):
            FilteredIdolsView(criterion: criterion, navigate: { path.append($0) })
        case .filteredEvents(let criterion):
            FilteredEventsView(criterion: criterion, navigate: { path.append($0) })
        case .filteredShows(let criterion):
            FilteredShowsView(criterion: criterion, navigate: { path.append($0) })
        case .tagDetail(let tag):
            TagDetailView(tagId: tag.id, tagName: tag.name)
        }
    }

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Song Sheet Content

struct SongSheetContent: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    let song: Song
    let navigate: (DetailDestination) -> Void

    /// 開く時の初期セグメント (0=情報・歌唱 / 1=披露履歴 / 2=コミュニティ)。
    init(song: Song, initialSegment: Int = 0, navigate: @escaping (DetailDestination) -> Void) {
        self.song = song
        self.navigate = navigate
        _segment = State(initialValue: initialSegment)
    }

    @State private var history: [PerformanceHistoryRow] = []
    @State private var originalArtists: [Idol] = []
    @State private var performerArtists: [Idol] = []
    @State private var artworkInfo: MusicKitSongInfo?
    @State private var editSong: Song?
    @State private var showLoginPrompt = false
    @State private var brand: Brand?
    @State private var songCalls: [SongCall] = []
    @State private var songVideos: [SongVideo] = []
    @State private var collectedShows: [ShowWithEventName] = []
    @State private var penlightVotes: PenlightVoteResult?
    @State private var showPenlightVoteSheet = false
    @State private var songTagData: SongTagListResponse?
    @State private var showTagPicker = false
    /// 関連楽曲 (同シリーズ/同ユニット/歌唱共有, ローカル算出)。
    @State private var relatedSongs: [Song] = []
    /// タグが似ている楽曲 (この曲が好きな人にはこれもおすすめ, サーバ算出)。
    @State private var similarTagSongs: [Song] = []
    /// similarTagSongs の song.id → 共有タグ数。
    @State private var similarSharedTags: [String: Int] = [:]
    // コーレス (SongCall) / 参考動画 (SongVideo) オープン編集 (確定契約 §4)。
    /// コーレス投稿/編集シート。nil=非表示, .create=新規, .edit(call)=編集。
    @State private var callSheet: SongCommunityEditTarget<SongCall>?
    /// 参考動画投稿/編集シート。
    @State private var videoSheet: SongCommunityEditTarget<SongVideo>?
    /// 未ログインで投稿導線を押した時のログイン誘導。
    @State private var showCommunityLoginPrompt = false

    @State private var segment = 0
    /// お気に入りトグル後に依存ビューを再評価させるためのバージョン。
    @State private var markVersion = 0

    private var markService: UserMarkService { UserMarkService.shared }

    /// 配色シード。ソロ曲 (オリジナル歌唱が1人) はそのアイドル個人カラーを使い、
    /// それ以外 (ユニット/全体曲やカラー未設定) はブランド色にフォールバックする。
    private var songSeed: String? {
        if originalArtists.count == 1, let color = originalArtists.first?.color, !color.isEmpty {
            return color
        }
        return brand?.color
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                segmentBar
                    .padding(.horizontal, DS.sp5)
                    .padding(.top, DS.sp4)
                    .padding(.bottom, DS.sp1)

                switch segment {
                case 0: infoTab
                case 1: historyTab
                default: communityTab
                }

                Color.clear.frame(height: DS.sp9)
            }
        }
        .background(DS.bg)
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if EditPermission.showEditAffordance {
                        Button {
                            if EditPermission.canEdit {
                                editSong = song
                            } else {
                                showLoginPrompt = true
                            }
                        } label: {
                            Label("この楽曲を編集", systemImage: "pencil")
                        }
                    }
                    NavigationLink {
                        EditHistoryView(recordType: "Song", recordName: song.id, title: song.title)
                    } label: {
                        Label("編集履歴", systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
                    Button { openURL(lyricsURL) } label: {
                        Label("歌詞を見る", systemImage: "text.quote")
                    }
                    if let appleMusicURL = artworkInfo?.appleMusicURL {
                        Button { openURL(appleMusicURL) } label: {
                            Label("Apple Musicで開く", systemImage: "music.note")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editSong) { s in
            SongEditView(song: s).environment(database)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { editSong = song } })
        }
        .sheet(isPresented: $showPenlightVoteSheet) {
            PenlightVoteSheet(songId: song.id) {
                Task { await loadPenlightVotes() }
            }
        }
        .sheet(isPresented: $showTagPicker) {
            SongTagPicker(songId: song.id, song: SongWithArtists(song: song, artistNames: song.singerLabel ?? "", performerIdols: originalArtists)) {
                Task { await loadSongTags() }
            }
        }
        .sheet(item: $callSheet) { target in
            callEditSheet(for: target)
        }
        .sheet(item: $videoSheet) { target in
            videoEditSheet(for: target)
        }
        .sheet(isPresented: $showCommunityLoginPrompt) {
            LoginToEditSheet()
        }
        .task { await loadData() }
        .trackScreen("song_detail")
    }

    // MARK: - Hero (大ジャケ + 曲名 + アーティスト + 主要アクション)

    @ViewBuilder
    private var hero: some View {
        let t = ImasTheme.derive(seed: songSeed, scheme: scheme)
        VStack(spacing: DS.sp4) {
            ArtworkImageView(
                url: artworkInfo?.artworkURL,
                size: 168,
                previewURL: artworkInfo?.previewURL,
                songTitle: song.title,
                seed: songSeed
            )

            VStack(spacing: DS.sp1) {
                Text(song.title)
                    .font(.imasTitle2)
                    .foregroundStyle(DS.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let artistLine {
                    Text(artistLine)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, DS.sp5)

            HStack(spacing: DS.sp3) {
                playAction(t)
                favoriteAction(t)
            }
            .padding(.horizontal, DS.sp5)
        }
        .padding(.top, DS.sp4)
        .padding(.bottom, DS.sp5)
        .frame(maxWidth: .infinity)
        .background(t.heroSurface)
    }

    /// アーティスト = 歌唱アイドル名連結 (なければ singerLabel / unitName)。
    private var artistLine: String? {
        if !originalArtists.isEmpty {
            return originalArtists.map(\.name).joined(separator: " / ")
        }
        return song.singerLabel ?? song.unitName
    }

    private var isPreviewing: Bool {
        MusicKitService.shared.isPlaying && MusicKitService.shared.nowPlayingTitle == song.title
    }

    @ViewBuilder
    private func playAction(_ t: ImasTheme) -> some View {
        Button {
            AppAnalytics.tap("song_detail.play")
            if let info = artworkInfo, info.musicKitId != nil {
                Task { await playFull(info) }
            } else if let previewURL = artworkInfo?.previewURL {
                MusicKitService.shared.togglePreview(url: previewURL, title: song.title)
            }
        } label: {
            Label(isPreviewing ? "停止" : "再生", systemImage: isPreviewing ? "stop.fill" : "play.fill")
                .font(.imasSubhead.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(t.onAccent)
                .background(t.accent, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(artworkInfo?.previewURL == nil && artworkInfo?.musicKitId == nil)
        .opacity((artworkInfo?.previewURL == nil && artworkInfo?.musicKitId == nil) ? 0.5 : 1)
    }

    private func playFull(_ info: MusicKitSongInfo) async {
        if MusicKitService.shared.isPlaying
            && MusicKitService.shared.isFullPlayback
            && MusicKitService.shared.nowPlayingTitle == song.title {
            MusicKitService.shared.stop()
            return
        }
        if !MusicKitService.shared.hasAppleMusicSubscription {
            await MusicKitService.shared.requestAuthorization()
            guard MusicKitService.shared.hasAppleMusicSubscription else {
                // サブスク無しは fallback でプレビュー再生。
                if let previewURL = info.previewURL {
                    MusicKitService.shared.togglePreview(url: previewURL, title: song.title)
                }
                return
            }
        }
        await MusicKitService.shared.playFull(songInfo: info, title: song.title)
    }

    @ViewBuilder
    private func favoriteAction(_ t: ImasTheme) -> some View {
        let isFav = markService.bool(.favorite, entity: .song, id: song.id)
        Button {
            AppAnalytics.tap("song_detail.toggle_favorite")
            toggleFavorite()
        } label: {
            Label(isFav ? "お気に入り済み" : "お気に入り", systemImage: isFav ? "star.fill" : "star")
                .font(.imasSubhead.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(isFav ? DS.favorite : t.accent)
                .background(t.chipBg, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(markVersion) // toggle 後に再評価
    }

    private func toggleFavorite() {
        do {
            try markService.toggle(.favorite, entity: .song, id: song.id)
            markVersion += 1
            let value = markService.bool(.favorite, entity: .song, id: song.id)
            Task { try? await CommunityAPI.shared.toggleFavorite(songId: song.id, value: value) }
        } catch {
            Logger.database.error("toggle_favorite_failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Segmented

    private var segmentBar: some View {
        ImasSegmented(
            labels: ["情報・歌唱", "披露履歴", "コミュニティ"],
            selection: $segment,
            seed: songSeed
        )
    }

    // MARK: - Tab 0: 情報・歌唱

    @ViewBuilder
    private var infoTab: some View {
        VStack(spacing: DS.sp5) {
            performanceStats
            songInfoSection
            if !originalArtists.isEmpty { singersSection }
            if !performerArtists.isEmpty { performerSection }
            if !relatedSongs.isEmpty { relatedSongsSection }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    /// 関連楽曲: 同じシリーズ・ユニット・歌唱アイドルでつながる曲 (ローカル算出)。
    private var relatedSongsSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "関連楽曲", count: "\(relatedSongs.count)")
            ImasListContainer {
                ForEach(Array(relatedSongs.enumerated()), id: \.element.id) { idx, s in
                    if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5 + 44) }
                    Button { navigate(.song(s)) } label: { relatedSongRow(s, badge: nil) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// 関連/おすすめ楽曲の共通行。badge に共有タグ数などの補足を出せる。
    private func relatedSongRow(_ s: Song, badge: String?) -> some View {
        HStack(spacing: DS.sp3) {
            ImasArtwork(title: s.title, seed: songSeed, size: 44,
                        imageURL: URL.safeHTTP(string: s.artworkUrl))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink).lineLimit(1)
                if let sub = s.singerLabel ?? s.unitName, !sub.isEmpty {
                    Text(sub).font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let badge {
                Text(badge).font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
            }
            Image(systemName: "chevron.right").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink3)
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var performanceStats: some View {
        let total = history.count
        let collected = collectedShows.count
        return VStack(spacing: DS.sp4) {
            HStack(spacing: DS.sp3) {
                ImasStatTile(systemImage: "mic.fill", value: "\(total)", unit: "回", label: "披露回数", seed: songSeed)
                ImasStatTile(systemImage: "checkmark.seal.fill", value: "\(collected)", unit: "公演", label: "現地回収", seed: songSeed)
            }
            Button {
                AppAnalytics.tap("song_detail.register_attendance")
                showAttendPicker()
            } label: {
                Label("参加ライブを登録して現地回収", systemImage: "plus")
                    .font(.imasSubhead.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(DS.ink2)
                    .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
            .buttonStyle(.plain)

            if !collectedShows.isEmpty {
                ImasListContainer {
                    ForEach(Array(collectedShows.enumerated()), id: \.element.id) { idx, show in
                        if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        Button { navigate(.show(show.asShow)) } label: {
                            collectedRow(show)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func collectedRow(_ show: ShowWithEventName) -> some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.imasScaled( 15, weight: .semibold))
                .foregroundStyle(DS.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(eventDisplayName(show.eventName)).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Text([show.name, show.date].joined(separator: " ・ "))
                    .font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.ink3)
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// 参加ライブ登録は披露履歴の公演を選んで現地回収マークする導線。
    /// 現状は履歴タブへ誘導 (個別公演で参加登録) する。
    private func showAttendPicker() {
        segment = 1
    }

    @ViewBuilder
    private var songInfoSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "楽曲情報", tight: true)
            ImasListContainer {
                infoRows
            }
        }
    }

    @ViewBuilder
    private var infoRows: some View {
        let rows = buildInfoRows()
        ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
            if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
            row.view
        }
    }

    private struct InfoRowItem: Identifiable { let id = UUID(); let view: AnyView }

    private func buildInfoRows() -> [InfoRowItem] {
        var items: [InfoRowItem] = []
        func add<V: View>(_ v: V) { items.append(InfoRowItem(view: AnyView(v))) }

        if let artistLine {
            add(ImasLabeledRow(key: "アーティスト", value: artistLine, seed: songSeed))
        }
        if let brand {
            add(Button { navigate(.filteredSongs(.brand(id: brand.id, label: brand.shortName))) } label: {
                ImasLabeledRow(key: "ブランド", value: brand.shortName, showChevron: true, tappable: true, seed: songSeed)
            }.buttonStyle(.plain))
        }
        if !song.songType.isEmpty, song.songType != "unknown" {
            add(Button { navigate(.filteredSongs(.songType(song.songType))) } label: {
                ImasLabeledRow(key: "タイプ", value: song.songTypeLabel, showChevron: true, tappable: true, seed: songSeed)
            }.buttonStyle(.plain))
        }
        if let composer = song.composer {
            add(creditRow(key: composer == song.arranger ? "作曲 / 編曲" : "作曲", credit: composer))
        }
        if let arranger = song.arranger, arranger != song.composer {
            add(creditRow(key: "編曲", credit: arranger))
        }
        if let lyricist = song.lyricist {
            add(creditRow(key: "作詞", credit: lyricist))
        }
        if let cdSeries = song.cdSeries {
            add(Button { navigate(.filteredSongs(.cdSeries(cdSeries))) } label: {
                ImasLabeledRow(key: "CDシリーズ", value: cdSeries, showChevron: true, tappable: true, seed: songSeed)
            }.buttonStyle(.plain))
        }
        if let date = song.releaseDate {
            let year = String(date.prefix(4))
            if year.count == 4, Int(year) != nil {
                add(Button { navigate(.filteredSongs(.releaseYear(year))) } label: {
                    ImasLabeledRow(key: "リリース日", value: date, showChevron: true, tappable: true, seed: songSeed)
                }.buttonStyle(.plain))
            } else {
                add(ImasLabeledRow(key: "リリース日", value: date, seed: songSeed))
            }
        }
        if let dur = durationValue {
            add(ImasLabeledRow(key: "再生時間", value: dur, mono: true, seed: songSeed))
        }
        if let unitId = song.unitId, let unitName = song.unitName {
            add(Button {
                Task { if let unit = try? await AppContainer.shared.unitReading.unit(id: unitId) { navigate(.unit(unit)) } }
            } label: {
                ImasLabeledRow(key: "ユニット", value: unitName, showChevron: true, tappable: true, seed: songSeed)
            }.buttonStyle(.plain))
        }
        return items
    }

    /// クレジット行: 区切り文字で複数名に分割し、各名をクリエイター絞り込みへタップ可能にする。
    @ViewBuilder
    private func creditRow(key: String, credit: String) -> some View {
        let names = splitCredits(credit)
        HStack(spacing: 12) {
            Text(key).font(.imasSubhead).foregroundStyle(DS.ink2)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    if idx > 0 { Text("/").font(.imasSubhead).foregroundStyle(DS.ink3) }
                    Button { navigate(.filteredSongs(.creator(name))) } label: {
                        Text(name).font(.imasSubhead).foregroundStyle(ImasTheme.derive(seed: songSeed, scheme: scheme).accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(DS.surface)
    }

    private func splitCredits(_ s: String) -> [String] {
        let separators = CharacterSet(charactersIn: "/／,、・")
        return s.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var durationValue: String? {
        guard let sec = song.durationSec, sec > 0 else { return nil }
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    private var singersSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "歌唱アイドル", count: "\(originalArtists.count)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: DS.sp3)], spacing: DS.sp4) {
                ForEach(originalArtists) { idol in
                    Button { navigate(.idol(idol)) } label: {
                        VStack(spacing: 6) {
                            IdolAvatarView(idol: idol, size: 52)
                            Text(idol.name)
                                .font(.imasCaption.weight(.medium))
                                .foregroundStyle(DS.ink2)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var performerSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "ライブ歌唱歴", count: "\(performerArtists.count)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: DS.sp3)], spacing: DS.sp4) {
                ForEach(performerArtists) { idol in
                    Button { navigate(.idol(idol)) } label: {
                        VStack(spacing: 6) {
                            IdolAvatarView(idol: idol, size: 52)
                            Text(idol.name)
                                .font(.imasCaption.weight(.medium))
                                .foregroundStyle(DS.ink2)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tab 1: 披露履歴

    @ViewBuilder
    private var historyTab: some View {
        VStack(spacing: DS.sp5) {
            if history.isEmpty {
                ImasEmptyState(
                    systemImage: "mic",
                    title: "披露履歴はまだありません",
                    message: "この曲がライブで披露されると、ここに記録されます。",
                    seed: songSeed
                )
            } else {
                if let first = history.last?.date, let last = history.first?.date {
                    HStack(spacing: DS.sp3) {
                        ImasStatTile(systemImage: "mic.fill", value: "\(history.count)", unit: "回", label: "総披露", seed: songSeed)
                        ImasStatTile(systemImage: "calendar", value: shortDate(first), label: "初披露", seed: songSeed)
                        ImasStatTile(systemImage: "calendar.badge.clock", value: shortDate(last), label: "最終披露", seed: songSeed)
                    }
                }
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "ライブ披露履歴", count: "\(history.count)回", tight: true)
                    ImasListContainer {
                        ForEach(Array(history.enumerated()), id: \.offset) { idx, row in
                            if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp4) }
                            historyRow(row)
                        }
                    }
                }
            }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    private func historyRow(_ row: PerformanceHistoryRow) -> some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    navigate(.show(show))
                }
            }
        } label: {
            HStack(spacing: 0) {
                ImasLeadBar(seed: songSeed)
                    .frame(height: 34)
                    .padding(.trailing, DS.sp4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventDisplayName(row.eventName)).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                    Text([row.showName, row.date].joined(separator: " ・ "))
                        .font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.imasScaled( 13, weight: .semibold)).foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortDate(_ date: String) -> String {
        // "2024-08-03" → "24.08"
        let comps = date.split(separator: "-")
        if comps.count >= 2 {
            return "\(comps[0].suffix(2)).\(comps[1])"
        }
        return date
    }

    // MARK: - Tab 2: コミュニティ

    @ViewBuilder
    private var communityTab: some View {
        VStack(spacing: DS.sp5) {
            PollAchievementBadges(entityId: song.id)
            InlineLoginPrompt(message: "タグ・コーレス・投票にはログインが必要です", seed: songSeed)
            communityTags
            if !similarTagSongs.isEmpty { similarByTagsSection }
            communityCalls
            communityVideos
            communityPenlight
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    /// この曲が好きな人にはこれもおすすめ — タグが似ている楽曲 (サーバ算出)。
    private var similarByTagsSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("この曲が好きな人にはこれも")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("つけられたタグが似ている楽曲")
                    .font(.imasCaption).foregroundStyle(DS.ink2)
            }
            ImasListContainer {
                ForEach(Array(similarTagSongs.enumerated()), id: \.element.id) { idx, s in
                    if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5 + 44) }
                    Button { navigate(.song(s)) } label: {
                        relatedSongRow(s, badge: similarSharedTags[s.id].map { "タグ\($0)個一致" })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var communityTags: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            communityHeader(title: "タグ", actionLabel: "タグ", systemImage: "plus") {
                AppAnalytics.tap("song_detail.tag_action")
                startCommunityEdit { showTagPicker = true }
            }
            if let tagData = songTagData, !tagData.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tagData.tags) { tag in
                        let isMine = Set(tagData.myTagIds).contains(tag.id)
                        Button { navigate(.tagDetail(tag)) } label: {
                            // 何人がこのタグを付けたか (票数) を常に表示。
                            ImasChip(text: "\(tag.name) \(tag.voteCount)",
                                     style: isMine ? .selected : .themed,
                                     seed: songSeed)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if isMine {
                                Button(role: .destructive) {
                                    Task {
                                        try? await CommunityAPI.shared.removeSongTag(songId: song.id, tagId: tag.id)
                                        await loadSongTags()
                                    }
                                } label: { Label("タグを外す", systemImage: "tag.slash") }
                            }
                            Button { navigate(.tagDetail(tag)) } label: { Label("タグ詳細を見る", systemImage: "tag") }
                        }
                    }
                }
            } else {
                ImasEmptyState(systemImage: "tag", title: "タグはまだありません",
                               message: "この曲を一言で表すタグを付けてみませんか？",
                               actionTitle: EditPermission.showEditAffordance ? "タグを追加" : nil,
                               action: EditPermission.showEditAffordance ? { startCommunityEdit { showTagPicker = true } } : nil,
                               seed: songSeed)
            }
        }
    }

    @ViewBuilder
    private var communityCalls: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            communityHeader(title: "コーレス", actionLabel: "コール", systemImage: "megaphone") {
                AppAnalytics.tap("song_detail.call_action")
                startCommunityEdit { callSheet = .create }
            }
            if songCalls.isEmpty {
                ImasEmptyState(systemImage: "megaphone", title: "コーレスはまだありません",
                               message: "サビ前のコールなど、現地の盛り上げ方を共有しませんか？",
                               actionTitle: EditPermission.showEditAffordance ? "コーレスを投稿" : nil,
                               action: EditPermission.showEditAffordance ? { startCommunityEdit { callSheet = .create } } : nil,
                               seed: songSeed)
            } else {
                ImasListContainer {
                    ForEach(Array(songCalls.enumerated()), id: \.element.id) { idx, call in
                        if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        callRow(call)
                    }
                }
            }
        }
    }

    private func callRow(_ call: SongCall) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(call.callText)
                .font(.imasSubhead).foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.sp3) {
                if let link = URL.safeHTTP(string: call.sourceUrl) {
                    Link(destination: link) {
                        Label("出典", systemImage: "link").font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                }
                if let author = call.authorDisplayName {
                    Text("投稿者: \(author)").font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 4)
                if EditPermission.showEditAffordance {
                    Button { startCommunityEdit { callSheet = .edit(call) } } label: {
                        Image(systemName: "pencil").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
    }

    @ViewBuilder
    private var communityVideos: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            communityHeader(title: "参考動画", actionLabel: "動画", systemImage: "play.fill") {
                AppAnalytics.tap("song_detail.video_action")
                startCommunityEdit { videoSheet = .create }
            }
            if songVideos.isEmpty {
                ImasEmptyState(systemImage: "play.rectangle", title: "参考動画はまだありません",
                               message: "最初の1本を投稿しませんか？",
                               actionTitle: EditPermission.showEditAffordance ? "動画を投稿" : nil,
                               action: EditPermission.showEditAffordance ? { startCommunityEdit { videoSheet = .create } } : nil,
                               seed: songSeed)
            } else {
                ImasListContainer {
                    ForEach(Array(songVideos.enumerated()), id: \.element.id) { idx, video in
                        if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        videoRow(video)
                    }
                }
            }
        }
    }

    private func videoRow(_ video: SongVideo) -> some View {
        let videoID = YouTube.videoID(from: video.youtubeUrl)
        return VStack(alignment: .leading, spacing: 8) {
            if let videoID, let url = URL.safeHTTP(string: video.youtubeUrl) {
                // 公式 MV は埋め込み無効が多くアプリ内再生不可 (YouTube仕様) のため、
                // サムネタップで YouTube アプリ/Safari を開く。
                Button { openURL(url) } label: {
                    ZStack {
                        LazyImage(url: YouTube.thumbnailURL(for: videoID)) { state in
                            if let image = state.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else if state.error != nil {
                                // maxresdefault が無い動画は mqdefault にフォールバック。
                                LazyImage(url: YouTube.fallbackThumbnailURL(for: videoID)) { fb in
                                    if let image = fb.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(DS.surface2)
                                    }
                                }
                            } else {
                                Rectangle().fill(DS.surface2)
                            }
                        }
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
                        Image(systemName: "play.circle.fill")
                            .font(.imasScaled( 46))
                            .foregroundStyle(.white.opacity(0.94))
                            .shadow(color: .black.opacity(0.35), radius: 5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let title = video.videoTitle {
                Text(title).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
            }
            if videoID == nil, let url = URL.safeHTTP(string: video.youtubeUrl) {
                // YouTube 以外 (または ID 解析不可) は従来どおり外部リンク。
                Link(destination: url) {
                    Label(video.youtubeUrl, systemImage: "play.rectangle.fill")
                        .font(.imasCaption).foregroundStyle(DS.danger)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if let note = video.note, !note.isEmpty {
                Text(note).font(.imasCaption).foregroundStyle(DS.ink2)
            }
            HStack(spacing: DS.sp3) {
                if let author = video.authorDisplayName {
                    Text("投稿者: \(author)").font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 4)
                if EditPermission.showEditAffordance {
                    Button { startCommunityEdit { videoSheet = .edit(video) } } label: {
                        Image(systemName: "pencil").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
    }

    @ViewBuilder
    private var communityPenlight: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            communityHeader(title: "ペンライト投票", actionLabel: "投票する", systemImage: "sparkles") {
                AppAnalytics.tap("song_detail.penlight_action")
                startCommunityEdit { showPenlightVoteSheet = true }
            }
            if let votes = penlightVotes, !votes.topColorSets.isEmpty {
                ImasListContainer {
                    ForEach(Array(votes.topColorSets.enumerated()), id: \.element.id) { idx, set in
                        if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        penlightRow(set, myKey: votes.myColorSet?.key, total: max(votes.totalVotes, 1))
                    }
                }
                Text("この曲のペンライト色 ・ \(votes.totalVotes)票")
                    .font(.imasCaption).foregroundStyle(DS.ink2)
                    .padding(.leading, DS.sp1)
            } else {
                ImasEmptyState(systemImage: "lightspectrum.horizontal", title: "まだ投票がありません",
                               message: "あなたが思うこの曲のペンライト色を投票しませんか？",
                               actionTitle: EditPermission.showEditAffordance ? "ペンライト色を投票" : nil,
                               action: EditPermission.showEditAffordance ? { startCommunityEdit { showPenlightVoteSheet = true } } : nil,
                               seed: songSeed)
            }
        }
    }

    private func penlightRow(_ set: PenlightColorSet, myKey: String?, total: Int) -> some View {
        let isMine = myKey == set.key
        return VStack(spacing: 7) {
            HStack(spacing: DS.sp3) {
                PenlightColorBar(colors: set.colors.map(\.rawValue), height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
                    .frame(maxWidth: 120)
                if isMine {
                    Text("自分の投票").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.pick)
                }
                Spacer(minLength: 4)
                Text("\(set.count)票").font(.imasDisplay(13, weight: .semibold)).foregroundStyle(DS.ink2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(DS.pick.opacity(0.7))
                        .frame(width: max(4, geo.size.width * CGFloat(set.count) / CGFloat(total)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 10)
    }

    /// セクション見出し + 文脈投稿導線 (＋タグ / ＋コール / ▶動画 / ✦投票)。
    @ViewBuilder
    private func communityHeader(title: String, actionLabel: String, systemImage: String, action: @escaping () -> Void) -> some View {
        let t = ImasTheme.derive(seed: songSeed, scheme: scheme)
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
            Spacer(minLength: 12)
            if EditPermission.showEditAffordance {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: systemImage).font(.imasScaled( 13, weight: .semibold))
                        Text(actionLabel).font(.imasScaled( 14, weight: .semibold))
                    }
                    .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Community edit (コーレス / 参考動画) sheets

    @ViewBuilder
    private func callEditSheet(for target: SongCommunityEditTarget<SongCall>) -> some View {
        Group {
            if let call = target.editing {
                CallEditView(call: call) { Task { await loadCommunityContent() } }
            } else {
                CallEditView(songId: song.id) { Task { await loadCommunityContent() } }
            }
        }
        .environment(database)
    }

    @ViewBuilder
    private func videoEditSheet(for target: SongCommunityEditTarget<SongVideo>) -> some View {
        Group {
            if let video = target.editing {
                VideoEditView(video: video) { Task { await loadCommunityContent() } }
            } else {
                VideoEditView(songId: song.id) { Task { await loadCommunityContent() } }
            }
        }
        .environment(database)
    }

    /// 投稿/編集導線の共通ゲート: 未ログインはログイン誘導、BAN 済みは何もしない、
    /// ログイン済み・未 BAN のみ `present` を実行する (EditPermission に集約)。
    private func startCommunityEdit(_ present: () -> Void) {
        if EditPermission.canEdit {
            present()
        } else if EditPermission.shouldPromptLogin {
            showCommunityLoginPrompt = true
        }
        // BAN 済みは導線自体を出さない (showEditAffordance=false) ので no-op。
    }

    /// コーレス / 参考動画をローカル DB から再読込する (投稿/編集成功後の反映)。
    private func loadCommunityContent() async {
        do {
            songCalls = try await AppContainer.shared.songReading.songCalls(songId: song.id)
            songVideos = try await AppContainer.shared.songReading.songVideos(songId: song.id)
        } catch {
            Logger.database.error("load_failed song_community: \(error.localizedDescription)")
        }
    }

    private var lyricsURL: URL {
        if let url = URL.safeHTTP(string: song.lyricsUrl) {
            return url
        }
        let encoded = song.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.uta-net.com/search/?Keyword=\(encoded)") ?? URL(string: "https://www.uta-net.com")!
    }

    private func loadData() async {
        do {
            let songReading = AppContainer.shared.songReading
            history = try await songReading.songPerformanceHistory(songId: song.id)
            originalArtists = try await songReading.songArtists(songId: song.id, role: "original")
            performerArtists = try await songReading.songArtists(songId: song.id, role: "performer")
            if let brandId = song.brandId {
                let brands = try await AppContainer.shared.brandReading.brands()
                brand = brands.first { $0.id == brandId }
            }
            songCalls = try await AppContainer.shared.songReading.songCalls(songId: song.id)
            songVideos = try await AppContainer.shared.songReading.songVideos(songId: song.id)
            collectedShows = try await songReading.collectedShows(for: song.id)
            relatedSongs = try await songReading.relatedSongs(to: song, limit: 8)
        } catch {
            Logger.database.error("load_failed song_details: \(error.localizedDescription)")
        }
        artworkInfo = await MusicKitService.shared.fetchSongInfo(title: song.title, appleMusicId: song.appleMusicId)
        await loadPenlightVotes()
        await loadSongTags()
        await loadSimilarSongs()
    }

    /// タグ類似のおすすめ楽曲をサーバから取得し、ローカル DB で Song に解決する。
    /// 返却順 (共有タグ数の降順) を維持する。
    private func loadSimilarSongs() async {
        guard let response = try? await CommunityAPI.shared.similarSongsByTags(songId: song.id) else { return }
        let ids = response.songs.map(\.songId)
        guard !ids.isEmpty,
              let resolved = try? await AppContainer.shared.songReading.songs(criterion: .songIds(ids, title: "")) else { return }
        let byId = Dictionary(resolved.map { ($0.song.id, $0.song) }) { a, _ in a }
        similarSharedTags = Dictionary(response.songs.map { ($0.songId, $0.sharedTags) }) { a, _ in a }
        similarTagSongs = ids.compactMap { byId[$0] }
    }

    private func loadPenlightVotes() async {
        penlightVotes = try? await CommunityAPI.shared.penlightVotes(songId: song.id)
    }

    private func loadSongTags() async {
        songTagData = try? await CommunityAPI.shared.songTags(songId: song.id)
    }
}
/// 旧 IdolRowLabel 互換 (新規実装は IdolNameRow を直接使うこと)。
private typealias IdolRowLabel = IdolNameRow

// MARK: - Unit Sheet Content

struct UnitSheetContent: View {
    @Environment(AppDatabase.self) private var database
    let unit: Unit
    let navigate: (DetailDestination) -> Void

    @State private var members: [Idol] = []
    @State private var songs: [Song] = []

    var body: some View {
        List {
            if !members.isEmpty {
                Section("メンバー") {
                    ForEach(members) { idol in
                        Button { navigate(.idol(idol)) } label: {
                            IdolRowLabel(idol: idol)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !songs.isEmpty {
                Section("楽曲（\(songs.count)曲）") {
                    ForEach(songs) { song in
                        Button { navigate(.song(song)) } label: {
                            SongTitleRow(song: song)
                        }
                    }
                }
            }
        }
        .navigationTitle(unit.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let unitReading = AppContainer.shared.unitReading
                members = try await unitReading.unitMembers(unitId: unit.id)
                songs = try await unitReading.unitSongs(unitId: unit.id)
            } catch {
                Logger.database.error("load_failed unit: \(error.localizedDescription)")
            }
        }
        .trackScreen("unit_detail")
    }
}

// MARK: - タップ可能な履歴行コンポーネント

struct ShowHistoryButton: View {
    @Environment(AppDatabase.self) private var database
    let showId: String
    let eventName: String
    let showName: String
    let date: String
    let navigate: (DetailDestination) -> Void

    var body: some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: showId) {
                    navigate(.show(show))
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eventDisplayName(eventName))
                        .font(.imasSubhead)
                        .foregroundStyle(.primary)
                    HStack {
                        Text(showName)
                            .font(.imasCaption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(date)
                            .font(.imasCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.imasCaption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}


// MARK: - Tappable Value Row

/// 値全体をタップして遷移する汎用行（LabeledContent のスタイルを維持）

// MARK: - Credits Row

/// 作曲者・作詞者・編曲者を分割してタップ可能に表示する行
