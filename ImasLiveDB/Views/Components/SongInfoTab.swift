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
    /// 曲の補足 (直接反映した直後の値を含む、親が決めた表示値)。
    var note: String? = nil
    /// 補足を書く・直す導線。編集導線を出さない状態なら nil (ボタンを出さない)。
    var onEditNote: (() -> Void)? = nil
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
            if !vm.variantSongs.isEmpty { variantSongsSection }
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
            ImasButton(title: "参加ライブを登録して現地回収", systemImage: "plus", role: .secondary, size: .medium,
                      fillsWidth: true) {
                AppAnalytics.tap("song_detail.register_attendance")
                onRequestAttendPicker()
            }

            if !vm.collectedShows.isEmpty {
                ImasCardList {
                    ForEach(Array(vm.collectedShows.enumerated()), id: \.element.id) { idx, show in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5) }
                        Button { navigate(.show(show.asShow)) } label: {
                            collectedRow(show)
                        }
                        .buttonStyle(.imasRow)
                    }
                }
            }
        }
    }

    private func collectedRow(_ show: ShowWithEventName) -> some View {
        ImasRow(
            title: eventDisplayName(show.eventName),
            subtitle: [show.name, show.date].joined(separator: " ・ "),
            leading: .icon("checkmark.seal.fill", tone: .positive),
            trailing: .chevron,
            density: .compact
        )
    }

    // MARK: - 楽曲情報

    private var songInfoSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "楽曲情報", tight: true)
            ImasCardList {
                infoRows
            }
            noteEntry
        }
    }

    /// 補足。ある曲は「この曲の補足」として本文を主役に見せ、直す導線は右上に小さく添える。
    /// 無い曲だけ、利用者の投稿で増やしたいので「補足を書く」を例付きで置く。
    @ViewBuilder
    private var noteEntry: some View {
        if let note {
            ImasCard {
                VStack(alignment: .leading, spacing: DS.sp2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("この曲の補足").imasText(.sectionLabel)
                        Spacer(minLength: 8)
                        if let onEditNote {
                            Button("直す", action: onEditNote)
                                .font(.imasCaption.weight(.semibold))
                                .accessibilityLabel("補足を直す")
                        }
                    }
                    Text(note)
                        .imasText(.value)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        } else if let onEditNote {
            Button(action: onEditNote) {
                ImasEntryCard(
                    systemImage: "text.bubble",
                    title: "補足を書く",
                    preview: "「◯周年記念楽曲」「アニメ◯話の挿入歌」など、この曲の由来を 1 文で",
                    seed: seed
                )
            }
            .buttonStyle(.imasPress)
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
            ImasValueRow(key: row.key, value: value, monospaced: mono)
        case .navigate(let value, let destination):
            Button { navigate(destination) } label: {
                ImasValueRow(key: row.key, value: value, isLink: true)
            }
            .buttonStyle(.imasRow)
        case .credit(let names):
            creditRow(key: row.key, names: names)
        case .unit(let value, let unitId):
            Button {
                Task { if let unit = await vm.resolveUnit(id: unitId) { navigate(.unit(unit)) } }
            } label: {
                ImasValueRow(key: row.key, value: value, isLink: true)
            }
            .buttonStyle(.imasRow)
        }
    }

    /// クレジット行: 分割済みの名前を各クリエイター絞り込みへタップ可能に表示する。
    /// 複数名が独立してタップできる行は `ImasValueRow` では表現できないため据え置き
    /// (寸法だけ DS のトークンに揃える)。
    private func creditRow(key: String, names: [String]) -> some View {
        HStack(spacing: DS.Space.rowGap) {
            Text(key).imasText(.value, color: DS.ink2)
            Spacer(minLength: DS.Space.rowGap)
            HStack(spacing: DS.Space.gapTight) {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    if idx > 0 { Text("/").imasText(.value, color: DS.ink3) }
                    Button { navigate(.filteredSongs(.creator(name))) } label: {
                        Text(name).imasText(.value, color: ImasTheme.derive(seed: seed, scheme: scheme).accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowV)
        .frame(minHeight: DS.Size.touch)
    }

    // MARK: - 別バージョン

    /// 同じ曲のソロ Ver. / Remix 等。
    ///
    /// 一覧・カレンダー・統計は `parent_song_id IS NULL` で派生曲を隠しているので、
    /// ここが**唯一の到達手段**になる。関連楽曲 (別の曲) とは意味が違うので節を分ける。
    private var variantSongsSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "別バージョン", count: "\(vm.variantSongs.count)")
            ImasCardList {
                ForEach(Array(vm.variantSongs.enumerated()), id: \.element.id) { idx, s in
                    if idx > 0 { ImasRowDivider(inset: DS.sp5 + 44) }
                    Button { navigate(.song(s)) } label: { RelatedSongRow(song: s, seed: seed) }
                        .buttonStyle(.imasRow)
                }
            }
        }
    }

    // MARK: - 関連楽曲

    /// 同じシリーズ・ユニット・歌唱アイドルでつながる曲 (ローカル算出)。
    private var relatedSongsSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "関連楽曲", count: "\(vm.relatedSongs.count)")
            ImasCardList {
                ForEach(Array(vm.relatedSongs.enumerated()), id: \.element.id) { idx, s in
                    if idx > 0 { ImasRowDivider(inset: DS.sp5 + 44) }
                    Button { navigate(.song(s)) } label: { RelatedSongRow(song: s, seed: seed) }
                        .buttonStyle(.imasRow)
                }
            }
        }
    }
}
