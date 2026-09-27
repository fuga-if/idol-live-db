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
            VStack(alignment: .leading, spacing: DS.sp5) {
                header
                ForEach(events, id: \.eventId) { event in
                    VStack(alignment: .leading, spacing: DS.sp2) {
                        ImasSectionHeader(title: event.eventName, tight: true)
                        ImasListContainer {
                            ForEach(Array(event.shows.enumerated()), id: \.element.showId) { index, show in
                                if index > 0 { ImasRowDivider(inset: DS.sp5) }
                                showRow(show)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.top, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
        .readableContentMargins()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            Text(costume.name)
                .font(.imasTitle2.weight(.bold))
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let attribution = costume.attribution {
                    ImasTagChip(text: attribution, kind: .unit)
                }
                Text("\(costume.showCount) 公演で着用")
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
            }
        }
    }

    private func showRow(_ show: CostumeShowRecord) -> some View {
        Button {
            Task { await open(showId: show.showId) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(show.showName)
                            .font(.imasScaled(15, weight: .semibold))
                            .foregroundStyle(DS.ink)
                        Text(show.date)
                            .font(.imasScaled(13).monospacedDigit())
                            .foregroundStyle(DS.ink2)
                    }
                    if let songs = show.songsLabel {
                        Text(songs)
                            .font(.imasScaled(12))
                            .foregroundStyle(DS.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.imasScaled(12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
