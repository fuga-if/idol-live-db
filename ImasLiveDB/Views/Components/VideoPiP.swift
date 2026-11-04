import SwiftUI
import UIKit

/// 参考動画の小窓 (アプリの中だけで浮かぶ PiP)。
///
/// 動画を押すと最初からこの小窓で開く。曲の画面 (シート) を閉じても、他の画面へ移っても
/// 再生が続くように、プレーヤーは画面ではなくアプリで 1 つだけ持つ。
/// シートより上に出すため、アプリの画面とは別の、触れない所を素通しするウィンドウに置く
/// (`LocalWriteFailureAlert` と同じ考え方。こちらはアラートより下の段)。
///
/// YouTube の規約で、埋め込みプレーヤーは 200×200 pt 以上・上に何も重ねない。
/// なので小窓は幅いっぱい・プレーヤーの高さは 200 以上で、閉じる操作はプレーヤーの外
/// (上のバー) に置く。
@MainActor
@Observable
final class VideoPiP {
    static let shared = VideoPiP()

    /// 小窓で流している動画。
    struct Item {
        let videoID: String
        let title: String?
        let url: URL
        let player: YouTubeEmbedPlayer
    }

    /// 小窓の置き場所。バーをつまんで上下へずらすと、近いほうの端に寄る。
    enum Dock { case top, bottom }

    private(set) var item: Item?
    /// 押してみて埋め込みを止めていると分かった動画。一覧の行も案内に替える。
    private(set) var unplayableVideoIDs: Set<String> = []
    var dock: Dock = .bottom

    /// 小窓の枠 (ウィンドウの座標)。この外の指はアプリの画面へ素通しする。
    @ObservationIgnored fileprivate var frame: CGRect = .zero
    @ObservationIgnored private var window: PassthroughWindow?

    private init() {}

    var isUnplayable: Bool { item.map { unplayableVideoIDs.contains($0.videoID) } ?? false }

    func isPlaying(videoID: String) -> Bool { item?.videoID == videoID }

    func play(_ item: Item) {
        self.item = item
        showWindow()
    }

    func close() {
        item = nil
        frame = .zero
        window?.isHidden = true
        window = nil
    }

    func markUnplayable(_ videoID: String) {
        unplayableVideoIDs.insert(videoID)
    }

    private func showWindow() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })
                  ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let overlay = PassthroughWindow(windowScene: scene)
        overlay.hitArea = { [weak self] in self?.frame ?? .zero }
        // 画面より上・アラートより下。キーにはしない (文字入力はアプリの画面のまま)。
        overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        overlay.backgroundColor = .clear
        // アプリ側でライト/ダークを固定していればそれに合わせる。
        overlay.overrideUserInterfaceStyle = scene.keyWindow?.overrideUserInterfaceStyle ?? .unspecified
        let host = UIHostingController(rootView: VideoPiPOverlay(pip: self))
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.isHidden = false
        window = overlay
    }
}

/// 小窓の外の指を素通しするウィンドウ。SwiftUI の中身は当たり判定が全面になるので、
/// 小窓の枠で切る。
private final class PassthroughWindow: UIWindow {
    var hitArea: () -> CGRect = { .zero }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard hitArea().contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// 小窓の中身。上のバー (つまんで動かす・動画名・YouTube で開く・閉じる) とプレーヤー。
private struct VideoPiPOverlay: View {
    @Bindable var pip: VideoPiP

    /// バーをつまんで動かしている量 (縦だけ)。
    @State private var dragY: CGFloat = 0

    private let barHeight: CGFloat = 40
    /// タブバーに被らない高さ (下に寄せたとき)。
    private let bottomClearance: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            if let item = pip.item {
                let width = min(geo.size.width - DS.sp4 * 2, 520)
                // 規約の 200 pt を割らない (幅の狭い端末では上下に黒が入る)。
                let playerHeight = max(200, (width * 9 / 16).rounded())
                let height = barHeight + playerHeight
                let topY = DS.sp3 + height / 2
                let bottomY = geo.size.height - bottomClearance - DS.sp3 - height / 2
                let restY = pip.dock == .top ? topY : bottomY
                let y = min(max(restY + dragY, topY), bottomY)

                VStack(spacing: 0) {
                    bar(item)
                        .gesture(dragGesture(topY: topY, bottomY: bottomY))
                    stage(item)
                        .frame(height: playerHeight)
                }
                .frame(width: width)
                .imasFloatingWindow()
                .position(x: geo.size.width / 2, y: y)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pip.frame = $0 }
                .transition(.move(edge: pip.dock == .top ? .top : .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pip.dock)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pip.item?.videoID)
    }

    private func bar(_ item: VideoPiP.Item) -> some View {
        HStack(spacing: DS.sp3) {
            ImasWindowGrip()
            Text(item.title ?? "参考動画")
                .imasText(.meta, color: DS.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                AppAnalytics.tap("video_pip.open_youtube")
                UIApplication.shared.open(item.url)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .imasText(.value, color: DS.ink2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("YouTube で開く")
            Button {
                AppAnalytics.tap("video_pip.close")
                withAnimation(.easeOut(duration: 0.18)) { pip.close() }
            } label: {
                Image(systemName: "xmark")
                    .imasText(.value, color: DS.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("小窓を閉じる")
        }
        .padding(.leading, DS.sp4)
        .padding(.trailing, DS.sp2)
        .frame(height: barHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func stage(_ item: VideoPiP.Item) -> some View {
        if pip.isUnplayable {
            YouTubeUnplayableNotice {
                UIApplication.shared.open(item.url)
                pip.close()
            }
        } else {
            YouTubeInlinePlayer(player: item.player) {
                pip.markUnplayable(item.videoID)
            }
            .id(item.videoID)
        }
    }

    /// バーをつまんで上下へ。離したら、勢いも見て近いほうの端に寄せる。
    private func dragGesture(topY: CGFloat, bottomY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { dragY = $0.translation.height }
            .onEnded { value in
                let restY = pip.dock == .top ? topY : bottomY
                let landing = restY + value.predictedEndTranslation.height
                pip.dock = landing < (topY + bottomY) / 2 ? .top : .bottom
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { dragY = 0 }
            }
    }
}
