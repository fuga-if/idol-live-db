import SwiftUI

/// DB を開いている間の画面。起動画面 (Info.plist の UILaunchScreen) と同じ背景とロゴを出し、
/// 起動画面がそのまま続いているように見せる。
///
/// 普段の起動はすぐ終わるので、何も足さない。初回やアップデート後のように長引いたときだけ、
/// 少し待ってから「準備しています」を出す (固まったと思わせない)。
struct DatabasePreparingView: View {
    @State private var showsProgress = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchLogo").accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            if showsProgress {
                ProgressView {
                    Text("データを準備しています").font(.imasSubhead).foregroundStyle(DS.ink2)
                }
                .padding(.bottom, DS.sp9)
                .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation { showsProgress = true }
        }
    }
}

/// DB を開けなかったときの画面。端末のデータは消していないので、「もう一度試す」だけを出す。
/// 再インストールは勧めない (端末にしかないデータが消える)。
struct DatabaseRecoveryView: View {
    let detail: String
    let retry: () -> Void

    var body: some View {
        // 文字を大きくしている人でも読み切れるようにスクロールさせ、短いときは縦の中央に置く。
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: DS.sp3) {
                    ImasEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "データを開けませんでした",
                        message: "端末に保存しているデータを開く途中で問題が起きました。データは消えていません。"
                            + "もう一度試しても開けないときは、アプリを最新版に更新してください。",
                        actionTitle: "もう一度試す",
                        action: retry
                    )
                    Text("詳細: \(detail)")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, DS.sp7)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Color("LaunchBackground").ignoresSafeArea())
    }
}
