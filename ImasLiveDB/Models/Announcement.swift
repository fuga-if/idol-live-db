import SwiftUI

/// アプリ内蔵のお知らせ (新機能告知など)。サーバー不要・アプデで増える (ゼロコスト)。
struct Announcement: Identifiable {
    let id: String        // リリースをまたいで安定させる
    let date: String      // "2026-06-17"
    let title: String
    let summary: String
    let body: [String]    // 段落
    let icon: String      // SF Symbol
    let tint: Color
    let link: AnnouncementLink?
}

/// お知らせ詳細から開ける遷移先 (任意)。
enum AnnouncementLink {
    case widgetHowTo
}

enum AnnouncementCatalog {
    /// 新しいものほど上 (表示順)。
    static let all: [Announcement] = [
        Announcement(
            id: "v1.7.1_widget_polish",
            date: "2026-06-19",
            title: "スライドショーの画像を選べるように",
            summary: "ウィジェットに出す画像を選べるようになり、アイドル選択も探しやすくなりました。",
            body: [
                "ウィジェットのスライドショーに出す画像を、ギャラリーで1枚ずつ選べるようになりました。サムネを長押しして「スライドショーから外す/入れる」を切り替えられます。お気に入りだけを回すこともできます。",
                "ウィジェット編集でアイドルを選ぶとき、検索で絞り込めるようになり、ブランド名も表示されるようになりました。",
                "ギャラリーの表示や、画像まわりの細かな不具合を修正しました。",
            ],
            icon: "rectangle.stack.badge.play",
            tint: Color(red: 0.4, green: 0.5, blue: 1),
            link: .widgetHowTo
        ),
        Announcement(
            id: "v1.7_oshi_widget",
            date: "2026-06-17",
            title: "担当の画像をホーム画面に",
            summary: "ホーム画面ウィジェットに、自分で入れた推しの画像を表示できるようになりました。",
            body: [
                "アイドル詳細の「ギャラリー」に画像を何枚でも追加できるようになりました。先頭の1枚がアイコンになります。",
                "ホーム画面ウィジェット「担当の画像」を追加すると、選んだアイドルの画像を表示。タップで次の画像に切り替わり、放っておいても自動でローテーションします。",
                "「タップでアプリ」版もあるので、お気に入りの起動ショートカットとしても使えます。",
            ],
            icon: "person.crop.square.badge.camera",
            tint: Color(red: 1, green: 0.3, blue: 0.55),
            link: .widgetHowTo
        ),
    ]
}

/// App.init など MainActor 隔離外からも読める軽量ヘルパ (UserDefaults 直読み)。
enum AnnouncementDefaults {
    static let readKey = "read_announcement_ids"
    static let seenVersionKey = "announce_seen_version"

    /// 未読が 1 件でもあるか。
    static func hasUnread() -> Bool {
        let read = Set(UserDefaults.standard.stringArray(forKey: readKey) ?? [])
        return AnnouncementCatalog.all.contains { !read.contains($0.id) }
    }
}
