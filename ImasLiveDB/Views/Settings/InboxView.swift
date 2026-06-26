import SwiftUI

/// お知らせ受信箱。新機能告知などを既読フラグ付きで一覧表示する。
struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = AnnouncementStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if AnnouncementCatalog.all.isEmpty {
                    ContentUnavailableView("お知らせはありません", systemImage: "bell.slash")
                } else {
                    List {
                        ForEach(AnnouncementCatalog.all) { a in
                            NavigationLink {
                                AnnouncementDetailView(announcement: a)
                            } label: {
                                row(a)
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DS.bg)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .trackScreen("inbox")
        }
    }

    private func row(_ a: Announcement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.icon)
                .font(.imasTitle3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(a.tint.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !store.isRead(a.id) {
                        Circle().fill(a.tint).frame(width: 8, height: 8)
                    }
                    Text(a.title)
                        .font(.imasHeadline)
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                }
                Text(a.summary)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(2)
                Text(a.date)
                    .font(.imasScaled(11))
                    .foregroundStyle(DS.ink3)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AnnouncementDetailView: View {
    let announcement: Announcement
    @State private var store = AnnouncementStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: announcement.icon)
                    .font(.imasScaled(40, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(announcement.tint.gradient, in: RoundedRectangle(cornerRadius: 19))

                VStack(alignment: .leading, spacing: 4) {
                    Text(announcement.title).font(.imasTitle2)
                    Text(announcement.date).font(.imasCaption).foregroundStyle(DS.ink2)
                }

                ForEach(Array(announcement.body.enumerated()), id: \.offset) { _, para in
                    Text(para)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if announcement.link == .widgetHowTo {
                    NavigationLink {
                        WidgetHowToView()
                    } label: {
                        Label("使い方を見る", systemImage: "arrow.right.circle.fill")
                            .font(.imasHeadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(announcement.tint.gradient, in: RoundedRectangle(cornerRadius: DS.rMD))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle("お知らせ")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.markRead(announcement.id) }
    }
}
