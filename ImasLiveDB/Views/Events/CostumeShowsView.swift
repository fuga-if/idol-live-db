import os
import SwiftUI

/// 衣装 1 着を「どの公演で着たか」で引く画面。
///
/// イベントをまたいで着用公演を並べる (リ・プロローグ・X なら 10th の Act-1/2/4)。
/// イベントごとに束ね、イベントは新しい順・中の公演は DAY1 → DAY2 の順。
/// 束ね方と並び、曲名の 1 行は imas-core の `costume_events` が決めている。
struct CostumeShowsView: View {
    let costume: CostumeRecord
    let navigate: (DetailDestination) -> Void

    @State private var events: [CostumeEventRecord] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ImasLoadingState()
            } else {
                content
            }
        }
        .background(DS.bg)
        .navigationTitle(costume.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .trackScreen("costume_shows")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.screen) {
                header
                ForEach(events, id: \.eventId) { event in
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        ImasSectionHeader(event.eventName, style: .small)
                        ImasCardList {
                            ForEach(Array(event.shows.enumerated()), id: \.element.showId) { index, show in
                                if index > 0 { ImasRowDivider(inset: DS.Space.screen) }
                                showRow(show)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.top, DS.Space.card)
            .padding(.bottom, DS.Space.section)
        }
        .readableContentMargins()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            Text(costume.name).imasText(.heroTitle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.gap) {
                if let attribution = costume.attribution {
                    ImasBadge(text: attribution, kind: .unit)
                }
                Text("\(costume.showCount) 公演で着用").imasText(.value, color: DS.ink2)
            }
        }
    }

    private func showRow(_ show: CostumeShowRecord) -> some View {
        Button {
            Task { await open(showId: show.showId) }
        } label: {
            // 曲名の並び (songsLabel) は副題 (1 行固定) ではなく detail に置き、全文を折り返す。
            ImasRow(
                title: show.showName,
                trailing: .custom(AnyView(
                    HStack(spacing: DS.Space.gap) {
                        Text(show.date).font(ImasTextRole.value.font.monospacedDigit()).foregroundStyle(DS.ink2)
                        ImasRowChevron()
                    }
                )),
                density: .compact,
                titleLineLimit: 1,
                titleRole: .rowLabel
            ) {
                if let songs = show.songsLabel {
                    Text(songs).imasText(.meta).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.imasRow)
    }

    private func open(showId: String) async {
        do {
            if let show = try await AppContainer.shared.showReading.show(id: showId) {
                navigate(.show(show))
            }
        } catch {
            Logger.database.error("load_failed costume_show: \(error.localizedDescription)")
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            events = try await AppContainer.shared.showReading.costumeEvents(costumeId: costume.id)
        } catch {
            Logger.database.error("load_failed costume_events: \(error.localizedDescription)")
        }
    }
}
