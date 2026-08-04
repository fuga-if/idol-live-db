import Foundation

// =============================================================================
// 歌詞モデル (メモリ専用)
//
// ⚠️ JASRAC 許諾の条件により「ユーザが一括ダウンロードできない形式での配信」が必須。
// このため歌詞はプロセス内メモリ以外のどこにも保持してはならない:
//   - GRDB (master.sqlite / Documents DB) / SwiftData / UserDefaults / App Group
//   - バックアップ (BackupExportImportService / UserMarkBackup)
//   - 共有画像 (ShareCardScaffold) / ウィジェットブリッジ
//
// それを型で担保するため、この 2 型は意図的に
//   * GRDB の `FetchableRecord` / `PersistableRecord` に準拠しない
//     (準拠していれば誰かが `insert(db)` を書けてしまう)
//   * `Encodable` にも準拠しない
//     (JSONEncoder / PropertyListEncoder に渡せないので書き出し経路が塞がる)
// としてある。**この 2 点は絶対に緩めないこと。**
// =============================================================================

/// 歌詞 1 行の種別。
///
/// サーバが将来新しい種別を足しても壊れないよう、未知の値は本文 (`lyric`) として扱う。
enum LyricLineKind: String, Sendable, Hashable {
    /// 歌詞本文。
    case lyric
    /// 「イントロ」「間奏」等の構成マーカー (歌詞ではない)。
    case marker
    /// 意図的な空行 (ブロック区切り)。
    case blank
}

extension LyricLineKind: Decodable {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LyricLineKind(rawValue: raw) ?? .lyric
    }
}

/// 歌詞 1 行。
struct LyricLine: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    /// 表示順 (サーバ側で昇順に並んで来るが、明示的に持つ)。
    let ord: Int
    let kind: LyricLineKind
    let text: String
    /// 「1番」「サビ」等の所属セクション名。無ければ nil。
    let section: String?
    /// 再生位置 (ms)。将来の再生連動用で現状サーバは常に null を返すが、
    /// 値を返し始めてもデコードが壊れないよう `Int?` で受ける。
    let startMs: Int?
}

/// 1 曲分の歌詞。
struct Lyrics: Decodable, Sendable, Hashable {
    let songId: String
    /// 出典表記 (JASRAC 許諾表示等)。
    let source: String?
    /// サーバ側の最終更新時刻 (epoch 秒)。
    let updatedAt: Int?
    let lines: [LyricLine]

    /// 表示すべき本文行が 1 行でもあるか (マーカー/空行しか無い場合は「歌詞なし」扱い)。
    var hasContent: Bool { lines.contains { $0.kind == .lyric && !$0.text.isEmpty } }
}
