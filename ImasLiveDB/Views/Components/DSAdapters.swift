import SwiftUI

// =============================================================================
// アプリのモデルから DesignSystem の部品へ写す口。
//
// DesignSystem はアプリのサービス (CustomImageService など) を知らない。画像の在り処や
// 色の引き方のようなアプリ側の事情はここで 1 回だけ解決し、画面は部品にモデルを渡すだけにする。
// =============================================================================

// MARK: - ブランド

extension ImasBrandPicker.Option {
    /// ブランドから。読み込んだロゴがあればロゴ、無ければペンライト。
    @MainActor init(brand: Brand) {
        self.init(id: brand.id, label: brand.shortName, color: brand.color,
                  logoURL: CustomImageService.shared.brandImageURL(for: brand.id))
    }
}

extension ImasBrandPicker {
    /// ブランドの並びから組む。
    @MainActor init(brands: [Brand], selection: Binding<Set<String>>, includesAll: Bool = true,
                    allLabel: String = "全て", allowsMultiple: Bool = true) {
        self.init(options: brands.map { ImasBrandPicker.Option(brand: $0) }, selection: selection,
                  includesAll: includesAll, allLabel: allLabel, allowsMultiple: allowsMultiple)
    }
}

// MARK: - 曲

extension ImasSongRow {
    /// 曲の試聴 URL から、試聴の配線一式 (`previewURL`/`isPreviewing`/`onPreviewTap`) を組む。
    /// 楽曲一覧の行 (`SongRowView`) と同じ配線をここ 1 箇所にまとめ、`song:` から組む
    /// 呼び出し全部 (曲名表示の統一行・お気に入り一覧・タグ詳細など) に自動で効かせる。
    @MainActor private static func previewWiring(for song: Song) -> (URL?, Bool, () -> Void) {
        let previewURL = URL.safeHTTP(string: song.previewUrl)
        let isPreviewing = MusicKitService.shared.isPlaying(songId: song.id)
        let onPreviewTap = {
            if let previewURL { MusicKitService.shared.togglePreview(url: previewURL, songId: song.id) }
        }
        return (previewURL, isPreviewing, onPreviewTap)
    }

    /// 曲の長押しコピー (曲名・よみ・歌唱者)。`song:` から組む行はいつもこれを持つ。
    private static func copyItems(for song: Song) -> [CopyItem] {
        [
            CopyItem("曲名をコピー", song.title, key: "song_title"),
            CopyItem("よみをコピー", song.titleKana, key: "kana"),
            CopyItem("歌唱者をコピー", song.singerLabel, key: "artists"),
        ]
    }
}

extension ImasSongRow where Detail == EmptyView {
    /// 曲のデータから組む。副題は既定でユニット名 (無ければ歌唱者の表記)。
    /// ジャケの試聴と長押しコピーを自動で持つ (楽曲一覧の行と同じ配線)。
    /// `playsPreview: false` で試聴だけ切る行 (ジャケを押しても行全体のタップが効く。
    /// 集計の行など、ジャケを押すたびに詳細シートが開いてほしい画面で使う)。長押しコピーは残る。
    @MainActor init(song: Song, subtitle: String? = nil, isCollected: Bool = false, showsBrandBar: Bool = false,
                    playsPreview: Bool = true,
                    trailing: ImasRowTrailing = .none, density: ImasRowDensity = .regular, emphasis: ImasRowEmphasis = .normal) {
        let (previewURL, isPreviewing, onPreviewTap) = playsPreview ? Self.previewWiring(for: song) : (nil, false, {})
        self.init(
            title: song.title,
            subtitle: subtitle ?? song.unitName ?? song.singerLabel,
            artworkURL: song.artworkUrl.flatMap(URL.init(string:)),
            brandHex: BrandColors.hex(for: song.brandId),
            isCollected: isCollected,
            showsBrandBar: showsBrandBar,
            previewURL: previewURL,
            isPreviewing: isPreviewing,
            onPreviewTap: onPreviewTap,
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            copyItems: Self.copyItems(for: song),
            detail: { EmptyView() }
        )
    }
}

extension ImasSongRow {
    /// 曲のデータから組み、下段 (札・日付) を足す。試聴・長押しコピーは上と同じく自動配線。
    @MainActor init(song: Song, subtitle: String? = nil, isCollected: Bool = false, showsBrandBar: Bool = false,
                    playsPreview: Bool = true,
                    trailing: ImasRowTrailing = .none, density: ImasRowDensity = .regular, emphasis: ImasRowEmphasis = .normal,
                    @ViewBuilder detail: () -> Detail) {
        let (previewURL, isPreviewing, onPreviewTap) = playsPreview ? Self.previewWiring(for: song) : (nil, false, {})
        self.init(
            title: song.title,
            subtitle: subtitle ?? song.unitName ?? song.singerLabel,
            artworkURL: song.artworkUrl.flatMap(URL.init(string:)),
            brandHex: BrandColors.hex(for: song.brandId),
            isCollected: isCollected,
            showsBrandBar: showsBrandBar,
            previewURL: previewURL,
            isPreviewing: isPreviewing,
            onPreviewTap: onPreviewTap,
            trailing: trailing,
            density: density,
            emphasis: emphasis,
            copyItems: Self.copyItems(for: song),
            detail: detail
        )
    }
}

// MARK: - アイドル

extension ImasIdolCell {
    /// アイドルから。アイコンは写真を設定した子は写真、無ければ略称の判子。担当は輪が二重になる。
    /// `metric` は並べ替えの値 (何順に並んでいるか)。
    @MainActor init(idol: Idol, isPick: Bool, metric: String? = nil, showsKana: Bool = false,
                    isSelected: Bool? = nil) {
        self.init(name: idol.name, kana: showsKana ? idol.nameKana : nil, seed: idol.color,
                  brand: BrandColors.hex(for: idol.brandId), iconLabel: idol.shortName,
                  imageURL: CustomImageService.shared.imageURL(for: idol.id),
                  isPick: isPick, metric: metric, isSelected: isSelected)
    }
}
