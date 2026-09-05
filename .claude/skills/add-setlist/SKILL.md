---
name: add-setlist
description: 公演のセットリストを data/setlists/ に投入する。「セトリ入れて」「この公演のセットリスト追加」「ライブのセトリ更新」と言われたとき、または新曲が初披露された公演を登録するときに使う。show_id の引き当て、初披露曲の同時登録、--check の落とし穴までを含む。
---

# add-setlist

公演のセットリストを `data/setlists/` に入れる。**投入 (CloudKit への push) はオーナーの作業**で、
ここでやるのは JSON を置いて `--check` を通すところまで。

## 0. 前提の確認 (最初に必ず)

```bash
git fetch origin && git checkout -B <作業ブランチ> origin/develop
```

`db/master.sql` は日次 cron で更新される。**古い master に対して検証しても意味がない**
(詳細は「落とし穴 1」)。

このコンテナには `sqlite3` CLI が無いので `tools/build_db.sh` は落ちる。
Python で作る:

```bash
python3 -c "
import sqlite3,pathlib
p='ImasLiveDB/Resources/master.sqlite'; pathlib.Path(p).unlink(missing_ok=True)
c=sqlite3.connect(p); c.executescript(open('db/master.sql',encoding='utf-8').read()); c.commit()"
```

> `build_db.sh` は FK ゲート・`data_version` ゲート・`meta.content_hash` の書き込みも行う。
> 同梱 DB を作る用途ではスクリプトを使うこと (上の代替は検証用)。

## 1. show_id を引き当てる

```bash
python3 - <<'PY'
import sqlite3
c=sqlite3.connect('ImasLiveDB/Resources/master.sqlite')
q='''select s.id,s.date,s.name,s.venue,(select count(*) from setlist_items si where si.show_id=s.id)
from shows s join events e on e.id=s.event_id where e.name like ? order by s.date'''
for r in c.execute(q,('%公演名の一部%',)): print(' | '.join(map(str,r)))
PY
```

末尾の数字が**既存のセトリ曲数**。0 でなければ既に入っている (「落とし穴 2」)。

公演自体が無ければ先に `data/events/` で追加する。

## 2. セトリを一次ソースで確認する

優先順:

1. `idolmaster-official.jp/news/…` の「本日のセットリスト」— ただし**セトリは画像**なので本文からは取れない
2. 公式 X (`@imas_official` 等) のセトリ画像
3. ライブレポート記事 (PANORA 等) や `aimasupay.hatenablog.com` — 曲順と歌唱者がテキストで載る

**x.com は WebFetch できない (HTTP 402)。** プロキシではなく X 側の制限なので回避策は無い。
X しか出典が無い場合は、依頼者に本文を貼ってもらう。

歌唱者が**声優名**で書かれている資料が多い。アイドル id への変換は DB で引く:

```sql
SELECT i.id, i.name FROM idol_voice_actors v JOIN idols i ON i.id = v.idol_id
WHERE v.name LIKE '%声優名%';
```

## 3. 曲を全部 id に解決する

```bash
python3 - <<'PY'
import sqlite3
c=sqlite3.connect('ImasLiveDB/Resources/master.sqlite')
titles=["曲名1","曲名2"]           # セトリ順に
for t in titles:
    r=list(c.execute("select id,brand_id from songs where title=?",(t,)))
    print(("✓ " if r else "✗ ")+t, r)
PY
```

**解決しなかった曲は、以下のどれかを見極める:**

- **表記ゆれ** — `〜` と `～`、全角/半角の `!`、`「」` の有無、`(ビクトリー)` のような副題。
  `LIKE '%部分文字列%'` で探し直す
- **バージョン違い** — 会場ごとに歌唱メンバーが変わる曲がある
  (例: `修楽旅行 (有村麻央・葛城リーリヤ・花海佑芽・姫崎莉波 ver.)`)。
  **別公演の ver. を流用しない。** 該当 ver. が未登録なら出典を確認してから登録する
- **初披露の新曲** — `data/songs/` に同じ PR で足す (次項)

## 4. 初披露の新曲があれば先に登録する

`data/songs/<日付>_<topic>.json` に足す。`--check` は**同じバッチの新曲を見る**ので、
曲とセトリを同じ PR に入れてよい (`resolve_song` の `pending`)。

発売日・クレジットが未発表なら空でよい。`original_singers` は入れること
(一覧の performer アイコンに要る)。

同名別ブランド曲に注意 (例: `Be proud` は `ml_be_proud` が既存。学マスのものは
`gakuen_be_proud` として別に作る)。

## 5. JSON を書く

`data/setlists/<YYYYMMDD>_<topic>.json`。`_template.json` をコピーする。

```json
{
  "title": "公演名 (日付 会場) セットリスト",
  "show_id": "sh_...",
  "all_performers": ["idol_id", "..."],
  "songs": [
    { "position": 1, "song_id": "...", "performers": "all" },
    { "position": 2, "song_id": "...", "performers": ["idol_id"],
      "section": "アンコール", "notes": "新曲初披露" }
  ]
}
```

