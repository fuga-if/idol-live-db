import SwiftUI

/// タグ付けの盛り上がり (GET /tags/activity)。「最近つけられたタグ」「伸びてるタグ」
/// 「タグが急増中の曲・アイドル」を横断表示し、タグ付けのモチベーションにつなげる。
struct TagActivityView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme

    @State private var activity: TagActivityResponse?
    @State private var songCache: [String: Song] = [:]
    @State private var idolCache: [String: Idol] = [:]
    @State private var isLoading = true
    @State private var nextDestination: DetailDestination?
    @State private var domainTab: Int = 0

    private var selectedDomain: TagActivityDomain { domainTab == 0 ? .song : .idol }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.sp6) {
                if isLoading {
                    ImasInlineLoading()
                } else if let activity, !activity.trendingTags.isEmpty || !activity.risingEntities.isEmpty || !activity.recent.isEmpty {
                    domainPicker
                    let trends = activity.trendingTags.filter { $0.domain == selectedDomain }
                    let rises = activity.risingEntities.filter { $0.domain == selectedDomain }
                    let events = activity.recent.filter { $0.domain == selectedDomain }
                    if trends.isEmpty && rises.isEmpty && events.isEmpty {
                        ImasEmptyState(
                            systemImage: "tag",
                            title: "まだ動きがありません",
                            message: selectedDomain == .song ? "曲にタグを付けると、ここに反映されます。" : "アイドルにタグを付けると、ここに反映されます。"
                        )
                        .padding(.top, DS.sp6)
                    } else {
                        trendingSection(trends)
                        risingSection(rises)
                        recentSection(events)
                    }
                } else {
                    ImasEmptyState(
                        systemImage: "tag",
                        title: "まだ動きがありません",
                        message: "タグを付けると、ここに反映されます。"
                    )
                    .padding(.top, DS.sp6)
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.top, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("タグの動き")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $nextDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .task { await load() }
        .refreshable { await load() }
        .trackScreen("tag_activity")
    }

    private var domainPicker: some View {
        ImasSegmented(labels: ["曲", "アイドル"], selection: $domainTab)
    }

    // MARK: - 伸びてるタグ

    private func trendingSection(_ trends: [TagActivityTrend]) -> some View {
        Group {
            if !trends.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "伸びてるタグ", tight: true)
                    ImasListContainer {
                        ForEach(Array(trends.enumerated()), id: \.element.id) { idx, trend in
                            if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                            trendRow(trend, rank: idx + 1)
                        }
                    }
                }
            }
        }
    }

    private func trendRow(_ trend: TagActivityTrend, rank: Int) -> some View {
        NavigationLink {
            tagDestination(for: trend.domain, tagId: trend.tagId, tagName: trend.tagName)
        } label: {
            HStack(spacing: DS.sp3) {
                TagRankBadge(rank: rank)
                if let color = trend.tagColor {
                    Circle().fill(Color(hexColor: color)).frame(width: 10, height: 10)
                }
                Text(trend.tagName)
                    .font(.imasBody.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("直近\(trend.recentCount)件")
                        .font(.imasFootnote.weight(.semibold))
                        .foregroundStyle(DS.ink)
                    Text("累計\(trend.totalCount)")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                }
                Image(systemName: "chevron.right")
                    .font(.imasScaled(13, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 急上昇中の曲・アイドル

    private func risingSection(_ rises: [TagActivityRise]) -> some View {
        Group {
            if !rises.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "タグが急増中", tight: true)
                    ImasListContainer {
                        ForEach(Array(rises.enumerated()), id: \.element.id) { idx, rise in
                            if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                            riseRow(rise)
                        }
                    }
                }
            }
        }
    }

    private func riseRow(_ rise: TagActivityRise) -> some View {
        Button {
            openEntity(domain: rise.domain, entityId: rise.entityId)
        } label: {
            HStack(spacing: DS.sp3) {
                entityLead(domain: rise.domain, entityId: rise.entityId)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entityName(domain: rise.domain, entityId: rise.entityId))
                        .font(.imasBody.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("「\(rise.tagName)」")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right")
                        .font(.imasScaled(11, weight: .bold))
                    Text("\(rise.recentCount)件")
                        .font(.imasFootnote.weight(.bold))
                }
                .foregroundStyle(DS.favorite)
                Image(systemName: "chevron.right")
                    .font(.imasScaled(13, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entityResolved(domain: rise.domain, entityId: rise.entityId))
    }

    // MARK: - 最近つけられたタグ

    private func recentSection(_ events: [TagActivityEvent]) -> some View {
        Group {
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "最近つけられたタグ", tight: true)
                    ImasListContainer {
                        ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                            if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                            recentRow(event)
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ event: TagActivityEvent) -> some View {
        Button {
            openEntity(domain: event.domain, entityId: event.entityId)
        } label: {
            HStack(spacing: DS.sp3) {
                entityLead(domain: event.domain, entityId: event.entityId)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entityName(domain: event.domain, entityId: event.entityId))
                        .font(.imasBody.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    Text("「\(event.tagName)」タグが付きました")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(relativeTime(event.createdAt))
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entityResolved(domain: event.domain, entityId: event.entityId))
    }

    // MARK: - Entity resolution (song_id/idol_id → ローカル DB)

    @ViewBuilder
    private func entityLead(domain: TagActivityDomain, entityId: String) -> some View {
        switch domain {
        case .song:
            if let song = songCache[entityId] {
                ImasArtwork(title: song.title, seed: nil, size: 40, imageURL: song.artworkUrl.flatMap(URL.init))
            } else {
                ImasArtwork(title: "?", size: 40)
            }
        case .idol:
            if let idol = idolCache[entityId] {
                ImasAvatar(label: idol.name, seed: idol.color, brand: idol.brandId, size: 40)
            } else {
                ImasAvatar(label: "?", size: 40)
            }
        }
    }

    private func entityName(domain: TagActivityDomain, entityId: String) -> String {
        switch domain {
        case .song: return songCache[entityId]?.title ?? "曲を読み込み中"
        case .idol: return idolCache[entityId]?.name ?? "アイドルを読み込み中"
        }
    }

    private func entityResolved(domain: TagActivityDomain, entityId: String) -> Bool {
        switch domain {
        case .song: return songCache[entityId] != nil
        case .idol: return idolCache[entityId] != nil
        }
    }

    private func openEntity(domain: TagActivityDomain, entityId: String) {
        switch domain {
        case .song:
            guard let song = songCache[entityId] else { return }
            nextDestination = .song(song)
        case .idol:
            guard let idol = idolCache[entityId] else { return }
            nextDestination = .idol(idol)
        }
    }

    @ViewBuilder
    private func tagDestination(for domain: TagActivityDomain, tagId: String, tagName: String) -> some View {
        switch domain {
        case .song: TagDetailView(tagId: tagId, tagName: tagName)
        case .idol: IdolTagDetailView(tagId: tagId, tagName: tagName)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Load

    private func load() async {
        isLoading = songCache.isEmpty && idolCache.isEmpty
        defer { isLoading = false }
        guard let response = try? await AppContainer.shared.communityTagReading.tagActivity(windowDays: 7) else { return }
        activity = response

        var songIds = Set<String>()
        var idolIds = Set<String>()
        for e in response.recent {
            if e.domain == .song { songIds.insert(e.entityId) } else { idolIds.insert(e.entityId) }
        }
        for r in response.risingEntities {
            if r.domain == .song { songIds.insert(r.entityId) } else { idolIds.insert(r.entityId) }
        }
        songIds.subtract(songCache.keys)
        idolIds.subtract(idolCache.keys)

        if !songIds.isEmpty, let fetched = try? await AppContainer.shared.songReading.songs(ids: Array(songIds)) {
            for song in fetched { songCache[song.id] = song }
        }
        if !idolIds.isEmpty, let fetched = try? await AppContainer.shared.idolReading.idols(ids: Array(idolIds)) {
            for idol in fetched { idolCache[idol.id] = idol }
        }
    }
}
