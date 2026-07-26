import SwiftUI

/// 楽曲詳細の「情報・歌唱」タブ。披露/回収の統計、楽曲情報、歌唱アイドル、関連楽曲。
///
/// 親の状態は触らない。画面遷移は `navigate`、タブ切り替えを伴う操作 (参加ライブ登録)
/// だけ `onRequestAttendPicker` で親へ返す。
struct SongInfoTab: View {
    @Environment(\.colorScheme) private var scheme

    let song: Song
    let seed: String?
    let vm: DetailSheetViewModel
    let navigate: (DetailDestination) -> Void
    /// 「参加ライブを登録して現地回収」を押した。どこへ誘導するかは親が決める。
    let onRequestAttendPicker: () -> Void

    var body: some View {
        VStack(spacing: DS.sp5) {
            performanceStats
            songInfoSection
            if !vm.originalArtists.isEmpty {
                IdolGridSection(title: "歌唱アイドル", idols: vm.originalArtists, navigate: navigate)
            }
            if !vm.performerArtists.isEmpty {
                IdolGridSection(title: "ライブ歌唱歴", idols: vm.performerArtists, navigate: navigate)
            }
            if !vm.relatedSongs.isEmpty { relatedSongsSection }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    // MARK: - 披露 / 現地回収

    private var performanceStats: some View {
        VStack(spacing: DS.sp4) {
            HStack(spacing: DS.sp3) {
                ImasStatTile(systemImage: "mic.fill", value: "\(vm.history.count)", unit: "回", label: "披露回数", seed: seed)
                ImasStatTile(systemImage: "checkmark.seal.fill", value: "\(vm.collectedShows.count)", unit: "公演", label: "現地回収", seed: seed)
            }
            Button {
                AppAnalytics.tap("song_detail.register_attendance")
                onRequestAttendPicker()
            } label: {
                Label("参加ライブを登録して現地回収", systemImage: "plus")
                    .font(.imasSubhead.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.sp4)
                    .foregroundStyle(DS.ink2)
                    .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }
            .buttonStyle(.plain)

            if !vm.collectedShows.isEmpty {
                ImasListContainer {
                    ForEach(Array(vm.collectedShows.enumerated()), id: \.element.id) { idx, show in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5) }
                        Button { navigate(.show(show.asShow)) } label: {
                            collectedRow(show)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func collectedRow(_ show: ShowWithEventName) -> some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.imasScaled( 15, weight: .semibold))
                .foregroundStyle(DS.success)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(eventDisplayName(show.eventName)).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Text([show.name, show.date].joined(separator: " ・ "))
                    .font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            ImasRowChevron()
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - 楽曲情報

    private var songInfoSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "楽曲情報", tight: true)
            ImasListContainer {
                infoRows
            }
        }
    }

    @ViewBuilder
    private var infoRows: some View {
        let rows = vm.infoRows(for: song)
        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
            if idx > 0 { ImasRowDivider(inset: DS.sp5) }
            infoRow(row)
        }
    }

    /// VM が組み立てた宣言的モデル (SongInfoRow) を実際の行に描画する。
    @ViewBuilder
    private func infoRow(_ row: SongInfoRow) -> some View {
        switch row.kind {
        case .plain(let value, let mono):
            ImasLabeledRow(key: row.key, value: value, mono: mono, seed: seed)
        case .navigate(let value, let destination):
            Button { navigate(destination) } label: {
                ImasLabeledRow(key: row.key, value: value, showChevron: true, tappable: true, seed: seed)
            }
            .buttonStyle(.plain)
        case .credit(let names):
            creditRow(key: row.key, names: names)
        case .unit(let value, let unitId):
            Button {
                Task { if let unit = await vm.resolveUnit(id: unitId) { navigate(.unit(unit)) } }
            } label: {
                ImasLabeledRow(key: row.key, value: value, showChevron: true, tappable: true, seed: seed)
            }
            .buttonStyle(.plain)
        }
    }

    /// クレジット行: 分割済みの名前を各クリエイター絞り込みへタップ可能に表示する。
    private func creditRow(key: String, names: [String]) -> some View {
        HStack(spacing: DS.sp4) {
            Text(key).font(.imasSubhead).foregroundStyle(DS.ink2)
            Spacer(minLength: 12)
            HStack(spacing: DS.sp2) {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    if idx > 0 { Text("/").font(.imasSubhead).foregroundStyle(DS.ink3) }
                    Button { navigate(.filteredSongs(.creator(name))) } label: {
                        Text(name).font(.imasSubhead)
                            .foregroundStyle(ImasTheme.derive(seed: seed, scheme: scheme).accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
        .background(DS.surface)
    }

    // MARK: - 関連楽曲

    /// 同じシリーズ・ユニット・歌唱アイドルでつながる曲 (ローカル算出)。
    private var relatedSongsSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "関連楽曲", count: "\(vm.relatedSongs.count)")
            ImasListContainer {
                ForEach(Array(vm.relatedSongs.enumerated()), id: \.element.id) { idx, s in
                    if idx > 0 { ImasRowDivider(inset: DS.sp5 + 44) }
                    Button { navigate(.song(s)) } label: { RelatedSongRow(song: s, seed: seed) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}
