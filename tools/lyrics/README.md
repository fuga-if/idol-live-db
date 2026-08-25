# tools/lyrics — 歌詞と歌詞リンクの作業ツール

## 1. 歌詞リンクの収集 (継続作業)

`songs.lyrics_url` を埋めて、曲詳細から歌詞サイトへ飛べるようにする。
リンクは掲載ではないので JASRAC 許諾は不要。

### なぜセッションを跨ぐのか

**WebSearch はセッション全体で 200 回が上限で、エージェント間で共有される。**
並列に増やしても総量は変わらない。全 2,685 曲には同数の検索が要るので、
12〜13 セッションに分けて進める。

歌ネットは `robots.txt` が 403 を返し自動アクセスを拒否しているので、
**サイトを直接叩かない**。URL の発見は検索エンジンの結果からのみ行う。

### 再開手順

```bash
# 1. 未調査分をスライスに切り出す (既存の候補は自動で対象から外れる)
python3 tools/lyrics/link_worklist.py --slices 150

# 2. エージェントに slice_01 から順に処理させる (1セッションで 150〜200曲が限度)
#    出力は tools/lyrics/slices/out_NN.tsv に
#      song_id / candidate_url / candidate_title / note
#    見つからない曲は URL を**空欄**にすること。文言を書かない。
#
#    ⚠️ **「検索したが見つからなかった」と「予算切れで未着手」を必ず区別させること。**
#       未着手の行は note に「未着手」と書かせる。書かせないと、マージ時に
#       not_found を立ててしまい、次回のスライスから漏れて永久に調査されない。

# 3. 回収した候補を links.tsv にマージし、機械判定を回す
python3 tools/lyrics/link_verify.py --apply

# 4. high だけを data/fixes の JSON に書き出す
python3 tools/lyrics/export_links_json.py --apply

# 5. 反映
python3 tools/apply_data.py --check
python3 tools/apply_data.py --apply
```

スライスは**セトリ登場回数の多い順**なので、`slice_01` から埋めるのが効率的。
実用上は上位数百曲で足りる。

### 判定の考え方 (`link_verify.py`)

キャスト構成が違っても歌詞は同じなので、版や人数の一致は要求しない。
避けたいのは**同名の全く別の曲**を掴むことだけ。判定条件は 2 つ:

1. 候補ページのタイトルに曲名が含まれる
2. 候補ページのタイトルにアイマス関連の固有名詞が含まれる
   (アイドル名・声優名・ユニット名・ブランド名を master.sqlite から集めた 2,236 語)

`high` だけを `lyrics_url` に昇格させる。

## 2. 歌詞本文の投入

**JASRAC の許諾が下りるまで公開しない。** 詳細は `docs/JASRAC.md` §0。

```bash
# テキストを貼って登録 (lyrics_local/ は gitignore 済み)
python3 tools/lyrics/add_lyrics.py "曲名" --clipboard
python3 tools/lyrics/lyrics_json.py validate

# D1 へ投入 (既定は draft。公開には --status published が要る)
python3 tools/lyrics/push_lyrics.py --all --apply
```

歌詞本文は `data/fixes/` に**置かない**。あそこは公開 git リポジトリ。
