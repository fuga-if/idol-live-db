import SwiftUI

/// お知らせ受信箱。新機能告知などを既読フラグ付きで一覧表示する。
struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = AnnouncementStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if AnnouncementCatalog.all.isEmpty {
                    ImasEmptyState(systemImage: "bell.slash", title: "お知らせはありません")
                } else {
                    List {
                        ImasListSection {
                            ForEach(AnnouncementCatalog.all) { a in
                                NavigationLink {
                                    AnnouncementDetailView(announcement: a)
                                } label: {
                                    row(a)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .imasForm()
                }
            }
            .navigationTitle("お知らせ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("すべて既読") {
                        AppAnalytics.tap("inbox.mark_all_read")
                        store.markAllRead()
                    }
                    .disabled(store.unreadCount == 0)
                }
            }
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .trackScreen("inbox")
        }
    }

    private func row(_ a: Announcement) -> some View {
        let hex = ColorMath.hexString(from: a.tint)
        return ImasRow(
            title: a.title,
            subtitle: a.summary,
            leading: .icon(a.icon, tone: .themed, seed: hex),
            trailing: store.isRead(a.id) ? .none : .custom(AnyView(
                ImasSwatch(hex: hex, size: .dot, isDecorative: true)
            )),
            titleRole: .rowTitle
        ) {
            Text(a.date).imasText(.meta)
        }
    }
}

private struct AnnouncementDetailView: View {
    let announcement: Announcement
    @State private var store = AnnouncementStore.shared
    @State private var showWidgetHowTo = false

    var body: some View {
        let hex = ColorMath.hexString(from: announcement.tint)
        ImasPage {
            VStack(alignment: .leading, spacing: DS.Space.card) {
                ImasIconTile(systemImage: announcement.icon, size: .s56, tone: .themed, seed: hex)

                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    Text(announcement.title).imasText(.sectionTitle)
                    Text(announcement.date).imasText(.meta)
                }

                ImasProse(blocks: announcement.body.map { .paragraph($0) })

                if announcement.link == .widgetHowTo {
                    Button {
                        showWidgetHowTo = true
                    } label: {
                        Label("使い方を見る", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.imas(.primary, size: .large))
                }
            }
        }
        .navigationTitle("お知らせ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showWidgetHowTo) { WidgetHowToView() }
        .task { store.markRead(announcement.id) }
    }
}
