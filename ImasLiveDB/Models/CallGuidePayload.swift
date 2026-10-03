import Foundation

// =============================================================================
// コールガイド保存 (PUT /songs/{song_id}/calls) の送信型
//
// ⚠️ **歌詞本文は絶対に含めない。** `Lyrics` / `LyricLine` / `LyricCall` に
// `Encodable` を付ければ済む話に見えるが、それをやると JSONEncoder に歌詞まるごとを
// 渡せるようになり、JASRAC 許諾の条件 (一括ダウンロード不可) を型で塞いでいた担保が
// 崩れる。だから「送るぶんだけを持つ別の型」をここに置く。
//
// ここに `text` (行の歌詞) を足さないこと。行は `id` で指せる。
// `anchorText` だけは契約上必須なので載るが、これは 1 コール分の短い断片であって
// 本文ではない (サーバ側で歌詞編集後のズレ検出に使う)。
//
// キーは `APIClient` の `keyEncodingStrategy = .convertToSnakeCase` で
// `anchorText` → `anchor_text` に変換される。ここでは camelCase のままにしておく。
// =============================================================================

/// `PUT /songs/{song_id}/calls` のリクエストボディ。
struct CallGuidePayload: Encodable, Sendable {
    let lines: [Line]

    /// 1 行ぶんの指定。ここに載った行は「この内容で置き換える」。
    /// `calls` が空 かつ `clap` が null なら、その行のコール指定を消す意味になる。
    struct Line: Encodable, Sendable {
        let id: String
        let clap: String?
        let calls: [Call]

        private enum CodingKeys: String, CodingKey { case id, clap, calls }

        /// `clap` は **nil でも明示的に null を出す**。`encodeIfPresent` だとキーごと
        /// 消えてしまい、サーバから見て「未指定 (=変更しない)」と「消す」の区別が付かない。
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(clap, forKey: .clap)
            try c.encode(calls, forKey: .calls)
        }
    }

    /// コール 1 件。`stale` は送らない — サーバ側が歌詞との突き合わせで決める印なので、
    /// クライアントから申告する筋合いのものではない (再アンカーすれば自然に消える)。
    struct Call: Encodable, Sendable {
        let id: String
        let start: Int
        let end: Int
        let anchorText: String
        let text: String
        let emphasis: String
        /// "over" (同時) / "after" (追っかけ)。幅ゼロのアンカーはサーバが "after" に倒す。
        let timing: String
    }
}

extension CallGuidePayload.Call {
    /// 表示用モデルから送信用に詰め替える。
    init(_ call: LyricCall) {
        self.init(
            id: call.id,
            start: call.start,
            end: call.end,
            anchorText: call.anchorText,
            text: call.text,
            emphasis: call.emphasis.rawValue,
            // 幅ゼロに "over" を送ってもサーバ側で "after" に倒されるが、
            // 送信値と保存値が食い違うのは気持ちが悪いのでこちらでも揃えておく。
            timing: call.isOverlapping ? CallTiming.over.rawValue : CallTiming.after.rawValue
        )
    }
}

/// `PUT /songs/{song_id}/timings` のリクエストボディ。歌詞行の再生位置だけを送る。
///
/// ⚠️ ここにも行の本文を足さないこと (`CallGuidePayload` と同じ理由)。
/// PUT は曲全体の全置換で、載せなかった行は「記録なし」に戻る。
struct LyricTimingPayload: Encodable, Sendable {
    let lines: [Line]
    /// コールの再生位置 (id はコールの id)。行と同じ形。
    let calls: [Line]

    struct Line: Encodable, Sendable {
        let id: String
        let startMs: Int?
        /// 被せの指定。`sendsLayer` が false (コール) ならキーごと送らない。
        var layer: String? = nil
        var sendsLayer = false

        private enum CodingKeys: String, CodingKey { case id, startMs, layer }

        /// 記録を消した行も明示的に null で送る (キーごと消すと意図が読めない)。
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(startMs, forKey: .startMs)
            if sendsLayer { try c.encode(layer, forKey: .layer) }
        }
    }
}

/// `POST /songs/{song_id}/lyric-structure` のリクエストボディ。歌詞の行の区切りだけを動かす。
///
/// ⚠️ 歌詞の文字は送らない (行 ID と位置だけ)。サーバは文字を書き換えない。
struct LyricStructurePayload: Encodable, Sendable {
    enum Joiner: String, Sendable, CaseIterable {
        case none = ""
        case half = " "
        case full = "　"

        var label: String {
            switch self {
            case .none: return "空白なしでくっつける"
            case .half: return "半角空白でくっつける"
            case .full: return "全角空白でくっつける"
            }
        }
    }

    let op: String
    let lineId: String
    var joiner: String?
    var at: Int?

    /// 行と次の行を 1 行にする。
    static func merge(lineId: String, joiner: Joiner) -> Self {
        Self(op: "merge", lineId: lineId, joiner: joiner.rawValue)
    }

    /// 行をスカラー位置 `at` の前で 2 行に分ける。
    static func split(lineId: String, at: Int) -> Self {
        Self(op: "split", lineId: lineId, at: at)
    }
}

/// `PUT /songs/{song_id}/parts` のリクエストボディ。行ごとの歌唱者 (アイドル id) だけを送る。
///
/// ⚠️ 歌詞本文は送らない。PUT は全置換で、載せなかった行のパートは消える。
struct LyricPartsPayload: Encodable, Sendable {
    struct Line: Encodable, Sendable {
        let id: String
        let singers: [String]
    }
    let lines: [Line]
}
