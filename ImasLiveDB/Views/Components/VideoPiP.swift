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
/// なのでプレーヤーの幅と高さは 200 以上で、閉じる操作はプレーヤーの外 (上のバー) に置く。
///
/// 大きさは 2 本指でつまんで変える (小窓のどこでも)。バーを 2 回押すと最小 ⇄ 最大。
/// 幅いっぱいより小さいときは、バーをつまんで四隅の近いほうへ寄せられる。
/// 決めた大きさは次に開いたときも使う。
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

    /// 小窓の置き場所。バーをつまんでずらすと、近いほうの端 (隅) に寄る。
    enum Dock { case top, bottom }
    /// 幅いっぱいより小さいときの左右の寄せ先。
    enum Side { case leading, trailing }

    private(set) var item: Item?
    /// 押してみて埋め込みを止めていると分かった動画。一覧の行も案内に替える。
    private(set) var unplayableVideoIDs: Set<String> = []
    var dock: Dock = .bottom
    var side: Side = .trailing

    /// 人が決めた小窓の幅。nil は「入る中でいちばん大きく」(はじめの大きさ)。
    private(set) var preferredWidth: CGFloat? = {
        let w = UserDefaults.standard.double(forKey: VideoPiP.widthKey)
        return w > 0 ? w : nil
    }()
    /// 2 本指でつまんでいる間の倍率 (離したら幅に焼き込んで 1 に戻す)。
    fileprivate(set) var pinchScale: CGFloat = 1
    /// いま描いている幅と、取れる幅の範囲 (つまみ終わりに丸めるため)。
    @ObservationIgnored fileprivate var shownWidth: CGFloat = 0
    @ObservationIgnored fileprivate var widthRange: ClosedRange<CGFloat> = 0...0
    private static let widthKey = "videoPiP.width"

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

    /// つまみ終わり。最大に近ければ「いちばん大きく」に戻し、画面が変わっても追う。
    fileprivate func commitPinch() {
        setWidth(shownWidth)
        pinchScale = 1
    }

    /// バーを 2 回押したとき。いま大きめなら最小へ、小さめなら最大へ。
    fileprivate func toggleSize() {
        let mid = (widthRange.lowerBound + widthRange.upperBound) / 2
        setWidth(shownWidth > mid ? widthRange.lowerBound : widthRange.upperBound)
    }

    private func setWidth(_ width: CGFloat) {
        let w = min(max(width, widthRange.lowerBound), widthRange.upperBound)
        if w >= widthRange.upperBound - 8 {
            preferredWidth = nil
            UserDefaults.standard.removeObject(forKey: Self.widthKey)
        } else {
            preferredWidth = w.rounded()
            UserDefaults.standard.set(Double(w.rounded()), forKey: Self.widthKey)
        }
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
        // 2 本指のつまみは、プレーヤー (WebView) の上でも取れるようにウィンドウで受ける。
        overlay.onPinch = { [weak self] recognizer in
            guard let self else { return }
            switch recognizer.state {
            case .changed: self.pinchScale = recognizer.scale
            case .ended, .cancelled, .failed:
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { self.commitPinch() }
            default: break
            }
        }
        overlay.isHidden = false
        window = overlay
    }
}

/// 小窓の外の指を素通しするウィンドウ。SwiftUI の中身は当たり判定が全面になるので、
/// 小窓の枠で切る。
private final class PassthroughWindow: UIWindow, UIGestureRecognizerDelegate {
    var hitArea: () -> CGRect = { .zero }
    var onPinch: (UIPinchGestureRecognizer) -> Void = { _ in }

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) { onPinch(recognizer) }

    /// プレーヤーやバーの指 (再生・停止・つまんで動かす) と一緒に取る。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard hitArea().contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// 小窓の中身。上のバー (つまんで動かす・動画名・YouTube で開く・閉じる) とプレーヤー。
private struct VideoPiPOverlay: View {
    @Bindable var pip: VideoPiP

    /// バーをつまんで動かしている量。
    @State private var drag: CGSize = .zero

    private let barHeight: CGFloat = 40
    /// タブバーに被らない高さ (下に寄せたとき)。
    private let bottomClearance: CGFloat = 56
    /// 規約の下限 (プレーヤーの幅・高さとも)。
    private let minPlayerSide: CGFloat = 200
    /// 大きい画面でも小窓らしさを残す上限。
    private let maxWidth: CGFloat = 720

    var body: some View {
        GeometryReader { geo in
            if let item = pip.item {
                let margin = DS.sp4
                let usableHeight = geo.size.height - bottomClearance - DS.sp3 * 2
                // 縦が足りない (横向きの iPhone など) ときは、高さが入る幅まで。
                let fitWidth = (usableHeight - barHeight) * 16 / 9
                let upper = max(minPlayerSide, min(geo.size.width - margin * 2, maxWidth, fitWidth))
                let range = minPlayerSide...upper
                let width = min(max((pip.preferredWidth ?? upper) * pip.pinchScale, range.lowerBound),
                                range.upperBound).rounded()
                // 規約の 200 pt を割らない (細くすると上下に黒が入る)。
                let playerHeight = max(minPlayerSide, (width * 9 / 16).rounded())
                let height = barHeight + playerHeight
                let topY = DS.sp3 + height / 2
                let bottomY = max(topY, geo.size.height - bottomClearance - DS.sp3 - height / 2)
                let leftX = margin + width / 2
                let rightX = max(leftX, geo.size.width - margin - width / 2)
                let restY = pip.dock == .top ? topY : bottomY
                let restX = rightX - leftX < 1 ? geo.size.width / 2 : (pip.side == .leading ? leftX : rightX)
                let y = min(max(restY + drag.height, topY), bottomY)
                let x = rightX - leftX < 1 ? restX : min(max(restX + drag.width, leftX), rightX)

                VStack(spacing: 0) {
                    bar(item)
                        .gesture(dragGesture(topY: topY, bottomY: bottomY, leftX: leftX, rightX: rightX))
                    stage(item)
                        .frame(height: playerHeight)
                }
                .frame(width: width)
                .imasFloatingWindow()
                .position(x: x, y: y)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pip.frame = $0 }
                .onChange(of: width, initial: true) { pip.shownWidth = width }
                .onChange(of: range, initial: true) { pip.widthRange = range }
                .transition(.move(edge: pip.dock == .top ? .top : .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pip.dock)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pip.side)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pip.preferredWidth)
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
        .onTapGesture(count: 2) {
            AppAnalytics.tap("video_pip.toggle_size")
            pip.toggleSize()
        }
        .accessibilityAction(named: "大きさを切り替える") { pip.toggleSize() }
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

    /// バーをつまんで動かす。離したら、勢いも見て近いほうの端 (細いときは隅) に寄せる。
    private func dragGesture(topY: CGFloat, bottomY: CGFloat, leftX: CGFloat, rightX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let restY = pip.dock == .top ? topY : bottomY
                let landingY = restY + value.predictedEndTranslation.height
                pip.dock = landingY < (topY + bottomY) / 2 ? .top : .bottom
                if rightX - leftX >= 1 {
                    let restX = pip.side == .leading ? leftX : rightX
                    let landingX = restX + value.predictedEndTranslation.width
                    pip.side = landingX < (leftX + rightX) / 2 ? .leading : .trailing
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { drag = .zero }
            }
    }
}
