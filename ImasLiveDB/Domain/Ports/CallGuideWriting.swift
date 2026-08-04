import Foundation

/// コールガイド (歌詞行に紐づくコール / 手拍子指示) の書き込みポート。
///
/// 読み取りは歌詞と同じ経路 (`SongDetailReading` の束ね) に同梱されて届くので、
/// ここは書き込みだけを持つ。
protocol CallGuideWriting: Sendable {
    /// 指定した行のコール指定を置き換える (`PUT /songs/{song_id}/calls`)。
    ///
    /// - Parameter lines: 変更のあった行だけでよい。`calls` が空 かつ `clap` が nil の行は
    ///   「その行のコール指定を消す」意味になる。
    ///
    /// ⚠️ 歌詞本文は送らない (`CallGuidePayload` の注記参照)。
    func updateCallGuide(songId: String, lines: [CallGuidePayload.Line]) async throws
}
