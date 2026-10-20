import SwiftUI
import UIKit

// =============================================================================
// テキストシェア (X 投稿 / 標準シェアシート) の共通導線
//
// 画像カード (ShareCardActionPane) ほど重くない「一言 + リンク」のシェアはこちら。
// 投票系 (セトリ予想 / みんなの投票) の「〇〇に投票しました！」がこれを使う。
//
// 文面と URL (本文の組み立て・締切の書き方・X の投稿画面の URL・ID のエンコード) は
// すべてコア (imas-core `share_text.rs`) が作る。ここは OS の値をコアに渡して、
// 返ってきた文字列を出すだけにする (Android と同じ文面になる)。
// =============================================================================

extension SharePayload {
    /// お題そのもののシェア。開催中は誘い、終了後は結果の知らせ。締切を載せるかも書き方もコアが決める。
    static func pollInvite(poll: Poll) -> SharePayload {
        sharePollInvitePayload(
            pollId: poll.id,
            title: poll.title,
            endsAtEpochMs: Int64((poll.endsAt.timeIntervalSince1970 * 1000).rounded()),
            isActive: poll.isActive,
            // 締切の日付は端末の時刻帯で読む (その時点の UTC からのずれを渡す)。
            tzOffsetSeconds: Int32(TimeZone.current.secondsFromGMT(for: poll.endsAt))
        )
    }
}

/// X の投稿画面を開く。X アプリの投稿画面を直接開き (ログイン中のアカウントで投稿できる)、
/// アプリが無いときだけブラウザの投稿画面へ落とす。`x.com/intent/post` を先に開くと
/// アプリが入っていてもブラウザ側に着地してしまう。
enum XPost {
    @MainActor
    static func open(_ payload: SharePayload) {
        let web = URL(string: sharePayloadXPostUrl(payload: payload))
        guard let app = URL(string: sharePayloadXAppPostUrl(payload: payload)) else {
            if let web { UIApplication.shared.open(web) }
            return
        }
        UIApplication.shared.open(app) { opened in
            if !opened, let web { UIApplication.shared.open(web) }
        }
    }
}

/// 「X にポスト」+「その他でシェア」の項目セット。
/// `Menu` にも `contextMenu` にもそのまま差し込めるよう、ラベルとは切り離してある。
struct SocialShareMenuItems: View {
    let payload: SharePayload
    /// AppAnalytics のイベント名 (例: "setlist_prediction.share")。
    let analyticsKey: String

    var body: some View {
        Button {
            AppAnalytics.tap("\(analyticsKey).x")
            XPost.open(payload)
        } label: {
            Label("X にポスト", systemImage: "paperplane")
        }

        ShareLink(item: sharePayloadPlainText(payload: payload)) {
            Label("その他でシェア", systemImage: "square.and.arrow.up")
        }
    }
}

/// 上記の項目セットをボタン化したメニュー。ラベルは呼び出し側が自由に差し替える。
struct SocialShareMenu<MenuLabel: View>: View {
    let payload: SharePayload
    let analyticsKey: String
    @ViewBuilder var label: MenuLabel

    var body: some View {
        Menu {
            SocialShareMenuItems(payload: payload, analyticsKey: analyticsKey)
        } label: {
            label
        }
        // Menu を List セル内で使うと .plain ではタップが散るため、他の行内ボタンと同じ流儀に揃える。
        .buttonStyle(.borderless)
    }
}

/// 投票シェアの定番ラベル (淡い塗りのカプセル)。行内・セクション末尾のどちらでも収まる寸法。
struct SocialShareChipLabel: View {
    let title: String
    var accent: Color = DS.sys

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.and.arrow.up")
                .font(.imasScaled(12, weight: .semibold))
            Text(title)
                .font(.imasScaled(13, weight: .semibold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, 7)
        .background(accent.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}
