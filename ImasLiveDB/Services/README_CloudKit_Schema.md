# CloudKit Schema — 手動設定ガイド

アプリが CloudKit Public Database から全データを同期するには、各 Record Type に
インデックスが設定されている必要があります。CloudKit Dashboard では API からインデックスを
追加できないため、以下の手順を **一度だけ** 手動で行ってください。

---

## 設定手順

1. [CloudKit Dashboard](https://icloud.developer.apple.com) を開く
2. コンテナ `iCloud.com.fugaif.ImasLiveDB` を選択
3. **Schema** → **Record Types** を開く
4. 各 Record Type を選択 → **Indexes** タブ → **Add Index**

---

## 必要なインデックス（全 Record Type 共通）

| フィールド   | タイプ                    | 理由                                         |
|------------|--------------------------|----------------------------------------------|
| `modifiedAt` | **QUERYABLE + SORTABLE** | 差分同期・全件同期の述語・ソートに必要           |
| `deletedAt`  | **QUERYABLE**            | soft delete フィルタリングに必要               |
| `recordName` | **QUERYABLE**            | 個別 fetch / CloudKit 内部クエリに必要（任意） |

> **注意**: `modifiedAt` が QUERYABLE でないと "Field 'modifiedAt' is not queryable" エラーで
> 同期が全件失敗します。`recordName` は `NSPredicate(value: true)` を使わなければ不要ですが、
> 念のため設定を推奨します。

---

## 対象 Record Type 一覧

```
Brand
Idol
CastMember
Event
Show
Song
ImasUnit
SetlistItem
SetlistPerformer
ShowCast
IdolCast
IdolBrand
SongArtist
UnitMember
MetaData
SongCall
SongVideo
```

---

## スキーマ自動生成（Development 環境のみ）

`CloudKitSchemaBootstrap.createSchema()` を Development 環境で一度実行すると、
各 Record Type のフィールド定義が CloudKit に登録されます（ダミーレコードを保存→削除）。
ただし **インデックスは自動登録されません**。上記の手動設定が必ず必要です。

---

## トラブルシューティング

| エラーメッセージ                              | 原因                          | 対処                                |
|----------------------------------------------|-------------------------------|-------------------------------------|
| "Field 'modifiedAt' is not queryable"         | インデックス未設定              | 上記の手動設定を実施                  |
| "Field '___recordName' is not queryable"      | `NSPredicate(value: true)` 使用 | コードは修正済み（modifiedAt ベース） |
| "Field 'modifiedAt' is not sortable"          | SORTABLE インデックス未設定     | modifiedAt に SORTABLE を追加         |
