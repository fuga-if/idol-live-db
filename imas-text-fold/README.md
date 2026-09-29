# imas-text-fold

検索の照合で使う **文字の畳み込み規則の唯一の実体**。

`imas-core` (iOS / Android) と、Web の検索欄で動く wasm の両方がここを見る。
畳み方が 1 箇所でも分かれると「iOS では当たって Android では当たらない」
「一覧には出るのにハイライトが付かない」といった形で、使う人にとっての不具合になる。
規則を変えるときは、**ここを変えてから**呼び出し側を直すこと。

## 畳むもの / 畳まないもの

畳むのは 3 つだけ。

1. **大文字小文字** — `char::to_lowercase` (文脈を見ない無条件写像)。
   `str::to_lowercase` は使わない。Unicode SpecialCasing の Final_Sigma 規則を適用して
   語末の Σ を ς にしてしまい、原本 Swift の `String.lowercased()` と当たり方がずれる。
2. **カタカナ → ひらがな** — U+30A1..=U+30F6 のみ。`ー` (U+30FC) と `・` (U+30FB)、
   `ヷヸヹヺ` は対応するひらがなが無いので触らない。
3. **単独の濁点・半濁点の合成** — `か` + U+3099 → `が`。合成済み (NFC) と分解済み (NFD) の
   2 通りの表し方をバイト列で比べられるようにするため。

**畳まないもの**: 濁点そのものの有無 (`ラブ` と `ラフ` は別)、全角半角、アクセント記号。

## API

| 関数 | 用途 |
|---|---|
| `fold(&str) -> String` | 索引側・検索語側の両方をこれに通す |
| `fold_kana(char) -> char` | 1 文字ぶんのカタカナ→ひらがな |
| `fold_with_offsets(&str)` | 畳んだバイト列 + 各バイトが元文字列のどこから来たかの対応表 (ハイライト用) |
| `find(&[u8], &[u8]) -> Option<usize>` | 畳み済みバイト列の部分列探索 |
| `contains(&[u8], &[u8]) -> bool` | 同上の真偽版 |

## 使う側

* `imas-core` — `domain::text_search_index` (`TextSearchIndex` / `FoldedNeedle` / `match_range`)
* `web/wasm/imas-fold-wasm` — ブラウザの検索欄に `fold` だけを渡す
