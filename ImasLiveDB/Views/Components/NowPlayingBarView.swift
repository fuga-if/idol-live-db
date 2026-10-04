import SwiftUI

/// 再生中バーの状態を持つ唯一の場所。
///
/// バーの差し込み口は 5 タブぶんある (`safeAreaInset` は TabView 自体に付けられない)
/// が、**読み込みまで 5 つに増やす理由は無い**。View ごとに `.task` を持たせると、
/// 曲を 1 回再生するだけで同じ曲を 5 回引くことになる。
@MainActor @Observable
final class NowPlayingModel {
    static let shared = NowPlayingModel()

    /// 描く 1 枚。コアが組んだものをそのまま持つ。
    private(set) var bar: NowPlayingBar?
    /// タップで開く曲。バーを組むときに引いたものを使い回す (開くたびに引き直さない)。
    private(set) var song: Song?

    private init() {}

    /// 再生状態が変わったときに呼ぶ。`MusicKitService.playbackKey` を鍵にする。
    func refresh() async {
        let service = MusicKitService.shared
        // フル再生でない (試聴・停止) なら歌詞は手放す。追従はフル再生だけ。
        LyricsSession.shared.release(unlessSongId: service.isFullPlayback ? service.nowPlayingSongId : nil)
        guard let songId = service.nowPlayingSongId else {
            bar = nil
            song = nil
            return
        }
        // 曲が変わったときだけ引き直す。一時停止/再開では同じ曲のまま。
        if song?.id != songId {
            song = try? await AppContainer.shared.songReading.song(id: songId)
        }
        bar = await AppContainer.shared.nowPlayingReading.bar(
            songId: songId,
            kind: service.nowPlayingKind,
            isPlaying: service.isPlaying
        )
        // バーを先に出してから、その曲の歌詞を取りに行く (曲送りで替わった曲にも付いてくる)。
        if service.isFullPlayback { await LyricsSession.shared.follow(songId: songId) }
    }
}

/// タブバーの直上に出す再生中バー (ミニプレイヤー)。
///
/// 出すのは **このアプリが鳴らしている音** だけ。純正ミュージックアプリで
/// かかっている曲は拾わない (`SystemMusicPlayer` は使っていない)。
///
/// 何を出すかの判断はコア (`imas-core` の `now_playing`) が持つ。ここは
/// [`NowPlayingModel`] が持つ 1 枚を描くだけで、名義の組み立ても試聴の書き分けもしない。
struct NowPlayingBarView: View {
    enum Placement {
        /// タブの中身の下端に差し込む帯 (iOS 25 以前・iPad のサイドバー)。
        case inset
        /// iOS 26 のタブバーの上に浮く枠 (`tabViewBottomAccessory`)。地は OS のガラス。
        case accessory
    }
    var placement: Placement = .inset

    private var model: NowPlayingModel { NowPlayingModel.shared }
    /// 枠が畳まれてタブバーの中に入ったとき (`.inline`) は、曲名と再生だけにする。
    @Environment(\.nowPlayingIsInline) private var isInline
    @State private var destination: DetailDestination?
    @State private var showsLyricsPlayer = false
    /// 鳴っている曲の歌詞 (歌詞タブが預けたとき)。あれば今の行を出し、タップで歌詞プレイヤーを開く。
    private var lyricsEntry: LyricsSession.Entry? {
        LyricsSession.shared.entry(forSongId: model.bar?.songId)
    }

    /// ジャケの一辺。Apple Music のミニプレイヤーとほぼ同じ大きさ。
    private static let artworkSize: CGFloat = 40

