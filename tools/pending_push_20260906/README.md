# 2026-09-06 のデータ修正

CloudKit Production への反映は **2026-09-06 に完了** (削除 5 + 13 + 4 件、push 197 / 11 / 651 / 1 / 16 件)。
適用済みの id 一覧・削除 TSV・data/fixes は片付けた (内容は git 履歴 `2281879` / `659fb41`)。

## 残り: D1 (コミュニティ) の付け替え

私はアイドル♥ (`765as_私はアイドル_2`) → ♡ (`765as_私はアイドル`) の統合で、D1 側の
タグ 3 件 / お気に入り 1 件 / お題投票 1 件がまだ旧 id を指している。

```bash
cd imas-live-api && npx wrangler d1 execute imas-live-db --remote --yes --file ../tools/pending_push_20260906/d1_merge_watashi_wa_idol.sql
```

終わったらこのディレクトリごと消してよい。

## 私はアイドル♡ の統合で落とした情報

♥ 側は原唱者を 星井美希・天海春香・如月千早、発売日を 2006-12-20 (MASTER LIVE 00 相当) としていたが、
コロムビアの商品ページは 2008 年の REM@STER 盤しか残っておらず裏が取れなかったので、この 3 人は
original に**足していない**。ブックレット等で確認できたら `song_artists` に original で足す
(♡ 側の release_date 2007-01-25 も同時に見直す)。

裏取り済み: コロムビア COCX-38070 / COCC-16516 / COCC-16883 / COCX-38437 (歌：765PRO ALLSTARS)、
ランティス LACM-14080 (Thank You! / 765 MILLIONSTARS)、COCX-36899 ANIM@TION MASTER 02
(私はアイドル♡ 歌：水瀬伊織、高槻やよい、双海亜美／真美 → 真美を original に追加)。
