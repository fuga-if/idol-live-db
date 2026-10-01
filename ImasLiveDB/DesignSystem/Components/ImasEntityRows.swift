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
// ImasEventRow  半券 (初日)・ライブ名・会場と期間。参加した公演があれば穴
// ImasShowRow   半券 (日付)・公演名・開演と会場。参加した公演は穴
// ImasRecordRow 記号の札・何をしたか・誰がいつ・操作の札 (編集履歴・お知らせ)
// =============================================================================

// MARK: - 曲

struct ImasSongRow<Detail: View>: View {
    let title: String
    var subtitle: String? = nil
    var artworkURL: URL? = nil
    /// ジャケが無いときの面とリードバーの色 (ブランドの hex)。
    var brandHex: String? = nil
    /// 自分が現地で聴いた曲 (ジャケの角に判子)。
    var isCollected: Bool = false
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
            leading: .artwork(title: title, brand: brandHex, imageURL: artworkURL, isCollected: isCollected),
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
    init(song: Song, subtitle: String? = nil, isCollected: Bool = false, trailing: ImasRowTrailing = .none,
         density: ImasRowDensity = .regular, emphasis: ImasRowEmphasis = .normal) {
        self.init(
            title: song.title,
            subtitle: subtitle ?? song.unitName ?? song.singerLabel,
            artworkURL: song.artworkUrl.flatMap(URL.init(string:)),
            brandHex: BrandColors.hex(for: song.brandId),
            isCollected: isCollected,
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            detail: { EmptyView() }
        )
    }
}

extension ImasSongRow {
    /// 曲のデータから組み、下段 (札・日付) を足す。
    init(song: Song, subtitle: String? = nil, isCollected: Bool = false, trailing: ImasRowTrailing = .none,
         density: ImasRowDensity = .regular, emphasis: ImasRowEmphasis = .normal,
         @ViewBuilder detail: () -> Detail) {
        self.init(
            title: song.title,
            subtitle: subtitle ?? song.unitName ?? song.singerLabel,
            artworkURL: song.artworkUrl.flatMap(URL.init(string:)),
            brandHex: BrandColors.hex(for: song.brandId),
            isCollected: isCollected,
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

/// ライブ 1 件の行。半券の形 (左に初日、右にライブ名と日付・会場)。参加した公演があれば穴が開く。
struct ImasEventRow<Detail: View>: View {
    let event: Event
    /// 初日 (`yyyy-MM-dd`)。半券の日付欄に出す。
    var date: String? = nil
    /// 会場・期間 (「Kアリーナ横浜 · 〜 11/8 (日)」)。
    var subtitle: String? = nil
    var isPunched: Bool = false
    var badges: [ImasBadgeSpec] = []
    var emphasis: ImasRowEmphasis = .normal
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasStubRow(date: date.map(ImasStubDate.init) ?? ImasStubDate(top: "", big: "—", bottom: ""),
                    title: eventDisplayName(event.name), subtitle: subtitle,
                    brand: BrandColors.hex(for: event.brandId), isPunched: isPunched, badges: badges,
                    emphasis: emphasis) { detail }
            .imasCopyable(event.name, label: "ライブ名をコピー", key: "event_name")
    }
}

extension ImasEventRow where Detail == EmptyView {
    init(event: Event, date: String? = nil, subtitle: String? = nil, isPunched: Bool = false,
         badges: [ImasBadgeSpec] = [], emphasis: ImasRowEmphasis = .normal) {
        self.init(event: event, date: date, subtitle: subtitle, isPunched: isPunched, badges: badges,
                  emphasis: emphasis) { EmptyView() }
    }
}

// MARK: - 公演

/// 公演 1 件の行。半券の形 (左に日付、右に公演名と開演・会場)。参加した公演は穴が開く。
struct ImasShowRow<Detail: View>: View {
    /// 公演の日 (`yyyy-MM-dd`)。
    let date: String
    /// 公演名 (DAY1 など)。
    let title: String
    /// 開演・会場・出演者数。
    var subtitle: String? = nil
    var brandHex: String? = nil
    var isPunched: Bool = false
    var badges: [ImasBadgeSpec] = []
    var emphasis: ImasRowEmphasis = .normal
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasStubRow(date: ImasStubDate(date), title: title, subtitle: subtitle, brand: brandHex,
                    isPunched: isPunched, badges: badges, emphasis: emphasis) { detail }
    }
}

extension ImasShowRow where Detail == EmptyView {
    init(date: String, title: String, subtitle: String? = nil, brandHex: String? = nil, isPunched: Bool = false,
         badges: [ImasBadgeSpec] = [], emphasis: ImasRowEmphasis = .normal) {
        self.init(date: date, title: title, subtitle: subtitle, brandHex: brandHex, isPunched: isPunched,
                  badges: badges, emphasis: emphasis) { EmptyView() }
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
