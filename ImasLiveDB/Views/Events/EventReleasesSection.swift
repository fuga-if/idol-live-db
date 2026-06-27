import SwiftUI

/// イベントの映像円盤 (Blu-ray / DVD) 所有チェックセクション。
/// `event_releases` にレコードがあるイベントだけ表示する (無ければ何も描かない = データ駆動)。
/// 所有フラグは user_marks(entity=release, kind=owned) に保存。
struct EventReleasesSection: View {
    let eventId: String
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var releases: [EventRelease] = []
    /// 所有中の release.id。トグルでローカル更新 + 永続化。
    @State private var ownedIds: Set<String> = []

    private let markService = UserMarkService.shared

    var body: some View {
        Group {
            if !releases.isEmpty {
                let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
                VStack(alignment: .leading, spacing: DS.sp3) {
                    HStack(spacing: 6) {
                        ImasSectionHeader(title: "映像円盤", tight: true)
                        Spacer()
                        Text("\(ownedIds.count)/\(releases.count) 所有")
                            .font(.imasCaption.weight(.semibold))
                            .foregroundStyle(DS.ink2)
                    }
                    .padding(.horizontal, DS.sp5)

                    ImasListContainer {
                        ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                            if index > 0 { Divider().overlay(DS.sep).padding(.leading, 72) }
                            releaseRow(release, theme: t)
                        }
                    }
                    .padding(.horizontal, DS.sp5)

                    Text("持っている円盤に印を付けられます。")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                        .padding(.horizontal, DS.sp5)
                }
            }
        }
        .task { await load() }
    }

    private func releaseRow(_ release: EventRelease, theme t: ImasTheme) -> some View {
        let owned = ownedIds.contains(release.id)
        return HStack(spacing: DS.sp3) {
            jacket(release)

            VStack(alignment: .leading, spacing: 3) {
                Text(release.title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(release.productTypeEnum.label)
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(t.accent)
                    if let date = release.releaseDate, !date.isEmpty {
                        Text(date).font(.imasCaption).foregroundStyle(DS.ink3)
                    }
                    if let cat = release.catalogNumber, !cat.isEmpty {
                        Text(cat).font(.imasCaption.monospacedDigit()).foregroundStyle(DS.ink3)
                    }
                }
                if let urlStr = release.purchaseUrl, let url = URL.safeHTTP(string: urlStr) {
                    Button { openURL(url) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cart").font(.imasScaled(10, weight: .semibold))
                            Text("購入ページ").font(.imasScaled(11, weight: .semibold))
                        }
                        .foregroundStyle(t.accent)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer(minLength: 4)

            // 所有トグル
            Button { toggleOwned(release) } label: {
                VStack(spacing: 2) {
                    Image(systemName: owned ? "opticaldisc.fill" : "opticaldisc")
                        .font(.imasTitle3)
                    Text(owned ? "所有" : "未所有")
                        .font(.imasScaled(10, weight: .semibold))
                }
                .foregroundStyle(owned ? t.accent : DS.ink3)
                .frame(width: 52)
                .contentShape(Rectangle())
                .accessibilityLabel(owned ? "\(release.title) を所有から外す" : "\(release.title) を所有に追加")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
    }

    @ViewBuilder
    private func jacket(_ release: EventRelease) -> some View {
        let url = release.jacketUrl.flatMap { URL(string: $0) }
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    DS.fill
                    Image(systemName: "opticaldisc")
                        .font(.imasTitle3)
                        .foregroundStyle(DS.ink3)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
    }

    private func load() async {
        let list = (try? AppDatabase.shared.fetchEventReleases(eventId: eventId)) ?? []
        releases = list
        ownedIds = Set(list.filter { markService.bool(.owned, entity: .release, id: $0.id) }.map(\.id))
    }

    private func toggleOwned(_ release: EventRelease) {
        let now = !ownedIds.contains(release.id)
        AppAnalytics.tap("event_release.toggle_owned")
        try? markService.setBool(.owned, entity: .release, id: release.id, value: now)
        if now { ownedIds.insert(release.id) } else { ownedIds.remove(release.id) }
    }
}
