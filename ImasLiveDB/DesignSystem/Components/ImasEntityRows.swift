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
// ImasEventRow  半券 (初日)・ライブ名・会場と期間
// ImasShowRow   半券 (日付)・公演名・開演と会場
// ImasRecordRow 記号の札・何をしたか・誰がいつ・操作の札 (編集履歴・お知らせ)
// =============================================================================

// MARK: - 曲

struct ImasSongRow<Detail: View>: View {
    let title: String
    var subtitle: String? = nil
    var artworkURL: URL? = nil
    /// ジャケが無いときの面とリードバーの色 (ブランドの hex)。
    var brandHex: String? = nil
    /// 行頭にブランドの色の帯を立てる (楽曲一覧)。
    var showsBrandBar: Bool = false
    /// 試聴できる音源の URL。渡すとジャケのタップが曲詳細への遷移と別に試聴を切り替える
    /// (行全体のタップは呼び出し側の Button/NavigationLink のまま)。
    var previewURL: URL? = nil
    /// いま試聴中か。
    var isPreviewing: Bool = false
    /// ジャケがタップされたとき。`previewURL` が無いときは使わない。
    var onPreviewTap: (() -> Void)? = nil
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
            leading: leading,
            leadBar: showsBrandBar ? ImasRowLeadBar(brand: brandHex) : nil,
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            titleLineLimit: density == .compact ? 1 : 2,
            attributedTitle: attributedTitle,
            detail: { detail }
        )
    }

    /// 試聴に対応する呼び出しだけ、ジャケを `ImasArtwork` 直書きに差し替えて試聴の口を足す
    /// (`ImasRowLeading.artwork` 自体は変えない。試聴を使わない呼び出しは今までどおり)。
    private var leading: ImasRowLeading {
        guard previewURL != nil else {
            return .artwork(title: title, brand: brandHex, imageURL: artworkURL)
        }
        let size = density.artworkSize
        return .custom(AnyView(
            ImasArtwork(title: title, brand: brandHex, size: size, imageURL: artworkURL,
                       previewURL: previewURL, isPreviewing: isPreviewing, onPreview: onPreviewTap)
        ), width: size)
    }
}

// `song:` から組む便利イニシャライザは `Views/Components/DSAdapters.swift` にある
// (試聴の配線に MusicKitService が要るため。DesignSystem はアプリのサービスを知らない)。

// MARK: - アイドル

struct ImasIdolRow<Detail: View>: View {
    let idol: Idol
    /// 既定はブランドの略称。CV を足すなどは呼び出し側で組んで渡す。
    var subtitle: String? = nil
    /// アイドル本人の色が無いときのフォールバック (所属ブランドの色)。
    var brand: String? = nil
    var isPick: Bool = false
    var trailing: ImasRowTrailing = .none
    var density: ImasRowDensity = .regular
    /// 副題の下にもう 1 行足す (CV 併記・並べ替えの根拠など)。
    @ViewBuilder var detail: Detail

    @State private var imageService = CustomImageService.shared

    var body: some View {
        ImasRow(
            title: idol.name,
            subtitle: subtitle,
            leading: .avatar(label: idol.shortName, seed: idol.color, brand: brand,
                             imageURL: imageService.imageURL(for: idol.id), isPick: isPick),
            trailing: trailing,
            density: density,
            titleLineLimit: 1,
            detail: { detail }
        )
    }
}

extension ImasIdolRow where Detail == EmptyView {
    init(idol: Idol, subtitle: String? = nil, brand: String? = nil, isPick: Bool = false,
         trailing: ImasRowTrailing = .none, density: ImasRowDensity = .regular) {
        self.init(idol: idol, subtitle: subtitle, brand: brand, isPick: isPick, trailing: trailing,
                  density: density, detail: { EmptyView() })
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
            leading: .custom(AnyView(ImasUnitAvatar(unit: unit, size: size)), width: size),
            trailing: trailing,
            density: density,
            titleLineLimit: 1
        )
    }
}

// MARK: - ライブ

/// ライブ 1 件の行。半券の形 (左に初日、右にライブ名と日付・会場)。
struct ImasEventRow<Detail: View>: View {
    let event: Event
    /// 初日 (`yyyy-MM-dd`)。半券の日付欄に出す。
    var date: String? = nil
    /// 会場・期間 (「Kアリーナ横浜 · 〜 11/8 (日)」)。
    var subtitle: String? = nil
    var badges: [ImasBadgeSpec] = []
    var emphasis: ImasRowEmphasis = .normal
    /// 合同ライブ (複数ブランド名義) は単色で表せないので、ペンライトを虹色にする。
    var rainbow: Bool = false
    /// 別画面へ進む矢印。`NavigationLink` の中では不要 (既定 false)、`Button` の中では true。
    var showsChevron: Bool = false
    /// 副題の行数。既定は 1 行。会場 + 補足などで長い行は 2 以上にする。
    var subtitleLineLimit: Int = 1
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasStubRow(date: date.map(ImasStubDate.init) ?? ImasStubDate(top: "", big: "—", bottom: ""),
                    title: eventDisplayName(event.name), subtitle: subtitle,
                    brand: BrandColors.hex(for: event.brandId), badges: badges,
                    emphasis: emphasis, rainbow: rainbow, showsChevron: showsChevron,
                    subtitleLineLimit: subtitleLineLimit) { detail }
    }
}