**曲は `song_id` 直指定にすること。** `title` 解決は**公演のブランド内に限定**される
(`resolve_song`) 一方、セトリには他ブランド曲が普通に入る
(`ml_嘆きのfraction` / `961_kiss` / `ml_discord_area` など)。title 依存だと解決できない。

- `performers`: `"all"` (= `all_performers` 全員) か `idol_id` 配列
- `section`: 公式の区切りがあれば入れる (`～COOL～` / `アンコール` 等)
- `notes`: 歌唱以外の事実 (「ダンス参加: 〜」「新曲初披露」「ロングヘアで歌唱」など)

判断が要る例:

- **歌唱しない出演者**は `performers` に入れない。`notes` に「ダンス参加: 〜」として残す
- **アイマス楽曲でないもの** (ラジオ体操等) は曲登録せず、隣接 position の `notes` に事実だけ残す
- `source` は**必須ではなくなった** (根拠は PR 説明欄に書く運用)。ただし出典 URL を
  `source` / `_sources` に残しておくとレビューが速い

## 6. 検証

### 6-1. 現 CloudKit を基準に検証する (重要)

```bash
git fetch origin bot/data-refresh
git show origin/bot/data-refresh:db/master.sql > /tmp/cur.sql
python3 -c "
import sqlite3
c=sqlite3.connect('/tmp/cur.sqlite'); c.executescript(open('/tmp/cur.sql',encoding='utf-8').read()); c.commit()"
python3 tools/apply_data.py --check --only <ファイル名>.json --db /tmp/cur.sqlite
```

### 6-2. 実際に入るかを試す

```bash
cp /tmp/cur.sqlite /tmp/dry.sqlite
python3 tools/apply_data.py --apply --only <ファイル名>.json --db /tmp/dry.sqlite
python3 tools/check_fk_integrity.py /tmp/dry.sqlite      # → ✅ 0件
```

### 6-3. 中身を目視する

```sql
SELECT si.position, s.title, si.section,
       group_concat(i.name,'・') AS performers, si.notes
FROM setlist_items si JOIN songs s ON s.id = si.song_id
LEFT JOIN setlist_performers sp ON sp.setlist_item_id = si.id
LEFT JOIN idols i ON i.id = sp.idol_id
WHERE si.show_id = ? GROUP BY si.id ORDER BY si.position;
```

## 7. PR

`data/**/*.json` は**自分で消さない**。オーナーが `--apply --push --production` した後に消す運用
(PR 履歴が監査ログ)。PR 説明欄に出典 URL と、判断した点 (バージョン違い・歌唱者の扱い等) を書く。

---

## 落とし穴

### 1. ローカルの master.sql は CloudKit より古い

`--check` はローカル `master.sqlite` (= `db/master.sql` 由来) を見る。これは**日次 cron の
スナップショットで、CloudKit にあって git に無いレコードが常に存在する**。

実例: `北極星をズラしちゃえ！` と韓国公演を「新規」として追加し `--check` を通したが、
両方とも既に CloudKit に存在していて衝突した (同じ id 規則で独立に採番したため)。
後から `data/fixes/` へ振り替える羽目になった。

**必ず `bot/data-refresh` の master.sql を基準に検証する** (6-1)。

### 2. 既にセトリが入っている公演に投入すると全滅する

`setlist_items` は `UNIQUE(show_id, position)`。push 済みのセトリが `data/` に残ったまま
`--apply` すると UNIQUE 違反でトランザクションごと巻き戻り、**無関係な投稿まで入らなくなる**
(実際、読み仮名 316 件がこれで落ちた)。

いまは `validate` が既存曲数を見て止めるようになっている。止まったら:
push 済みなら `data/` から消す。直したいなら `data/fixes/` (`setlist_items` は修正対象表)。

### 3. `--only` を付けないと自分の変更が届かない

`--apply` は検証エラーが 1 件でもあると `sys.exit(1)` する。`data/` には push 済みの
INSERT 用 JSON が残りやすく、それが全部「id は既に存在」で problem になる
(2026-08-28 時点で 732 件)。**`--only <ファイル名>.json` で絞る。** パスではなくファイル名で照合。

### 4. 会場ごとのバージョン違い

ツアーでは同じ曲名で歌唱メンバーが公演ごとに変わることがある。DB に 1 つしか無いからといって
それを指さない。該当 ver. が未登録なら、出典を確認してから新規登録する。

### 5. 人名・曲名の字形

master 側の既存表記に合わせる (割れると同一人物/同一曲として突き合わせできない)。
`石黑剛` は「黑」、`Giz'Mo (from Jam9)` と `清水"カルロス"宥人` は直線引用符、
人名の中の空白は除去 (`古屋 真` → `古屋真`)、所属表記 `(SUPA LOVE)` 等は含める。

## オーナー向け (反映)

`docs/DATA_PIPELINE.md` の「オーナー (反映)」を参照。要点:

- key ID は `.claude/skills/sync-new-songs/SKILL.md` (リポジトリ除外済み)、秘密鍵は `tools/eckey.pem`
- `--only` を必ず付ける
- CloudKit に反映 → 翌日の cron が `db/master.sql` を更新 → `bot/data-refresh` → develop へ PR
- スキーマを足した場合は push の前に `xcrun cktool import-schema` で Development へ入れ、
  Dashboard で Production へ昇格する
