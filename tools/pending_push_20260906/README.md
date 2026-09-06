# 2026-09-06 のデータ修正 (CloudKit へ未反映)

`db/master.sql` は直してある。CloudKit が正なので、push しないと翌日の日次 export で巻き戻る。

| ファイル | 内容 | push |
|---|---|---|
| `songs.txt` | 765AS 全体曲 4 曲 + Thank You! の song_artists (春香/律子/真美 を performer → original) | `--tables song_artists --ids-file` |
| `show_events.txt` | 会場欄と配信欄が同文だった 10 公演 (venue を都内某所/NULL に、配信欄に実体) | `--tables shows --ids-file --replace` (NULL にした列を消すため replace) |
| `setlist_items.txt` | 注記の括弧包み・＠ を素の形に (651 件、うち空文字 194 件は NULL) | `--tables setlist_items --ids-file --replace` |
| `../pending_cloudkit_deletions_sidem_11th_dup_20260906.tsv` | SideM 11th STAGE の重複イベント 3 件 + 公演 2 件 | `--delete-file --yes` |

裏取り: コロムビア COCX-38070 / COCC-16516 / COCC-16883 / COCX-38437 (歌：765PRO ALLSTARS)、
ランティス LACM-14080 (Thank You! / 765 MILLIONSTARS)。
