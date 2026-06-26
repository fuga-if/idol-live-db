import SwiftUI

/// 楽曲一覧の 1 行 (新デザインシステム移植版)。
///
/// 構成: ImasLeadBar(ブランド) + ArtworkImageView(実ジャケ×ソリッドフォールバック, プレビュー対応)
///       + 曲名 + [歌唱者 StackedAvatars + ユニット/演者ラベル]
///       + マイマーク行 (リリース日 / 担当♥ / メモ / 現地回収✓) + ★お気に入りトグル。
///
/// 実ジャケと「画像なし=ソリッド面+曲名」が同列で違和感なく並ぶよう、ArtworkImageView に
/// ブランド色 seed を渡してフォールバックをテーマ色で表現する。
struct SongRowView: View {
    let item: SongWithArtists
    /// 現地回収 N 回 (参加ライブで披露された回数)。 0 / nil なら非表示。
    var collectedCount: Int? = nil
    /// お気に入りマーク
    var isFavorite: Bool = false
    /// 担当アイドルが歌唱者にいる (歌唱アイドル ∩ 担当 ≠ 空)
    var isMyPick: Bool = false
    /// メモがある
    var hasNote: Bool = false
    /// 現地回収バッジをタップしたとき (楽曲詳細の披露履歴へ飛ばす導線)。
    var onCollectedTap: (() -> Void)? = nil
    /// タグ絞り込み中、その曲に付いたタグ票数。nil で非表示。
    var tagVoteCount: Int? = nil

    private var song: Song { item.song }

    /// フォールバック (画像なし) と行頭リードバーに使うブランド色 hex。
    private var brandHex: String? { Self.brandColorHex(for: song.brandId) }

    private var artworkURL: URL? {
        guard let dbUrl = song.artworkUrl else { return nil }
        return URL(string: dbUrl)
    }

    private var previewURL: URL? {
        guard let dbUrl = song.previewUrl else { return nil }
        return URL(string: dbUrl)
    }

    /// 表示用ラベル: ユニット名/全体名 (あれば) を優先、無ければアイドル個別名連結。
    /// - song.unitName が DB にあればそれ
    /// - artistNames が "MILLIONSTARS（...）" 形式ならカッコ前を抜き出し (全体曲・ユニット名カッコ表記対応)
    /// - 落ちる場合は performerIdols の名前を「・」で繋ぐ
    private var displayLabel: String {
        if let unit = song.unitName, !unit.isEmpty { return unit }
        let label = item.artistNames
        if !label.isEmpty {
            for sep in ["（", "("] {
                if let idx = label.firstIndex(of: Character(sep)) {
                    let prefix = label[..<idx].trimmingCharacters(in: .whitespaces)
                    if !prefix.isEmpty { return prefix }
                }
            }
        }
        return item.performerIdols.map(\.name).joined(separator: "・")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 行頭の控えめなブランド色マーカー (集約 = 細いリードバー)。
            ImasLeadBar(brand: brandHex)
                .frame(height: 50)

            // 実ジャケ × ソリッドフォールバック (プレビュー再生対応)。
            ArtworkImageView(
                url: artworkURL,
                size: 50,
                previewURL: previewURL,
                songTitle: song.title,
                seed: brandHex
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(.imasHeadline.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if let tagVoteCount {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill").font(.imasScaled( 9, weight: .bold))
                            Text("\(tagVoteCount)").font(.imasCaption.weight(.bold)).monospacedDigit()
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }

                performerLine

                markRow
            }
            .padding(.top, 1)

            Spacer(minLength: 0)

            FavoriteToggleButton(entity: .song, id: song.id)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 歌唱者 + ユニット/演者ラベル

    @ViewBuilder
    private var performerLine: some View {
        if !item.performerIdols.isEmpty {
            HStack(spacing: 7) {
                StackedAvatars(idols: item.performerIdols, maxVisible: 4, size: 22)
                Text(displayLabel)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
        } else if !item.artistNames.isEmpty {
            Text(item.artistNames)
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
        }
    }

    // MARK: - マイマーク (リリース日 / 担当♥ / メモ / 現地回収✓)

    @ViewBuilder
    private var markRow: some View {
        if hasAnyMark {
            HStack(spacing: 8) {
                if let date = song.releaseDate {
                    Text(date)
                        .font(.imasDisplay(11, weight: .regular))
                        .foregroundStyle(DS.ink3)
                }
                if isMyPick {
                    Label("担当", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.imasScaled( 11, weight: .semibold))
                        .foregroundStyle(DS.pick)
                }
                if hasNote {
                    Image(systemName: "pencil")
                        .font(.imasScaled( 11, weight: .semibold))
                        .foregroundStyle(DS.warning)
                }
                if let count = collectedCount, count > 0 {
                    let badge = HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                        Text("\(count)").font(.imasDisplay(11, weight: .bold))
                    }
                    .font(.imasScaled( 11, weight: .semibold))
                    .foregroundStyle(DS.success)
                    if let onCollectedTap {
                        Button(action: onCollectedTap) { badge.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                    } else {
                        badge
                    }
                }
            }
        }
    }

    private var hasAnyMark: Bool {
        song.releaseDate != nil || isMyPick || hasNote || (collectedCount ?? 0) > 0
    }

    // MARK: - Brand color

    /// ブランド ID → イメージカラー hex。 リードバーとジャケフォールバックの seed に使う。
    static func brandColorHex(for brandId: String?) -> String? {
        BrandPalette.hex(for: brandId)
    }
}
