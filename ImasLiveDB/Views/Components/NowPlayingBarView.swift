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
    private var model: NowPlayingModel { NowPlayingModel.shared }
    @State private var destination: DetailDestination?

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
    }

    private func barContent(_ bar: NowPlayingBar) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.sep).frame(height: 0.5)

            HStack(spacing: DS.sp3) {
                ArtworkImageView(
                    url: bar.artworkUrl.flatMap(URL.init(string:)),
                    size: Self.artworkSize,
                    songTitle: bar.title,
                    // seed は色 hex。ブランド ID をそのまま渡すと色として読まれる (P5-04)。
                    seed: BrandColors.hex(for: model.song?.brandId)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(bar.title)
                        .font(.imasSubhead.weight(.medium))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    subtitleLine(bar)
                }

                Spacer(minLength: 0)

                Button {
                    // stop ではなく pause。stop は曲ごと手放すのでバーが消えてしまう。
                    if bar.isPlaying {
                        MusicKitService.shared.pause()
                    } else {
                        MusicKitService.shared.resume()
                    }
                } label: {
                    Image(systemName: bar.isPlaying ? "pause.fill" : "play.fill")
                        .font(.imasTitle3)
                        .foregroundStyle(DS.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(bar.isPlaying ? "一時停止" : "再生")
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 6)
        }
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture { destination = model.song.map(DetailDestination.song) }
        // 下に払うと曲を手放してバーごと消す。一時停止では消えないので、
        // 「もう聴かない」を伝える手段がこれしかない (Apple Music と同じ)。
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { if $0.translation.height > 24 { MusicKitService.shared.stop() } }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("曲の詳細を開く。下に払うと閉じる")
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
            HStack(spacing: 4) {
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

extension View {
    /// タブコンテンツの下端に、同期バーと再生中バーをこの順で差し込む。
    ///
    /// 2 つを別々の modifier にすると、付ける順序 (= どちらが下に来るか) が
    /// 呼び出し側 5 箇所に散る。順序は 1 つの判断なのでここに閉じる。
    /// 同期バーは数秒で畳まれるが再生中バーは鳴っている間ずっと残るので、
    /// タブバー寄り (下) が再生中バー。
    func bottomBarsInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { SyncStatusBar() }
            .safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingBarView() }
    }
}
