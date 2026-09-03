import SwiftUI

/// JASRAC 許諾マークと許諾番号の掲示。
///
/// 許諾条件が「お申込みいただいたサイトのトップページ等の見やすい位置に表示してください」
/// なので、アプリの情報画面 (`AboutView`) と、実際に歌詞を出している画面の両方に置く。
///
/// ⚠️ マーク画像は JASRAC から**メールで届く**もので、こちらで作ってはいけない
///    (それらしい画像を自作すると、許諾の証明ではなく偽装になる)。
///    届いた画像を `Assets.xcassets` に `jasrac_mark` の名前で入れると自動的に出る。
///    未配置の間は番号だけを表示する — マークが無いより、番号すら無い方が条件から遠い。
struct JASRACLicenseNotice: View {
    /// 歌詞画面の隅に小さく出すか、情報画面に 1 件として出すか。
    enum Placement { case about, lyrics }

    let placement: Placement

    /// アセットが入っているかで出し分ける。`Image("...")` は不在でも例外にならず
    /// 空で描画されるだけなので、マークの有無をここで明示的に見る。
    private var mark: Image? {
        UIImage(named: "jasrac_mark").map { Image(uiImage: $0).renderingMode(.original) }
    }

    var body: some View {
        switch placement {
        case .about:
            HStack(spacing: 12) {
                if let mark {
                    mark.resizable().scaledToFit().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(JASRACLicense.notice)
                        .font(.footnote)
                    Text("歌詞は JASRAC の許諾を受けて掲載しています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

        case .lyrics:
            VStack(spacing: 4) {
                if let mark {
                    mark.resizable().scaledToFit().frame(width: 28, height: 28)
                }
                Text(JASRACLicense.notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }
}
