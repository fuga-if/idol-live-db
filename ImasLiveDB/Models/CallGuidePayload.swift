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
            emphasis: call.emphasis.rawValue
        )
    }
}
