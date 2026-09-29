# data/lyrics_requests/ — 歌詞の曲別リクエスト回数 (日次)

**ここは人が編集する場所ではありません。** GitHub Actions
(`.github/workflows/lyrics-request-stats.yml`) が毎日 06:00 JST に書き込みます。
データの投入口は `data/` 直下の README を読んでください。

## これは何か

JASRAC 年次利用曲目報告の 19 項目目「リクエスト回数」の材料です。
Worker が歌詞を返したときだけ出す 1 行のログ (`event=lyrics_read`) を、
Workers Logs から日ごとに数えたものです。

```
YYYY-MM-DD.tsv     # UTC のその日ぶん
song_id<TAB>count  # ヘッダ行あり。回数の多い順、同数は song_id 順
```

- **ヘッダだけのファイル = その日は 0 回**。ファイルが無い日は「まだ集めていない / 取れなかった」。
  この 2 つは意味が違うので区別できるようにしてあります。
- 同じ日を引き直しても同じ中身になります (上書き = 冪等)。
- 記録するのは `song_id` と回数だけです。誰が読んだか (uid・IP・端末) は
  ログにも TSV にも入りません。

## 使い方

```bash
# 年次報告に合算する (期間内の日次ファイルを足して各曲の request_count にする)
python3 tools/jasrac/build_reports.py annual \
  --month 202704 --published published_ids.txt \
  --requests-dir data/lyrics_requests --period 202604-202703
```

⚠️ Workers Logs の保持期間は 3 日です。日次バッチが 3 日以上止まると、その間の
回数は取り返せません (欠測として合計に入りません)。詳しくは
[docs/JASRAC.md](../../docs/JASRAC.md) の「リクエスト回数の集計」。
