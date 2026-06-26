import Foundation

struct IntroGameQuestion: Identifiable, Sendable {
    let id: String
    let title: String
    let brandId: String?
    let appleMusicId: String
    /// Apple Music 未加入ユーザー向けの 30 秒プレビュー再生 URL
    let previewUrl: String?
    let artworkUrl: String?
    let choices: [String]
}