    var body: some View {
        Group {
            if let bar = model.bar {
                barContent(bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.bar?.songId)
        .sheet(item: $destination) { DetailSheetView(destination: $0) }
        .fullScreenCover(isPresented: $showsLyricsPlayer) {
            NowPlayingLyricsPlayerView { song in
                // 編集は曲の詳細の歌詞タブから (記録の画面はそちらが持つ)。
                showsLyricsPlayer = false
                destination = .song(song)
            }
        }
    }

    private func barContent(_ bar: NowPlayingBar) -> some View {
        VStack(spacing: 0) {
            if placement == .inset { ImasRowDivider() }

            HStack(spacing: DS.sp3) {
                ArtworkImageView(
                    url: bar.artworkUrl.flatMap(URL.init(string:)),
                    size: placement == .accessory ? 30 : Self.artworkSize,
                    songTitle: bar.title,
                    // seed は色 hex。ブランド ID をそのまま渡すと色として読まれる (P5-04)。
                    seed: BrandColors.hex(for: model.song?.brandId)
                )
                // 右の Text(bar.title) と `.accessibilityElement(children: .combine)` で
                // 一つに合わさるので、ジャケ側の読み上げ (曲名) は隠して二重読みを防ぐ。
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(bar.title)
                        .font(.imasSubhead.weight(.medium))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if isInline {
                        EmptyView()
                    } else if let entry = lyricsEntry, lyricHasTiming(starts: entry.lyrics.lines.map { $0.startMs.map(Int64.init) }) {
                        NowPlayingLyricLine(entry: entry) { subtitleLine(bar) }
                    } else {
                        subtitleLine(bar)
                    }
                }

                Spacer(minLength: 0)

                if MusicKitService.shared.hasQueue && !isInline {
                    ImasIconButton(systemImage: "backward.fill", label: "前の曲", size: .regular, style: .plain) {
                        MusicKitService.shared.skipToPrevious()
                    }
                }
                ImasIconButton(
                    systemImage: bar.isPlaying ? "pause.fill" : "play.fill",
                    label: bar.isPlaying ? "一時停止" : "再生",
                    size: .regular,
                    style: .plain
                ) {
                    // stop ではなく pause。stop は曲ごと手放すのでバーが消えてしまう。
                    if bar.isPlaying {
                        MusicKitService.shared.pause()
                    } else {
                        MusicKitService.shared.resume()
                    }
                }
                if MusicKitService.shared.hasQueue {
                    ImasIconButton(systemImage: "forward.fill", label: "次の曲", size: .regular, style: .plain) {
                        MusicKitService.shared.skipToNext()
                    }
                    .disabled(!MusicKitService.shared.canSkipToNext)
                }
            }
            .padding(.horizontal, placement == .accessory ? DS.sp3 : DS.sp4)
            .padding(.vertical, placement == .accessory ? DS.sp1 : DS.sp3)
        }
        .background(placement == .inset ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            if lyricsEntry != nil || MusicKitService.shared.hasQueue {
                AppAnalytics.tap("now_playing.open_lyrics_player")
                showsLyricsPlayer = true
            } else {
                destination = model.song.map(DetailDestination.song)
            }
        }
        // 下に払うと曲を手放してバーごと消す。一時停止では消えないので、
        // 「もう聴かない」を伝える手段がこれしかない (Apple Music と同じ)。
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { if $0.translation.height > 24 { MusicKitService.shared.stop() } }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(lyricsEntry != nil ? "歌詞プレイヤーを開く。下に払うと閉じる" : "曲の詳細を開く。下に払うと閉じる")
        .accessibilityAction(named: "閉じる") { MusicKitService.shared.stop() }
    }

    /// 2 行目。名義と「試聴」の印を別の `Text` にする。
    ///
    /// 1 本に繋いで `lineLimit(1)` に掛けると、長い名義に押し出されて
    /// **末尾の印だけが真っ先に消える**。伝えたいのは「30 秒で終わる」の方なので、
    /// 印に `layoutPriority` を与えて先に場所を取らせる。
    @ViewBuilder
    private func subtitleLine(_ bar: NowPlayingBar) -> some View {
        if bar.subtitle != nil || bar.previewMark != nil {
            HStack(spacing: DS.Space.gapTight) {
                if let subtitle = bar.subtitle {
                    Text(subtitle).lineLimit(1)
                }
                if let mark = bar.previewMark {
                    if bar.subtitle != nil { Text("·") }
                    Text(mark).lineLimit(1).layoutPriority(1)
                }
            }
            .font(.imasCaption)
            .foregroundStyle(DS.ink3)
        }
    }
}

/// 再生中バーの 2 行目に出す、いま歌われている行 (と歌う人の帯)。
///
/// 位置は周期で読む (バーは画面に出続けるので、行の切り替わりより少し細かく)。
/// 最初の行の前 (イントロ) は `fallback` (名義) を出す。
///
/// ⚠️ 歌詞の本文を出すので、選択・コピーの口を付けないこと。
private struct NowPlayingLyricLine<Fallback: View>: View {
    let entry: LyricsSession.Entry
    @ViewBuilder let fallback: () -> Fallback

