import SwiftUI

/// 下のタブバーの並び (ユーザーが選ぶ)。保存は行き先の計測キーをカンマで繋いだ文字列。
/// 整え方 (プロデュースは必ず載る・上限・出せない行き先を落とす) はコアが決める。
enum TabBarSettings {
    static let storageKey = "tab_bar_order"

    /// AI チャットを出せるビルドか (試作。開発ビルド / TestFlight だけ)。
    @MainActor static var assistantAvailable: Bool { ChatGPTPlanSession.isPrototypeVisible }

    static func keys(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init)
    }

    /// 行き先を見出しごとに。先頭 (見出しなし) がタブバー、タブから外した主な画面と AI チャットは「そのほか」。
    @MainActor static func sections(_ raw: String) -> [NavSection] {
        appNavigationSectionsWithTabs(lyricsAvailable: LyricsFeature.isAvailable,
                                      assistantAvailable: assistantAvailable, tabKeys: keys(raw))
    }

    /// 整えた並び (保存する値)。
    @MainActor static func normalized(_ keys: [String]) -> [String] {
        normalizeTabBarKeys(lyricsAvailable: LyricsFeature.isAvailable,
                            assistantAvailable: assistantAvailable, tabKeys: keys)
    }
}

extension AppDestination: Identifiable {
    public var id: String { analyticsKey }
}

/// 設定の「タブバー」。載せる画面を選び、並べ替える。
struct TabBarSettingsView: View {
    @AppStorage(TabBarSettings.storageKey) private var raw: String = ""

    private var tabs: [String] { TabBarSettings.normalized(TabBarSettings.keys(raw)) }
    private var choices: [NavItem] {
        tabBarChoices(lyricsAvailable: LyricsFeature.isAvailable, assistantAvailable: TabBarSettings.assistantAvailable)
    }
    private var maxCount: Int { Int(maxTabBarCount()) }

    private func item(_ key: String) -> NavItem? { choices.first { $0.analyticsKey == key } }

    private func save(_ keys: [String]) {
        raw = TabBarSettings.normalized(keys).joined(separator: ",")
    }

    var body: some View {
        List {
            ImasListSection("タブバー", count: "\(tabs.count) / \(maxCount)",
                            footer: "プロデュースは外せません (設定と、タブから外した画面の入口があるため)。外した画面はプロデュースの「そのほか」から開けます。") {
                ForEach(tabs, id: \.self) { key in
                    if let item = item(key) {
                        ImasRow(title: item.label,
                                leading: .icon(item.destination.systemImage, tone: .neutral),
                                density: .compact)
                            .deleteDisabled(item.destination == .produce)
                    }
                }
                .onMove { from, to in
                    var next = tabs
                    next.move(fromOffsets: from, toOffset: to)
                    save(next)
                }
                .onDelete { offsets in
                    var next = tabs
                    next.remove(atOffsets: offsets)
                    save(next)
                }
            }

            let rest = choices.filter { !tabs.contains($0.analyticsKey) }
            if !rest.isEmpty {
                ImasListSection("追加できる画面",
                                footer: tabs.count >= maxCount ? "タブバーは \(maxCount) つまでです。追加するには先にどれかを外してください。" : nil) {
                    ForEach(rest, id: \.analyticsKey) { item in
                        Button {
                            save(tabs + [item.analyticsKey])
                        } label: {
                            ImasRow(title: item.label,
                                    leading: .icon(item.destination.systemImage, tone: .neutral),
                                    trailing: .value("追加"),
                                    density: .compact)
                        }
                        .buttonStyle(.plain)
                        .disabled(tabs.count >= maxCount)
                        .opacity(tabs.count >= maxCount ? 0.45 : 1)
                        .accessibilityLabel("\(item.label)をタブバーに追加")
                    }
                }
            }

            ImasListSection {
                ImasActionRow(title: "最初の並びに戻す", systemImage: "arrow.counterclockwise") { raw = "" }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle("タブバー")
        .navigationBarTitleDisplayMode(.inline)
    }
}
