import SwiftUI

extension CalendarEntry {
    /// カテゴリ装飾テーマ seed 群 (hex)。固有色を持たないエンティティ種別の帯/チップ色を
    /// `ImasTheme.derive(seed:scheme:)` 経由で導出するための固定シード
    /// (生の SwiftUI システムカラーではなく DS の導出エンジンを通す)。
    enum ThemeSeed {
        /// 公演 (絞り込み chip の代表色。iOS system blue 相当)。
        static let show = "#3E6DD6"
        /// 事務員誕生日 (iOS system pink 相当)。
        static let staffBirthday = "#FF2D55"
        /// ブランド記念日 (iOS system teal 相当)。
        static let anniversary = "#30B0C7"
        /// チケット関連 (受付期間・当落発表) (iOS system indigo 相当)。
        static let ticket = "#5856D6"
    }

    /// カレンダーのドットに使うエンティティ色。
    /// 公演=ブランド色 / リリース=橙 (DS.warning) / 誕生日=アイドル色 or テーマ導出ピンク。
    func accentColor(scheme: ColorScheme) -> Color {
        switch self {
        case .show(let row):
            return Color(hexString: row.brandColor, default: DS.sys)
        case .release:
            return DS.warning
        case .birthday(let idol, _):
            return Color(hexString: idol.color, default: ImasTheme.derive(seed: ThemeSeed.staffBirthday, scheme: scheme).accent)
        case .staffBirthday:
            // 事務員は固有色が無いので汎用桃 (アイドル誕生日と同じ色域、ロウ寄り)。
            return ImasTheme.derive(seed: ThemeSeed.staffBirthday, scheme: scheme).accent
        case .anniversary:
            // 記念日は祝祭色: ティール (公演=ブランド色 / リリース=橙 / 誕生日=桃 と被らない色域)。
            return ImasTheme.derive(seed: ThemeSeed.anniversary, scheme: scheme).accent
        case .personal(let event):
            return event.color
        case .ticket(let row):
            // 申込締切=赤(緊急) / 当落発表・アーカイブ終了=藍。公演(ブランド色)・リリース(橙)・誕生日(桃)と被らない色域。
            return row.kind == .deadline ? DS.danger : ImasTheme.derive(seed: ThemeSeed.ticket, scheme: scheme).accent
        }
    }

    /// accentColor の帯/チップの上に乗せる前景色。
    /// ブランド色・アイドル色は黄色 (#F5C900 系) や白系など明るい色が普通に存在するため、
    /// 白文字固定にせず WCAG コントラストで黒/白を自動選択する。
    func accentInk(scheme: ColorScheme) -> Color {
        ColorMath.onColor(accentColor(scheme: scheme))
    }
}
