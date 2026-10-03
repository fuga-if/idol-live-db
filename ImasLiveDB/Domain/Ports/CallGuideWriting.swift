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

    /// 歌詞行の再生位置を置き換える (`PUT /songs/{song_id}/timings`)。曲全体の全置換。
    ///
    /// ⚠️ 歌詞本文は送らない (`LyricTimingPayload` の注記参照)。
    func updateLyricTimings(songId: String, lines: [LyricTimingPayload.Line],
                            calls: [LyricTimingPayload.Line]) async throws

    /// 歌詞行の「ここ好き」を付け外しする (`PUT|DELETE /songs/{id}/lyric-likes/{line_id}`)。
    /// - Returns: 付け外し後のその行の人数 (みんなの分)。
    func setLyricLike(songId: String, lineId: String, liked: Bool) async throws -> Int

    /// 歌詞行のパート分け (誰が歌うか) を置き換える (`PUT /songs/{id}/parts`)。曲全体の全置換。
    func updateLyricParts(songId: String, lines: [LyricPartsPayload.Line]) async throws

    /// 歌詞の行をくっつける / 切り離す (`POST /songs/{id}/lyric-structure`)。文字は変わらない。
    func editLyricStructure(songId: String, _ change: LyricStructurePayload) async throws
}
