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
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    HStack(spacing: DS.Space.gapTight) {
                        ImasSectionHeader("映像円盤", style: .small)
                        Spacer()
                        Text("\(ownedIds.count)/\(releases.count) 所有").imasText(.eyebrow)
                    }
                    .padding(.horizontal, DS.Space.screen)

                    ImasCardList {
                        ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                            if index > 0 { ImasRowDivider(inset: 72) }
                            releaseRow(release, theme: t)
                        }
                    }
                    .padding(.horizontal, DS.Space.screen)

                    ImasNote("持っている円盤に印を付けられます。")
                        .padding(.horizontal, DS.Space.screen)
                }
            }
        }
        .task { await load() }
    }

    private func releaseRow(_ release: EventRelease, theme t: ImasTheme) -> some View {
        let owned = ownedIds.contains(release.id)
        return HStack(spacing: DS.Space.gap) {
            ImasArtwork(title: release.title, size: 52,
                       imageURL: release.jacketUrl.flatMap(URL.init(string:)),
                       fallbackSystemImage: "opticaldisc")

            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(release.title).imasText(.rowTitle).lineLimit(2)
                HStack(spacing: DS.Space.gap) {
                    Text(release.productTypeEnum.label).imasText(.eyebrow, color: t.accent)
                    if let date = release.releaseDate, !date.isEmpty {
                        Text(date).imasText(.meta)
                    }
                    if let cat = release.catalogNumber, !cat.isEmpty {
                        Text(cat).font(ImasTextRole.meta.font.monospacedDigit()).foregroundStyle(DS.ink3)
                    }
                }
                if let urlStr = release.purchaseUrl, let url = URL.safeHTTP(string: urlStr) {
                    Button { openURL(url) } label: {
                        HStack(spacing: DS.Space.gapTight) {
                            Image(systemName: "cart")
                            Text("購入ページ")
                        }
                        .font(ImasTextRole.badge.font)
                        .foregroundStyle(t.accent)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer(minLength: DS.Space.gapTight)

            // 所有トグル。アイコンは `UserMarkKind.owned` の見た目を直参照する
            // (ここで独自に決め打つと、KAMISABI カード所持と二重管理になって食い違う)。
            Button { toggleOwned(release) } label: {
                VStack(spacing: DS.Space.gapTight) {
                    Image(systemName: owned ? UserMarkKind.owned.activeIcon : UserMarkKind.owned.icon)
                        .font(.imasTitle3)
                    Text(owned ? "所有" : "未所有").imasText(.badge, color: owned ? t.accent : DS.ink3)
                }
                .foregroundStyle(owned ? t.accent : DS.ink3)
                .frame(width: 52)
                .contentShape(Rectangle())
                .accessibilityLabel(owned ? "\(release.title) を所有から外す" : "\(release.title) を所有に追加")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.Space.card)
        .padding(.vertical, DS.Space.gap)
    }

    private func load() async {
        let list = (try? await AppContainer.shared.eventReading.eventReleases(eventId: eventId)) ?? []
        releases = list
        ownedIds = Set(list.filter { markService.bool(.owned, entity: .release, id: $0.id) }.map(\.id))
    }

    private func toggleOwned(_ release: EventRelease) {
        let now = !ownedIds.contains(release.id)
        AppAnalytics.tap("event_release.toggle_owned")
        do {
            try markService.setBool(.owned, entity: .release, id: release.id, value: now)
        } catch {
            LocalWriteFailure.report(error, action: "所有の記録")
        }
        if now { ownedIds.insert(release.id) } else { ownedIds.remove(release.id) }
    }
}