    /// メインの行だけに時刻を入れた並び (被せの行に今の行を取られない)。
    private var mainStarts: [Int64?] {
        entry.lyrics.lines.map { $0.isOverlay ? nil : $0.startMs.map(Int64.init) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let line = MusicKitService.shared.fullPlaybackPositionMs.flatMap { ms in
                lyricActiveLine(starts: mainStarts, positionMs: Int64(ms)).map { entry.lyrics.lines[Int($0)] }
            }
            if let line, line.kind == .lyric {
                let split = lyricOverlaySplit(text: line.text)
                HStack(spacing: DS.sp2) {
                    if !line.allSingers.isEmpty {
                        ImasPartStripe(colors: entry.cast.colors(line.allSingers)).frame(height: 14)
                    }
                    Text(split.main.isEmpty ? line.text : split.main)
                        .imasText(.meta, color: DS.ink2)
                        .lineLimit(1)
                }
                .id(line.id)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: line.id)
            } else {
                fallback()
            }
        }
    }
}

extension View {
    /// タブコンテンツの下端に、同期バーと再生中バーをこの順で差し込む。
    ///
    /// 2 つを別々の modifier にすると、付ける順序 (= どちらが下に来るか) が
    /// 呼び出し側 5 箇所に散る。順序は 1 つの判断なのでここに閉じる。
    /// 同期バーは数秒で畳まれるが再生中バーは鳴っている間ずっと残るので、
    /// タブバー寄り (下) が再生中バー。
    func bottomBarsInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { SyncStatusBar() }
            .safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingInsetSlot() }
    }

    /// iOS 26.1 以降の iPhone では、再生中バーをタブバーの上に浮く枠 (OS のガラス) に出す。
    /// タブの中身の下端の帯 (`bottomBarsInset`) は、そのとき出さない。
    func nowPlayingTabAccessory() -> some View {
        modifier(NowPlayingTabAccessory())
    }
}

/// 再生中バーをタブバーの上の枠に出すか (iOS 26.1 以降・狭い画面)。帯と枠の二重出しを防ぐ判断を 1 か所に。
private func usesNowPlayingAccessory(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
    #if compiler(>=6.2)
    if #available(iOS 26.1, *) { return sizeClass == .compact }
    #endif
    return false
}

private struct NowPlayingInsetSlot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        if !usesNowPlayingAccessory(sizeClass) { NowPlayingBarView() }
    }
}

private struct NowPlayingTabAccessory: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.1, *), usesNowPlayingAccessory(sizeClass) {
            content
                .tabViewBottomAccessory(isEnabled: NowPlayingModel.shared.bar != nil) {
                    NowPlayingAccessoryContent()
                }
                // 下へ読み進めるとタブバーを畳み、再生中の枠がその中に入る (ミュージックアプリと同じ)。
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.1, *)
private struct NowPlayingAccessoryContent: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    var body: some View {
        NowPlayingBarView(placement: .accessory)
            .environment(\.nowPlayingIsInline, accessoryPlacement == .inline)
            .imasGlassPaperFill()
    }
}
#endif

private struct NowPlayingIsInlineKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 再生中の枠がタブバーの中に畳まれているか。
    fileprivate var nowPlayingIsInline: Bool {
        get { self[NowPlayingIsInlineKey.self] }
        set { self[NowPlayingIsInlineKey.self] = newValue }
    }
}
