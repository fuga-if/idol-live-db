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
// それを型で担保するため、このファイルの型 (`Lyrics` / `LyricLine` / `LyricCall`) は意図的に
//   * GRDB の `FetchableRecord` / `PersistableRecord` に準拠しない
//     (準拠していれば誰かが `insert(db)` を書けてしまう)
//   * `Encodable` にも準拠しない
//     (JSONEncoder / PropertyListEncoder に渡せないので書き出し経路が塞がる)
// としてある。**この 2 点は絶対に緩めないこと。**
//
// コールガイドの保存 (`PUT /songs/{id}/calls`) で送信が要るが、そのために
// `Encodable` を付けてはならない。歌詞本文を持たない専用の送信型
// `Models/CallGuidePayload.swift` に詰め替えて送ること。
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

/// 行頭に付く手拍子の指示。コール表の慣習に合わせた記号で示す。
///
/// `none` は「Optional の nil」と紛らわしいので Swift 側は `noCall` と呼ぶ
/// (`LyricClap?` の文脈で `.none` と書くと nil と区別が付かなくなる)。
enum LyricClap: String, Sendable, Hashable, CaseIterable {
    /// 裏拍 (★)。
    case backBeat = "back_beat"
    /// 4 つ打ち (■)。
    case fourOnFloor = "four_on_floor"
    /// PPPH (♠)。
    case ppph
    /// コールなし (♥)。「指示が無い」ではなく「声を出さない」という積極的な指示。
    case noCall = "none"

    /// コール表で使われている記号。
    var symbol: String {
        switch self {
        case .backBeat:    return "★"
        case .fourOnFloor: return "■"
        case .ppph:        return "♠"
        case .noCall:      return "♥"
        }
    }

    var label: String {
        switch self {
        case .backBeat:    return "裏拍"
        case .fourOnFloor: return "4つ打ち"
        case .ppph:        return "PPPH"
        case .noCall:      return "コールなし"
        }
    }
}

/// コールの強調度。凡例に出すのは「実際に使われているものだけ」(曲ごとに凡例が違う)。
enum CallEmphasis: String, Sendable, Hashable, CaseIterable {
    /// 通常。凡例には出さない。
    case normal
    /// おこのみで (緑)。
    case optional
    /// 演者要望 (赤)。
    case performerRequest = "performer_request"

    var label: String {
        switch self {
        case .normal:           return "通常"
        case .optional:         return "おこのみで"
        case .performerRequest: return "演者要望"
        }
    }
}

extension CallEmphasis: Decodable {
    /// 未知の強調度はサーバ側の新機能なので、落とさず `normal` に倒す。
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CallEmphasis(rawValue: raw) ?? .normal
    }
}

/// 歌詞行の一部 (アンカー) に紐づくコール 1 件。
///
/// ⚠️ `anchorText` は歌詞の一部を含む。`Lyrics` / `LyricLine` と同じく
/// **Encodable / GRDB には準拠させない** (Models/Lyrics.swift 冒頭の注記参照)。
/// サーバへ送るときは専用の送信型 `CallGuidePayload` に詰め替えること。
struct LyricCall: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    /// アンカー開始位置。行内の **Unicode スカラー単位**のオフセット
    /// (UTF-16 の `NSRange` ではない。絵文字・結合文字でズレる)。
    var start: Int
    /// アンカー終了位置 (排他)。同じくスカラー単位。
    var end: Int
    /// アンカーした歌詞の断片。歌詞が編集された時のズレ検出に使う。
    var anchorText: String
    /// コール文言。自由テキスト (繰り返し `× 26` 等も文言に含む)。
    var text: String
    var emphasis: CallEmphasis
    /// 歌詞が編集されてアンカーがズレた印。編集画面で目立たせる。
    var stale: Bool?

    var isStale: Bool { stale == true }

    /// アンカーを持たない (歌詞のない) コールか。`kind == .marker` の行に付くコールは
    /// start/end が 0 で来る。
    var hasAnchor: Bool { end > start }
}

extension LyricCall {
    private enum CodingKeys: String, CodingKey {
        case id, start, end, anchorText, text, emphasis, stale
    }

    /// 欠けたフィールドに耐える。Worker とアプリの配信タイミングがズレても、
    /// コール 1 件の形が古いだけで歌詞全体を落とさないため。
    ///
    /// ⚠️ `init(from:)` は必ず extension 側に置くこと (メンバーワイズ初期化子を残すため)。
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            start: try c.decodeIfPresent(Int.self, forKey: .start) ?? 0,
            end: try c.decodeIfPresent(Int.self, forKey: .end) ?? 0,
            anchorText: try c.decodeIfPresent(String.self, forKey: .anchorText) ?? "",
            text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
            emphasis: try c.decodeIfPresent(CallEmphasis.self, forKey: .emphasis) ?? .normal,
            stale: try c.decodeIfPresent(Bool.self, forKey: .stale)
        )
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
    /// 行頭に出す手拍子の指示。無指定は nil。
    var clap: LyricClap?
    /// この行に紐づくコール。**配列順が表示順**なので並べ替えないこと
    /// (同一アンカーに複数のコールが並ぶことがある)。
    var calls: [LyricCall]
}

extension LyricLine {
    private enum CodingKeys: String, CodingKey {
        case id, ord, kind, text, section, startMs, clap, calls
    }

    /// `clap` / `calls` は後から足したフィールドなので、返さない Worker でも壊れない。
    /// 未知の `clap` 値 (サーバが種類を増やした) も nil に倒して落とさない。
    ///
    /// ⚠️ `init(from:)` は必ず extension 側に置くこと (メンバーワイズ初期化子を残すため)。
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            ord: try c.decodeIfPresent(Int.self, forKey: .ord) ?? 0,
            kind: try c.decodeIfPresent(LyricLineKind.self, forKey: .kind) ?? .lyric,
            text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
            section: try c.decodeIfPresent(String.self, forKey: .section),
            startMs: try c.decodeIfPresent(Int.self, forKey: .startMs),
            clap: (try? c.decodeIfPresent(String.self, forKey: .clap)).flatMap { $0 }
                .flatMap(LyricClap.init(rawValue:)),
            calls: (try? c.decodeIfPresent([LyricCall].self, forKey: .calls)).flatMap { $0 } ?? []
        )
    }
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

    /// コールが 1 件でも付いているか (= この歌詞タブがコールガイドとして機能するか)。
    var hasCalls: Bool { lines.contains { !$0.calls.isEmpty } }

    /// この曲で**実際に使われている**強調度 (`normal` を除く)。凡例はここからだけ作る
    /// — 実物のコール表と同じく、曲ごとに凡例の中身が変わる。
    var usedEmphases: [CallEmphasis] {
        let used = Set(lines.flatMap(\.calls).map(\.emphasis))
        return CallEmphasis.allCases.filter { $0 != .normal && used.contains($0) }
    }

    /// この曲で実際に使われている手拍子指示。凡例用。
    var usedClaps: [LyricClap] {
        let used = Set(lines.compactMap(\.clap))
        return LyricClap.allCases.filter { used.contains($0) }
    }
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
