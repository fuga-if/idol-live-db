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
    /// サーバ上の公開状態。"published" / "draft"。
    ///
    /// draft はサーバが admin にしか返さない。JASRAC の許諾が下りるまで一般ユーザーに
    /// 配信できないが、開発中のプレビューは必要なため。判定はサーバ側で行っており、
    /// ビルド種別 (DEBUG) では切っていない — クライアントの自己申告は信用できないので。
    /// 旧サーバは status を返さないので optional。
    let status: String?

    /// 未公開 (下書き) か。画面に明示して、公開済みと取り違えないようにする。
    var isDraft: Bool { status == "draft" }

    /// 表示すべき本文行が 1 行でもあるか (マーカー/空行しか無い場合は「歌詞なし」扱い)。
    var hasContent: Bool { lines.contains { $0.kind == .lyric && !$0.text.isEmpty } }
}

extension Lyrics {
    private enum CodingKeys: String, CodingKey {
        case songId, source, updatedAt, lines, status
    }

    /// 単体取得 (`/songs/{id}/lyrics`) は `songId` を含むが、束ね取得
    /// (`/songs/{id}/detail`) の入れ子は含まない形もありうる。欠けていても落とさず
    /// 空文字で受け、束ね側が `resolvingSongId(_:)` で補う。
    ///
    /// ⚠️ `init(from:)` は**必ず extension 側に置く**こと。型本体に書くとメンバーワイズ
    /// イニシャライザが消え、`resolvingSongId` / フェイク実装が組み立てられなくなる。
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            songId: try c.decodeIfPresent(String.self, forKey: .songId) ?? "",
            source: try c.decodeIfPresent(String.self, forKey: .source),
            updatedAt: try c.decodeIfPresent(Int.self, forKey: .updatedAt),
            lines: try c.decodeIfPresent([LyricLine].self, forKey: .lines) ?? [],
            status: try c.decodeIfPresent(String.self, forKey: .status)
        )
    }

    /// `songId` が空 (束ねの入れ子で省略された) なら曲 ID を補った複製を返す。
    func resolvingSongId(_ id: String) -> Lyrics {
        songId.isEmpty
            ? Lyrics(songId: id, source: source, updatedAt: updatedAt,
                     lines: lines, status: status)
            : self
    }
}
