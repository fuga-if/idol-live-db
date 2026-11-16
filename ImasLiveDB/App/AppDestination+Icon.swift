import SwiftUI

/// 行き先のアイコン。並び・見出し・文言はコア (`appNavigationSections`) が持ち、
/// SF Symbols の名前だけ OS 側で引く (Android は Material の別物になるため)。
extension AppDestination {
    var systemImage: String {
        switch self {
        case .schedule: return "calendar"
        case .events: return "music.mic"
        case .songs: return "music.note.list"
        case .idols: return "person.3"
        case .produce: return "star.fill"
        case .stats: return "chart.bar.xaxis"
        case .timeline: return "calendar.day.timeline.left"
        case .polls: return "chart.bar.doc.horizontal"
        case .callGuide: return "hands.clap.fill"
        case .communityActivity: return "person.2.fill"
        case .tagActivity: return "flame.fill"
        case .games: return "gamecontroller.fill"
        case .chat: return "bubble.left.and.text.bubble.right"
        }
    }

    var label: String { AppDestination.labels[self] ?? "" }
    var analyticsKey: String { AppDestination.analyticsKeys[self] ?? "" }

    // チャットはタブバーの 5 枠とは別枠なので、選べる並びには入っていない。名前だけここで足す。
    private static let items = tabBarChoices(lyricsAvailable: true)
        + [appNavigationChatItem(chatConnected: true)].compactMap { $0 }
    private static let labels = Dictionary(uniqueKeysWithValues: items.map { ($0.destination, $0.label) })
    private static let analyticsKeys = Dictionary(uniqueKeysWithValues: items.map { ($0.destination, $0.analyticsKey) })
}
