import SwiftUI

// =============================================================================
// 実体ごとの行 (docs/DESIGN_SYSTEM.md §5.1〜§5.5・§5.14)
//
// 同じ実体はアプリ中どこでも同じ行で出す。中身は `ImasRow` の枠を実体のデータで埋めたもの。
// 画面ごとの足し算 (並べ替えの根拠・印・下段の札) は trailing と detail で渡す。
//
// ImasSongRow   ジャケ・曲名・歌唱者
// ImasIdolRow   アバター (担当は二重輪)・名前・ブランドと CV
// ImasUnitRow   ユニットのアバター・ユニット名・メンバー
// ImasEventRow  リードバー (ブランド・合同は縞)・ライブ名・日付と会場
// ImasShowRow   リードバー・公演名・日付と会場と開演
// ImasRecordRow 記号の札・何をしたか・誰がいつ・操作の札 (編集履歴・お知らせ)
// =============================================================================

// MARK: - 曲

struct ImasSongRow<Detail: View>: View {
    let title: String
    var subtitle: String? = nil
    var artworkURL: URL? = nil
    /// ジャケが無いときの面とリードバーの色 (ブランドの hex)。
    var brandHex: String? = nil
    var trailing: ImasRowTrailing = .none
    var density: ImasRowDensity = .regular
    var emphasis: ImasRowEmphasis = .normal
    /// 絞り込みで当たった所に色を敷いた曲名。
    var attributedTitle: AttributedString? = nil
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: .artwork(title: title, brand: brandHex, imageURL: artworkURL),
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            titleLineLimit: density == .compact ? 1 : 2,
            attributedTitle: attributedTitle,
            detail: { detail }
        )
    }
}

extension ImasSongRow where Detail == EmptyView {
    /// 曲のデータから組む。副題は既定でユニット名 (無ければ歌唱者の表記)。
    init(song: Song, subtitle: String? = nil, trailing: ImasRowTrailing = .none,
         density: ImasRowDensity = .regular, emphasis: ImasRowEmphasis = .normal) {
        self.init(
            title: song.title,
            subtitle: subtitle ?? song.unitName ?? song.singerLabel,
            artworkURL: song.artworkUrl.flatMap(URL.init(string:)),
            brandHex: BrandColors.hex(for: song.brandId),
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            detail: { EmptyView() }
        )
    }
}

extension ImasSongRow {
    /// 曲のデータから組み、下段 (札・日付) を足す。
    init(song: Song, subtitle: String? = nil, trailing: ImasRowTrailing = .none,
         density: ImasRowDensity = .regular, emphasis: ImasRowEmphasis = .normal,
         @ViewBuilder detail: () -> Detail) {
        self.init(
            title: song.title,
            subtitle: subtitle ?? song.unitName ?? song.singerLabel,
            artworkURL: song.artworkUrl.flatMap(URL.init(string:)),
            brandHex: BrandColors.hex(for: song.brandId),
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            detail: detail
        )
    }
}

// MARK: - アイドル

struct ImasIdolRow: View {
    let idol: Idol
    /// 既定はブランドの略称。CV を足すなどは呼び出し側で組んで渡す。
    var subtitle: String? = nil
    var isPick: Bool = false
    var trailing: ImasRowTrailing = .none
    var density: ImasRowDensity = .regular

    @State private var imageService = CustomImageService.shared

    var body: some View {
        ImasRow(
            title: idol.name,
            subtitle: subtitle,
            leading: .avatar(label: idol.shortName, seed: idol.color,
                             imageURL: imageService.imageURL(for: idol.id), isPick: isPick),
            trailing: trailing,
            density: density,
            titleLineLimit: 1
        )
        .imasCopyable([CopyItem("アイドル名をコピー", idol.name, key: "idol_name"),
                       CopyItem("よみをコピー", idol.nameKana, key: "kana")])
    }
}

// MARK: - ユニット

struct ImasUnitRow: View {
    let unit: Unit
    /// メンバー (3 人まで + 「ほか N 人」) など。
    var subtitle: String? = nil
    var trailing: ImasRowTrailing = .none
    var density: ImasRowDensity = .regular

    var body: some View {
        let size = density.avatarSize
        ImasRow(
            title: unit.displayName,
            subtitle: subtitle,
            leading: .custom(AnyView(UnitAvatarView(unit: unit, size: size)), width: size),
            trailing: trailing,
            density: density,
            titleLineLimit: 1
        )
    }
}

// MARK: - ライブ

struct ImasEventRow<Detail: View>: View {
    let event: Event
    /// 日付と会場 (「11月7日(土)〜8日(日) · Kアリーナ横浜」)。
    var subtitle: String? = nil
    var trailing: ImasRowTrailing = .none
    var emphasis: ImasRowEmphasis = .normal
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasRow(
            title: eventDisplayName(event.name),
            subtitle: subtitle,
            leading: .bar(brand: BrandColors.hex(for: event.brandId), rainbow: !event.jointBrandIdList.isEmpty),
            trailing: trailing,
            emphasis: emphasis,
            detail: { detail }
        )
        .imasCopyable(event.name, label: "ライブ名をコピー", key: "event_name")
    }
}

extension ImasEventRow where Detail == EmptyView {
    init(event: Event, subtitle: String? = nil, trailing: ImasRowTrailing = .none,
         emphasis: ImasRowEmphasis = .normal) {
        self.init(event: event, subtitle: subtitle, trailing: trailing, emphasis: emphasis) { EmptyView() }
    }
}

// MARK: - 公演

struct ImasShowRow<Detail: View>: View {
    /// 公演名 (DAY1 など)。
    let title: String
    /// 日付・会場・開演。
    var subtitle: String? = nil
    var brandHex: String? = nil
    var rainbow: Bool = false
    var trailing: ImasRowTrailing = .none
    var emphasis: ImasRowEmphasis = .normal
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: .bar(brand: brandHex, rainbow: rainbow),
            trailing: trailing,
            emphasis: emphasis,
            detail: { detail }
        )
    }
}

extension ImasShowRow where Detail == EmptyView {
    init(title: String, subtitle: String? = nil, brandHex: String? = nil, rainbow: Bool = false,
         trailing: ImasRowTrailing = .none, emphasis: ImasRowEmphasis = .normal) {
        self.init(title: title, subtitle: subtitle, brandHex: brandHex, rainbow: rainbow,
                  trailing: trailing, emphasis: emphasis) { EmptyView() }
    }
}

// MARK: - 記録

/// 編集履歴・お知らせ・支出など「何かが起きた記録」の行。
struct ImasRecordRow: View {
    let systemImage: String
    var tone: ImasIconTile.Tone = .neutral
    /// 何をしたか (「THE IDOLM@STER の歌唱者を直した」)。
    let title: String
    /// 誰が・いつ (「よ〜だ · 3分前」)。
    var subtitle: String? = nil
    /// 操作の札 (追加・変更・削除・差し戻し)。
    var badges: [ImasBadgeSpec] = []
    var trailing: ImasRowTrailing = .none

    var body: some View {
        ImasRow(title: title, subtitle: subtitle, leading: .icon(systemImage, tone: tone), trailing: trailing) {
            if !badges.isEmpty {
                HStack(spacing: DS.Space.gapTight) {
                    ForEach(badges) { b in ImasBadge(text: b.text, kind: b.kind, seed: b.seed) }
                }
            }
        }
    }
}
