# 2026-09-06 のデータ修正 (CloudKit へ未反映)

`db/master.sql` は直してある。CloudKit が正なので、push しないと翌日の日次 export で巻き戻る。

| ファイル | 内容 | push |
|---|---|---|
| `songs.txt` | 765AS 全体曲 4 曲 + Thank You! の song_artists (春香/律子/真美 を performer → original) | `--tables song_artists --ids-file` |
| `show_events.txt` | 会場欄と配信欄が同文だった 10 公演 (venue を都内某所/NULL に、配信欄に実体) | `--tables shows --ids-file --replace` (NULL にした列を消すため replace) |
| `setlist_items.txt` | 注記の括弧包み・＠ を素の形に (651 件、うち空文字 194 件は NULL) | `--tables setlist_items --ids-file --replace` |
| `../pending_cloudkit_deletions_sidem_11th_dup_20260906.tsv` | SideM 11th STAGE の重複イベント 3 件 + 公演 2 件 | `--delete-file --yes` |
| `../pending_cloudkit_deletions_765as_roles_20260906.tsv` | 上の 13 行の**旧 performer レコード** (recordName に role が入るので、original を push しても残る) | `--delete-file --yes` |
| `../pending_cloudkit_deletions_song_merge.tsv` | 私はアイドル♥ (`765as_私はアイドル_2`) の統合で消す Song 1 件 + SongArtist 3 件 | `--delete-file --yes` |
| (id 直指定) | 統合で付け替えた公演 `sh_L0987_10095` と、私はアイドル♡ に足した双海真美の original | `--tables setlist_items --ids sh_L0987_10095` / `--tables song_artists --ids 765as_私はアイドル` |
| `d1_merge_watashi_wa_idol.sql` | 私はアイドル♥ のコミュニティデータ (タグ 3 / お気に入り 1 / お題投票 1) を ♡ 側へ | `npx wrangler d1 execute imas-live-db --remote --file ...` (imas-live-api で) |

裏取り: コロムビア COCX-38070 / COCC-16516 / COCC-16883 / COCX-38437 (歌：765PRO ALLSTARS)、
ランティス LACM-14080 (Thank You! / 765 MILLIONSTARS)、COCX-36899 ANIM@TION MASTER 02
(私はアイドル♡ 歌：水瀬伊織、高槻やよい、双海亜美／真美 → 真美を original に追加)。

## 私はアイドル♡ の統合で落とした情報

♥ 側 (`765as_私はアイドル_2`) は原唱者を 星井美希・天海春香・如月千早、発売日を 2006-12-20
(MASTER LIVE 00 相当) としていたが、コロムビアの商品ページは 2008 年の REM@STER 盤しか残っておらず
裏が取れなかったので、この 3 人は original に**足していない**。ブックレット等で確認できたら
`song_artists` に original で足す (♡ 側の release_date 2007-01-25 も同時に見直す)。

## 順番

1. `--delete-file` 3 本 (SideM 重複 → 765AS 旧 performer → 私はアイドル♥)
2. push 4 本 (song_artists → shows --replace → setlist_items --replace → setlist_items/song_artists の id 直指定)
3. D1 の SQL
