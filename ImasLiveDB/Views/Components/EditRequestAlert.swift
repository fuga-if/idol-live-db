import SwiftUI

extension View {
    /// マスタ修正リクエスト (issue化) を送信した後の確認アラート。
    /// 一般ユーザーの編集は直接反映ではなく「修正リクエスト」になるため、
    /// 送信完了を明示して期待値を揃える (OK で onDismiss = 通常は画面を閉じる)。
    func editRequestSentAlert(isPresented: Binding<Bool>, onDismiss: @escaping () -> Void) -> some View {
        alert("修正リクエストを送信しました", isPresented: isPresented) {
            Button("OK", action: onDismiss)
        } message: {
            Text("運営の確認後に反映されます。ご協力ありがとうございます！")
        }
    }
}