extension ImasEventRow where Detail == EmptyView {
    init(event: Event, date: String? = nil, subtitle: String? = nil,
         badges: [ImasBadgeSpec] = [], emphasis: ImasRowEmphasis = .normal, rainbow: Bool = false,
         showsChevron: Bool = false, subtitleLineLimit: Int = 1) {
        self.init(event: event, date: date, subtitle: subtitle, badges: badges,
                  emphasis: emphasis, rainbow: rainbow, showsChevron: showsChevron,
                  subtitleLineLimit: subtitleLineLimit) { EmptyView() }
    }
}

// MARK: - 公演

/// 公演 1 件の行。半券の形 (左に日付、右に公演名と開演・会場)。
struct ImasShowRow<Detail: View>: View {
    /// 公演の日 (`yyyy-MM-dd`)。
    let date: String
    /// 公演名 (DAY1 など)。
    let title: String
    /// 開演・会場・出演者数。
    var subtitle: String? = nil
    var brandHex: String? = nil
    var badges: [ImasBadgeSpec] = []
    var emphasis: ImasRowEmphasis = .normal
    /// 合同ライブの公演など、単色で表せないとき、ペンライトを虹色にする。
    var rainbow: Bool = false
    /// 別画面へ進む矢印。`NavigationLink` の中では不要 (既定 false)、`Button` の中では true。
    var showsChevron: Bool = false
    /// `detail` の見た目 (チップのボタンなど) に添える読み上げ文言。
    var detailAccessibilityLabel: String? = nil
    /// 副題の行数。既定は 1 行。会場 + 補足などで長い行は 2 にする。
    var subtitleLineLimit: Int = 1
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasStubRow(date: ImasStubDate(date), title: title, subtitle: subtitle, brand: brandHex,
                    badges: badges, emphasis: emphasis, rainbow: rainbow,
                    showsChevron: showsChevron, detailAccessibilityLabel: detailAccessibilityLabel,
                    subtitleLineLimit: subtitleLineLimit) { detail }
    }
}

extension ImasShowRow where Detail == EmptyView {
    init(date: String, title: String, subtitle: String? = nil, brandHex: String? = nil,
         badges: [ImasBadgeSpec] = [], emphasis: ImasRowEmphasis = .normal, rainbow: Bool = false,
         showsChevron: Bool = false, subtitleLineLimit: Int = 1) {
        self.init(date: date, title: title, subtitle: subtitle, brandHex: brandHex,
                  badges: badges, emphasis: emphasis, rainbow: rainbow, showsChevron: showsChevron,
                  subtitleLineLimit: subtitleLineLimit) { EmptyView() }
    }
}

// MARK: - 記録

/// 編集履歴・お知らせ・支出・タグの活動など「何かが起きた記録」の行。
///
/// 先頭は記号 (既定) のほか、`leading:` で渡せばアイドルのアイコンやジャケにもできる。
/// diff の本文など自由な中身を足したいときは `detail:` を渡す (既定は何も足さない)。
struct ImasRecordRow<Detail: View>: View {
    var leading: ImasRowLeading = .none
    /// 何をしたか (「THE IDOLM@STER の歌唱者を直した」)。
    let title: String
    /// 題の行数。長い対象名などを省略したくないときに増やす (既定は他の行と同じ 2 行)。
    var titleLineLimit: Int = 2
    /// 誰が・いつ (「よ〜だ · 3分前」)。
    var subtitle: String? = nil
    /// 操作の札 (追加・変更・削除・差し戻し)。
    var badges: [ImasBadgeSpec] = []
    var trailing: ImasRowTrailing = .none
    @ViewBuilder var detail: Detail

    var body: some View {
        ImasRow(title: title, subtitle: subtitle, leading: leading, trailing: trailing,
                titleLineLimit: titleLineLimit) {
            if !badges.isEmpty {
                HStack(spacing: DS.Space.gapTight) {
                    ForEach(badges) { b in ImasBadge(text: b.text, kind: b.kind, seed: b.seed) }
                }
            }
            detail
        }
    }
}

extension ImasRecordRow where Detail == EmptyView {
    /// 記号 1 つの記録行 (編集履歴・お知らせなど、これまでの既定の形)。
    init(systemImage: String, tone: ImasIconTile.Tone = .neutral, title: String, titleLineLimit: Int = 2,
         subtitle: String? = nil, badges: [ImasBadgeSpec] = [], trailing: ImasRowTrailing = .none) {
        self.init(leading: .icon(systemImage, tone: tone), title: title, titleLineLimit: titleLineLimit,
                  subtitle: subtitle, badges: badges, trailing: trailing, detail: { EmptyView() })
    }

    /// 先頭を記号以外 (アイドルのアイコン・ジャケなど) にしたいとき。
    init(leading: ImasRowLeading, title: String, titleLineLimit: Int = 2, subtitle: String? = nil,
         badges: [ImasBadgeSpec] = [], trailing: ImasRowTrailing = .none) {
        self.init(leading: leading, title: title, titleLineLimit: titleLineLimit, subtitle: subtitle,
                  badges: badges, trailing: trailing, detail: { EmptyView() })
    }
}

extension ImasRecordRow {
    /// 記号 + diff 本文などの自由な中身を足す版。
    init(systemImage: String, tone: ImasIconTile.Tone = .neutral, title: String, titleLineLimit: Int = 2,
         subtitle: String? = nil, badges: [ImasBadgeSpec] = [], trailing: ImasRowTrailing = .none,
         @ViewBuilder detail: () -> Detail) {
        self.init(leading: .icon(systemImage, tone: tone), title: title, titleLineLimit: titleLineLimit,
                  subtitle: subtitle, badges: badges, trailing: trailing, detail: detail)
    }
}
