import SwiftUI

// =============================================================================
// テキストシェア (X 投稿 / 標準シェアシート) の共通導線
//
// 画像カード (ShareCardActionPane) ほど重くない「一言 + リンク」のシェアはこちら。
// 投票系 (セトリ予想 / みんなの投票) の「〇〇に投票しました！」がこれを使う。
// =============================================================================

/// シェアする一言 + 着地先 URL。
/// X の intent は本文と URL を別パラメータで受けるとリンクカードが出るので、
/// 文字列連結ではなく本文/URL を分けて保持する。
struct SocialSharePayload {
    let message: String
    let url: URL?

    /// 標準シェアシート (ShareLink) 用のプレーンテキスト。
    /// 「本文 + 改行 + URL」の組み立ては既存のイベント/公演シェアと同じ (DeeplinkBuilder が正)。
    var plainText: String {
        guard let url else { return message }
        return DeeplinkBuilder.shareText(name: message, url: url)
    }
}

extension SocialSharePayload {
    /// お題への誘いシェア。一覧と詳細で文面/リンクがズレないよう組み立てはここだけ。
    /// 締切は開催中のときだけ載せる (終了済みに締切を出しても意味がない)。
    static func pollInvite(poll: Poll) -> SocialSharePayload {
        SocialSharePayload(
            message: ShareMessage.pollInvite(title: poll.title, endsAt: poll.isActive ? poll.endsAt : nil),
            url: DeeplinkBuilder.pollURL(id: poll.id)
        )
    }
}

enum SocialShare {
    /// X (Twitter) の投稿画面 URL。X アプリ未インストールでもブラウザの投稿画面に着地する。
    static func xPostURL(_ payload: SocialSharePayload) -> URL? {
        var components = URLComponents(string: "https://x.com/intent/post")
        var items = [URLQueryItem(name: "text", value: payload.message)]
        if let url = payload.url {
            items.append(URLQueryItem(name: "url", value: url.absoluteString))
        }
        components?.queryItems = items
        return components?.url
    }
}

/// 「X にポスト」+「その他でシェア」の項目セット。
/// `Menu` にも `contextMenu` にもそのまま差し込めるよう、ラベルとは切り離してある。
struct SocialShareMenuItems: View {
    let payload: SocialSharePayload
    /// AppAnalytics のイベント名 (例: "setlist_prediction.share")。
    let analyticsKey: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            AppAnalytics.tap("\(analyticsKey).x")
            if let url = SocialShare.xPostURL(payload) { openURL(url) }
        } label: {
            Label("X にポスト", systemImage: "paperplane")
        }

        ShareLink(item: payload.plainText) {
            Label("その他でシェア", systemImage: "square.and.arrow.up")
        }
    }
}

/// 上記の項目セットをボタン化したメニュー。ラベルは呼び出し側が自由に差し替える。
struct SocialShareMenu<MenuLabel: View>: View {
    let payload: SocialSharePayload
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(accent.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - 文面

/// 投票系シェアの文面ビルダー。ハッシュタグはアプリ共通の #アイドルライブDB に揃える。
enum ShareMessage {
    static let hashtag = "#アイドルライブDB"

    /// 「A」「B」「C」形式。0件は空文字 (呼び出し側がシェア導線ごと隠す前提)。
    static func quoted(_ names: [String]) -> String {
        names.map { "「\($0)」" }.joined()
    }

    /// セトリ予想の投票シェア。
    static func predictionVotes(showName: String, songTitles: [String]) -> String {
        "\(showName) のセトリ予想で\(quoted(songTitles))に投票しました！ \(hashtag)"
    }

    /// みんなの投票 (お題) への投票シェア。
    static func pollVotes(pollTitle: String, entityNames: [String]) -> String {
        "お題「\(pollTitle)」で\(quoted(entityNames))に投票しました！ \(hashtag)"
    }

    /// お題そのもののシェア (まだ投票していない人への誘い)。
    static func pollInvite(title: String, endsAt: Date?) -> String {
        let deadline = endsAt.map { " 締切は\(pollDeadlineFormatter.string(from: $0))！" } ?? ""
        return "お題「\(title)」に投票しよう！\(deadline) \(hashtag)"
    }

    private static let pollDeadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
