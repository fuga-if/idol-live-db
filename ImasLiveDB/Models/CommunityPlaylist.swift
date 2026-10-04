import Foundation

/// みんなのプレイリスト 1 つ (ユーザー投稿)。曲は id の並びだけ。作者名は持たない。
struct CommunityPlaylist: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String?
    /// 一覧では先頭の数曲だけ (ジャケを並べる分)。1 つ取りでは全曲。
    let songIds: [String]
    let songCount: Int
    let createdAt: String
    let updatedAt: String
    /// 自分が公開したものか (自分の分を取ったときだけ付く)。
    let isOwn: Bool?
}

struct CommunityPlaylistPage: Decodable, Sendable {
    let playlists: [CommunityPlaylist]
    /// 続きの位置。最後のページなら nil。
    let next: String?
}

/// 公開するときの中身。
struct CommunityPlaylistInput: Encodable, Sendable {
    let title: String
    let description: String?
    let songIds: [String]
}
