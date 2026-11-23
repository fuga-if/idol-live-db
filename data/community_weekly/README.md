# data/community_weekly/ — 週ごとの再生回数・お気に入り数

**ここは人が編集する場所ではありません。** GitHub Actions
(`.github/workflows/community-weekly-stats.yml`) が毎日 00:23 JST に書き込みます。
実データは `bot/community-stats` ブランチに溜まります (develop にはこの README だけ)。

## これは何か

週次チャート (先週比・初登場・連続ランクイン) の材料です。D1 の `song_play_counts` は
今週・先週しか持たないので、過去の週の順位を後から出せるように週に 1 枚ずつ残します。

```
YYYY-MM-DD.tsv                       # その月曜 (JST) に始まる 1 週間ぶん
song_id<TAB>preview<TAB>full<TAB>favorites   # ヘッダ行あり。song_id 順
```

- `preview` / `full`: その週に再生された回数 (試聴 / フル再生)。
- `favorites`: その週が終わった時点のお気に入り数 (累計)。その週に付いた数は、
  前の週のファイルとの差で出します。
- 全部 0 の曲は行がありません。
- 同じ週は毎日書き直します。再生回数は遅れて届いた分で少し増え、お気に入り数は
  最初に書いた値のままです。

⚠️ 遡れるのは「終わった最新の週」だけです。バッチが 1 週間止まると、その週の
再生回数は取り返せません。

仕組みは `tools/community/collect_weekly_stats.py` の冒頭に書いてあります。
