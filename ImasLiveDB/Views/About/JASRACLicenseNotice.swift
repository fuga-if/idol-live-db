import SwiftUI

/// 歌詞の許諾マークと許諾番号の掲示 (JASRAC と NexTone の 2 団体)。
///
/// 管理団体は曲ごとに違い、表示中の曲がどちらの管理かはアプリが知らないので、
/// 両方を常に並べて出す。NexTone の条件は「許諾番号を許諾マークと併せて
/// サービス画面上で視認できる任意の箇所に掲載」で、JASRAC と同じ場所に置けば満たせる。
///
/// 許諾条件が「お申込みいただいたサイトのトップページ等の見やすい位置に表示してください」
/// なので、アプリの情報画面 (`AboutView`) と、実際に歌詞を出している画面の両方に置く。
///
/// ⚠️ マーク画像は各団体から**メールで届いた原本**を使う。こちらで作ってはいけない
///    (それらしい画像を自作すると、許諾の証明ではなく偽装になる)。
///    `Assets.xcassets/jasrac_mark` に入れてある (3x = 受け取った 240px 原本、
///    1x/2x は等比縮小のみ。色を変えたり縦横比を崩したりしないこと)。
///    NexTone は `Assets.xcassets/nextone_mark` (2026-09-25 のメール添付 200px 原本を
///    無加工の単一スケールで入れてある。縮小版も作らない)。
///
///    JASRAC のマークは内側が不透明な白なので、ダークモードでも白地に青のまま出る。
///    これは公式の見え方であって不具合ではない。地の色に合わせて反転させない。
///    アセットを外しても番号だけは残る (マークが無いより、番号すら無い方が条件から遠い)。
struct JASRACLicenseNotice: View {
    /// 歌詞画面の隅に小さく出すか、情報画面に 1 件として出すか。
    enum Placement { case about, lyrics }

    let placement: Placement

    /// 掲示する 1 団体ぶん。マークのアセット名と表記。
    private struct License: Identifiable {
        let assetName: String
        let notice: String
        var id: String { assetName }

        /// アセットが入っているかで出し分ける。`Image("...")` は不在でも例外にならず
        /// 空で描画されるだけなので、マークの有無をここで明示的に見る。
        var mark: Image? {
            UIImage(named: assetName).map { Image(uiImage: $0).renderingMode(.original) }
        }
    }

    private let licenses = [
        License(assetName: "jasrac_mark", notice: JASRACLicense.notice),
        License(assetName: "nextone_mark", notice: NexToneLicense.notice),
    ]

    var body: some View {
        switch placement {
        case .about:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(licenses) { license in
                    HStack(spacing: 12) {
                        if let mark = license.mark {
                            mark.resizable().scaledToFit().frame(width: 40, height: 40)
                        }
                        Text(license.notice)
                            .font(.footnote)
                    }
                }
                Text("歌詞は JASRAC・NexTone の許諾を受けて掲載しています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

        case .lyrics:
            // 2 団体を横に並べ、それぞれマークの下に番号を置く (JASRAC の指定が「マークの下に番号」)。
            // 小さい画面や大きい文字で横に収まらないときは縦に積む (番号を省略させない)。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { lyricsItems }
                VStack(spacing: 12) { lyricsItems }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }

    private var lyricsItems: some View {
        ForEach(licenses) { license in
            VStack(spacing: 4) {
                if let mark = license.mark {
                    mark.resizable().scaledToFit().frame(width: 28, height: 28)
                }
                Text(license.notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
