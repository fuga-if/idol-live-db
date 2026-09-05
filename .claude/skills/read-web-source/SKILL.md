---
name: read-web-source
description: WebFetch で読めない URL を r.jina.ai 経由で読む。X (Twitter) のリンクを渡されたとき、公式サイトが JS 描画で本文が取れないとき、セトリや告知が画像で貼られていて中身を確認したいときに使う。出典の裏取りが必要な作業 (セトリ投入・新曲登録) の前段。
---

# read-web-source

`https://r.jina.ai/` を前に付けると、ページを Markdown に変換して返してくれる。

```bash
curl -sS -L --max-time 90 -A "Mozilla/5.0 Chrome/126" \
  "https://r.jina.ai/<元のURL>" -o out.md
```

`<元のURL>` はスキームごと繋げる (`https://r.jina.ai/https://x.com/...`)。

## いつ使うか

| 状況 | 素の WebFetch | r.jina.ai |
|---|---|---|
| X (Twitter) の投稿 | **HTTP 402 で不可** | 読める |
| `idolmaster-official.jp` の記事 | 本文は取れるが JS 描画部分が欠ける | 本文 + **画像 URL** が出る |
| ランティス等のディスコグラフィ | JS 描画で空 | 読める場合がある |

**画像 URL が本文に出るのが大きい。** アイマス公式のセットリストは画像で貼られており、
テキストからは取れない。r.jina.ai の出力には CDN の実 URL が入るので、そのまま拾える:

```bash
grep -o "cmsapi-frontend[^)\" ]*" out.md | head
```

## セトリ画像を読むところまで

1. `r.jina.ai` でページを取る
2. 画像 URL を拾う (上のコマンド)。どの画像が何かは**前後の見出しテキストで判断する**
   (`新ロゴ＆新キャッチコピー` → 直後の画像、など)
3. ダウンロードして **Read ツールで開く** — 画像はそのまま読める

```bash
curl -sS -L --max-time 60 -A "Mozilla/5.0 Chrome/126" "<画像URL>" -o shot.jpg
```

実績: `Project"ReLight"AXE8` の第1弾/第2弾がどのユニットか本文に無く (alt も空)、
ロゴ画像を Read して アルストロメリア / イルミネーションスターズ を確定した。
作詞作曲クレジットも告知画像からしか取れなかった。

## X (Twitter) は専用プロキシの方が速い

r.jina.ai は X が詰まりやすい (下記 403)。X の投稿は**先にこちらを試す**:

```bash
ID=<status の数字>; U=<screen_name>
curl -sS -L --max-time 30 "https://api.fxtwitter.com/$U/status/$ID" -o fx.json
```

`tweet.text` に本文、`tweet.media.photos[].url` に**画像の原寸 URL** (`?name=orig`) が入る。
認証不要で JSON なので扱いやすい。3 つとも実地で通ることを確認済み:

| 経路 | 返るもの |
|---|---|
| `api.fxtwitter.com/<user>/status/<id>` | JSON。本文 + media URL。**第一候補** |
| `api.vxtwitter.com/<user>/status/<id>` | JSON。項目名が違う |
| `publish.twitter.com/oembed?url=<エンコード済みURL>` | 埋め込み HTML。本文のみ (画像なし) |

画像はダウンロードして **Read ツールで開く**。アイマス公式のセトリは画像で貼られるので、
ここまでやって初めて中身が取れる。

```bash
curl -sS -L --max-time 60 "https://pbs.twimg.com/media/XXXX.jpg?name=orig" -o setlist.jpg
```

## 失敗パターン

### 403 AbuseAlleviationError

```json
{"code":403,"name":"AbuseAlleviationError",
 "message":"Anonymous access to domain x.com blocked until Sat Sep 05 2026 12:31:53 GMT ..."}
```

**匿名アクセスの一時ブロック。** 他の誰かがそのドメインを叩きすぎると巻き添えで止まる。
`blocked until` に**解除時刻が書いてある**ので、それを読んで待つか、後で再試行する。
リクエストの投げ方を変えても回避できない (ドメイン単位)。

待てない場合は依頼者に本文を貼ってもらう。推測で埋めないこと。

### 402 (元の URL 側)

x.com は素の WebFetch だと 402 Payment Required。これはプロキシではなく X 側の制限で、
`r.jina.ai` を通す以外の回避策は無い。

## 注意

- **取れた内容は一次情報とは限らない。** r.jina.ai はページを変換するだけ。
  引用ツイートや埋め込みが混ざることがあるので、誰の投稿かを確認する
- 出典 URL は**元の URL** を記録する (`r.jina.ai` 付きのものではない)
- 長いページは途中で切れることがある。必要な箇所が入っているか確認してから使う
