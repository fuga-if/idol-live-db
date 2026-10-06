import SwiftUI
import UIKit

/// iOS の「テキストをスキャン」(メモアプリのキーボードにあるもの) を、入力欄を介さずに開く口。
///
/// カメラの映像の中で文字の塊を選んで「入力」を押すと、その文字が `onText` に届く。
/// 読み取りは端末の中だけ (OS の機能)。画面には見えない 1 点の受け手を置き、ボタンから
/// その受け手でスキャンを始める (`UIResponder.captureTextFromCamera`)。
@MainActor
final class LiveTextCapture {
    /// 受け手。`UIKeyInput` に届いた文字を渡す。
    final class Receiver: UIView, UIKeyInput {
        var onText: ((String) -> Void)?
        var hasText: Bool { false }
        func insertText(_ text: String) {
            onText?(text)
            // 1 回の「入力」で 1 度だけ。受け手のままだとキーボードが出続ける。
            DispatchQueue.main.async { [weak self] in _ = self?.resignFirstResponder() }
        }
        func deleteBackward() {}
        override var canBecomeFirstResponder: Bool { true }
    }

    let receiver = Receiver(frame: .zero)

    /// この端末でテキストスキャンが使えるか (A12 以降の iPhone)。
    var isAvailable: Bool {
        receiver.canPerformAction(#selector(UIResponder.captureTextFromCamera(_:)), withSender: nil)
    }

    func start(onText: @escaping (String) -> Void) {
        receiver.onText = onText
        guard receiver.becomeFirstResponder() else { return }
        receiver.captureTextFromCamera(nil)
    }
}

/// 受け手を画面に置く (見えない・場所を取らない)。
struct LiveTextCaptureAnchor: UIViewRepresentable {
    let capture: LiveTextCapture

    func makeUIView(context: Context) -> LiveTextCapture.Receiver { capture.receiver }
    func updateUIView(_ uiView: LiveTextCapture.Receiver, context: Context) {}
}
