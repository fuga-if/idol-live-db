# デザインシステム

アイドルライブDB (iOS / Android) の画面は、すべてこの文書の **型・区画・部品** を組み合わせて作る。
その場限りの見た目 (色・文字の大きさ・余白・角丸の数字を画面に直接書くこと) はしない。

- 正本はコード。iOS は `ImasLiveDB/DesignSystem/`、Android は `ui/designsystem/` (同じ名前・同じ見た目)。
- 見本 (全部品・全状態の実物) はアプリ内の「部品カタログ」(DEBUG ビルドの設定 → 開発 → 部品カタログ) と参照ページ。
- 画面のコードに数字の寸法・色・文字サイズを書くと `tools/check_ds_usage.sh` が止める。
- 足りない部品があったら、画面に書かずに DesignSystem に部品として足し、この文書に 1 節足す (§15)。

---

## 0. 画面の作り方 (3 段)

1. **画面の型を 1 つ選ぶ** (§2)。型が背景・余白・ナビバー・ツールバー・読み込み/空/失敗の出し方を決める。
2. **区画を上から並べる** (§3)。区画が見出し・中身の器・補足文・区画同士の間隔を決める。
3. **区画に部品を入れる** (§5〜§11)。部品が色・文字・寸法・押したときの動きを決める。

迷ったら §14 の早見表 (「〜したい → この部品」) を引く。

画面のコードに書いてよいのは「どの型・区画・部品を、どのデータで、どの順に置くか」だけ。

---

## 1. 原則 (判断に迷ったときだけ読む)

1. **色はアイドルとブランドのもの。** アプリの枠 (ナビバー・タブ・ツールバー・確定ボタン) は白黒にして、色は必ず `ImasTheme` を通して実体 (アイドル・ブランド・タグ) から引く。hex を画面に書かない。
2. **一覧は静かに、詳細は鮮やかに。** たくさん並ぶ所で全員を塗ると虹色になる。一覧では色は印 (リードバー・アバターの輪・点) だけ。面を塗るのは詳細の頭 (ヒーロー) と、選んだもの・上位のものだけ。
3. **同じ役割は同じ形。** 行・札・ボタン・見出し・シートの閉じ方はそれぞれ 1 種類。大きさ違いは「種類」として部品が持つ。
4. **iPhone の一部に見えること。** ナビバー・タブバー・シート・メニュー・スイッチは OS のものをそのまま使う。自前の面の角丸と余白は OS の表 (inset grouped) に合わせる。
5. **記録として信頼できること。** 数字は桁を揃える (等幅数字)。事実と推測 (予想・機械予測) は見た目で分ける。日付は人の読む形で書く。
6. **ファンの言葉で話す。** 担当・オリメン・全体曲・披露・回収・現地・配信・LV。機械の言葉 (ID・ISO 日付・null) を画面に出さない。

---

## 2. 画面の型

### 2.1 一覧 `ListScreen`
**用途** タブ直下の一覧、絞り込み一覧、検索結果。1 種類のもの (曲・ライブ・アイドル・ユニット・タグ) が多数並ぶ。

**上から順に**
1. ナビバー。タブ直下は大きいタイトル、push 先は標準。左=設定 (`ImasToolbarItem.settings`、タブ直下のみ)。右=`imasListToolbar` (絞り込み・追加・その他)。名前で絞る欄はナビバーの中の `ImasSearchField`。
2. `ImasFilterBar` — 効いている絞り込みを `ImasRemovableChip` で横に 1 段。何も効いていなければ出さない。
3. `ImasListSummary` — 「2,051 件」と並び順メニュー。
4. 本体 — `List(.plain)` + `ImasListSection` (見出しは年・ブランド・五十音などの区切り)。行は実体ごとの行 (§5)。
5. 状態 — `ImasStateContainer` が出し分ける。初回=スケルトン、0 件=空状態、絞り込み 0 件=「見つかりません」+解除ボタン、失敗=再試行。

**器** `List`。参加・習熟度のスワイプは List でしか動かない。
**やらない** 一覧の頭に説明文の帯を置く / チップを 2 段以上並べる / 同じ一覧に形の違う行を混ぜる。
**実例** ライブ、楽曲、アイドル、タグ、絞り込んだ曲・ライブ・公演、マイ投票、参加したライブ。

### 2.2 詳細 `DetailScreen`
**用途** 1 つのものの詳細 (曲・アイドル・ユニット・ライブ・公演・タグ・お題・衣装・会場)。シートでも push でも同じ形。

**上から順に**
1. ナビバー。タイトルはインラインで中央 (実体の名前)。右=`ImasToolbarItem.share` と `.more`。シートのときは閉じる (`ImasToolbarItem.close`)。
2. `ImasHero` — そのものの顔。画像・名前・要点・主操作 1 つ。地は実体色の `heroSurface`。
3. `ImasMarkBar` — 担当・お気に入り・参加・メモ・座席のうち、その実体に付けられるものだけ。
4. `ImasTabs` — 中身の切り替え 2〜4 個。ヒーローを越えると上に貼り付く。
5. タブの中身 — `ImasSection` を縦に並べる。

**器** `ScrollView` + `LazyVStack(pinnedViews: .sectionHeaders)`。
**色** 型の根で `.imasTheme(seed:brand:)` を 1 回だけかける。中の部品は環境から色を引くので、部品ごとに `seed` を渡さない。
**やらない** ヒーローにボタンを 3 つ以上 / タブの中にさらにタブ / 詳細で大きいナビタイトル / ヒーローの下に説明の帯。
**実例** 曲・アイドル・ユニット・ライブ・セットリスト・タグ・お題・衣装。

### 2.3 ハブ `HubScreen`
**用途** プロデュース、クイズ・ゲーム、マイページの最上段。奥の画面への入口を並べる。
**上から順に** ナビバー (大きいタイトル) → 主役のカード (`ImasFeatureCard`、担当・次のライブ・開催中のお題など 1〜3 枚) → 入口の区画 (`ImasEntryCard` の並び、または `ImasCardList` + `ImasNavRow`) → 記録 (`ImasStatGrid`)。
**やらない** 入口ごとに別のグラデーション / カードの横幅を中身に合わせる (横幅はいつも画面いっぱい)。

### 2.4 編集シート `FormSheet`
**用途** 作る・直す (ライブ・公演・受付・曲・アイドル・支出・タグ・お題・補足・参考動画・セトリ)。
**組み方**
- `NavigationStack` + `Form` に `.imasForm()`。タイトルは「〇〇を追加」「〇〇を編集」。
- ツールバー `.imasSheetToolbar(.edit(onCancel:onSave:canSave:))`。左=キャンセル、右=保存 (みんなに見えるもので「送信」にするときは `.submit`)。iOS 26 は OS のガラスのボタン (確定は白黒の塗り)、iOS 17/18 は文字のボタンで出る。
- 保存中は `.imasSavingOverlay(isSaving, label: "保存中")`、失敗は `.imasErrorAlert($error)`、書きかけを閉じるときは `.imasDiscardConfirmation(isDirty:)`。
- 入力は §7 の入力行だけで組む。削除は最後の区画に `ImasActionRow(.destructive)` を 1 つ置き、確認を出す。

**やらない** シートの上にシート (push にする) / 保存ボタンを本文の下に置く / `.sheet(isPresented:)` + 別の `@State` で値を渡す (`.sheet(item:)` を使う)。

### 2.5 選択シート `PickerSheet`
**用途** アイドル・ユニット・曲・会場・ライブ・公演・候補を選ぶ。
**上から順に** ナビバー (短いタイトル。ツールバー 4 個で省略されないように) と `ImasSearchField` → `ImasChipRow` (ブランドなどの絞り込み、任意) → 一覧 (`ImasSelectableRow`) か格子 (`ImasIdolCell`) → 複数選択なら下に `ImasSelectionTray` → ツールバー: 左=キャンセル、右=完了。
**1 つだけ選ぶ** ときは選んだ瞬間に閉じ、完了ボタンは出さない。
**唯一の正** アイドルは `IdolPickerView`、ユニットは `UnitMultiPickerView`、曲は `SongSearchPickerView`。同じ役割のピッカーを新しく作らない。

### 2.6 絞り込みシート `FilterSheet`
**組み方** `List` + `.imasFilterSheetChrome()` + `filterSheetToolbar` (左=リセット、右=適用。リセットはツールバーにだけ)。区画は `ImasListSection`。中身は `ImasChipFlow` + `ImasFilterChip`、`ImasToggleRow`、細かい選択へ進む `ImasNavRow`。
**やらない** 絞り込み条件を 1 画面に 2 か所 / 一覧の中にリセットの区画。

### 2.7 設定 `SettingsScreen`
**組み方** `List(.insetGrouped)` + `ImasListSection`。行は `ImasNavRow`・`ImasToggleRow`・`ImasMenuRow`・`ImasValueRow`・`ImasActionRow`。
**実例** 設定 (マイページ)、アプリについて、習熟度の段階、ChatGPT 連携。

### 2.8 読みもの `DocumentScreen`
**組み方** `ScrollView` + `ImasProse` (見出し・段落・箇条書き・手順 `ImasStepList`・画像)。
**実例** 規約、プライバシー、ヘルプの詳細、ウィジェットの使い方、JASRAC 表記。

### 2.9 ゲーム `Stage`
設定画面は通常の画面 (`ImasSetupHeader` → 区画 → 画面の下に主ボタン)。遊ぶ画面と結果はステージ (§12)。

### 2.10 共有画像 `ShareSheet`
シートにプレビューと共有ボタン (`ImasShareActions`) を置く。画像そのものは §13。

---

## 3. 区画

ScrollView では `ImasSection`、List・Form では `ImasListSection`。見た目は同じ。

```swift
ImasSection("ライブ歌唱曲", count: "42曲", action: .seeAll { ... }, footer: "披露回数は公式のセットリストから数えています。") {
    ImasCardList(songs) { ImasSongRow($0, density: .compact, trailing: .metric(.performances($0.count))) }
}
```

| 部分 | 決まり |
|---|---|
| 見出し `ImasSectionHeader` | **大** = 20pt 太字・墨。詳細とハブの区画。**小** = 13pt 中太・灰。一覧・設定・フォームの区画と、カードの中の小分け。1 画面の区画は大か小のどちらかに揃える |
| 見出しの右 | 件数 (灰) と「すべて見る」のどちらか 1 つずつまで |
| 中身の器 | `ImasCardList` (行をカードに入れる) / `ImasCard` (行でない中身) / `ImasGrid` (格子) / `ImasCarousel` (横スクロール) / `ImasChipFlow` (チップの折り返し) / なし (統計タイル・主ボタンなど単体) |
| 補足 `ImasNote` | 区画の下に 13pt 灰色の文。**囲まない** |
| 間隔 | 区画どうし 28pt、見出しと中身 8pt、中身と補足 6pt |

**やらない** 見出しを手書きの `Text` で作る / List の `Section("文字列")` の素の見出しを使う / 補足文を色付きの箱で囲む (注意させたいなら `ImasNotice`)。

---

## 4. 器と面のルール

| 中身 | 器 | 理由 |
|---|---|---|
| 1 種類のものが多数 (スワイプ操作がありうる) | `List(.plain)` | スワイプ・行の再利用・選択・編集 |
| 違う種類の区画が縦に並ぶ | `ScrollView` + `LazyVStack` | 見出しの貼り付き・区画ごとの器 |
| 入力・設定 | `Form` / `List(.insetGrouped)` | キーボードと入力の標準動作 |

**面の種類**

| 面 | 色 | 角丸 | 使う所 |
|---|---|---|---|
| 地 `DS.bg` | systemGroupedBackground 相当 | — | すべての画面の背景 |
| カード `DS.surface` | 白 / 濃灰 | `DS.rCard` | `ImasCard`・`ImasCardList`・統計タイル・入口カード |
| 入れ子 `DS.surface2` | 地と同じ灰 | `DS.rInner` | カードの中の囲み (差分表示など) |
| 押せる地 `DS.fill` | 半透明の灰 | 部品ごと (カプセル等) | チップ・セグメント・入力欄・副ボタン |
| 実体の地 `heroSurface` | 実体色をごく薄く | なし (全幅) | 詳細の頭、`ImasFeatureCard` の担当・次の出演 |

**角丸は OS の表に合わせる。** `DS.rCard` は iOS 26 以降 26pt、iOS 17/18 は 10pt (OS の inset grouped と同じ値)。自前のカードが OS の Form・設定と並んでも同じ形に見える。カードの中に入れる面は `DS.rInner` (= `rCard` − 余白 16、最小 6) で同心円にする。ボタン・チップ・入力欄・札はカプセル。

---

## 5. 行

### 5.0 行の共通の形 `ImasRow`

```
[先頭]  [題 (16pt 太字・墨・2 行まで)              ]  [末尾]
        [副題 (13pt 灰・1 行)                       ]
        [下段 (札・日付・回数 12pt 薄灰・1 行)       ]
```

| 枠 | 選べるもの |
|---|---|
| 先頭 `ImasRowLeading` | なし / `.bar` (ライブ・公演のリードバー) / `.avatar` (40) / `.artwork` (48) / `.iconTile` (32) / `.number` (セトリの曲順・順位) / `.selection` (ピッカーの選択印) |
| 末尾 `ImasRowTrailing` | なし / `.chevron` / `.value(String)` / `.metric(value, unit)` / `.toggle(Binding)` / `.mark(kind)` (♥ など) / `.menu` (…) / `.badge(ImasBadge)` |

| 種類 | 上下の余白 | 使う所 |
|---|---|---|
| `.regular` | 12 | 一覧 (List) |
| `.compact` | 8 | カードの中の短い一覧、ピッカー |

| 状態 | 見え方 |
|---|---|
| 通常 | — |
| 押下 | 面が `DS.fill` |
| 選択 | 先頭の選択印が塗り (`accent`)。行の面は塗らない |
| 薄字 | 題・副題が `ink3` (欠席・未配信・終わったもの) |
| 無効 | 全体 0.45 |

**振る舞い** タップ = 詳細へ / 長押し = コピー (`imasCopyable`、題・よみ・歌唱者など外で検索したくなる値) / スワイプ = 印 (参加・習熟度)。
**区切り線** 行が自分で決める (本文の頭から右端まで)。画面で `Divider()` を書かない。
**矢印** 一覧 (List) の行には出さない (行全体が押せるのが分かるため)。カードの中の行で別画面へ行くときだけ `.chevron`。
**最小の高さ** 44pt。Dynamic Type が大きいときは末尾が下の段に回る。

実体ごとの行 (5.1〜) は `ImasRow` の中身を実体のデータから決めたもの。**同じ実体はアプリ中どこでも同じ行で出す。**

### 5.1 `ImasSongRow` 曲
- **使う** 曲の一覧・検索結果・アイドル/ユニット詳細の曲・共起曲・関連曲・ピッカー。
- **使わない** 順位を見せる → `ImasRankingRow` / セトリの曲順 → `ImasSetlistRow` / 予想と機械予測 → `ImasForecastRow`。
- **構成** 先頭=ジャケ 48 (無ければブランド色の面 + 曲名)。題=曲名。副題=歌唱者 (ユニット名、無ければ個人名を「・」で)。下段=リリース日・♥(担当が歌う)・メモ・習熟度・現地回収 ✓N。
- **末尾** なし (既定) / `.metric` (並べ替えの根拠: 披露回数・回収率) / `.chevron` (カードの中)。
- **種類** `.regular` (一覧) / `.compact` (ジャケ 40・下段なし)。
- **振る舞い** タップ=曲詳細 / ジャケのタップ=試聴 / 長押し=曲名・よみ・歌唱者をコピー / スワイプ=習熟度。
- **置き換えるもの** `SongRowView`、`SongTitleRow`、`RelatedSongRow`、`SongHistoryTab` の共起曲・履歴行、`LyricsSearchRow`、`SongPickerView` の行。

### 5.2 `ImasIdolRow` アイドル
- **構成** 先頭=アバター 40 (担当は二重輪)。題=名前。副題=ブランド・CV。末尾=なし / `.mark(.pick)` / `.chevron`。
- **置き換えるもの** `IdolRowView`、`IdolNameRow`、ピッカーの行。

### 5.3 `ImasUnitRow` ユニット
- **構成** 先頭=ユニットのアバター 40。題=ユニット名。副題=メンバー (3 人まで + 「ほか N 人」)。
- **置き換えるもの** `UnitRowView`、`UnitNameRow`。

### 5.4 `ImasEventRow` ライブ
- **構成** 先頭=リードバー (ブランド色、合同は複数色の縞)。題=ライブ名 (2 行まで)。副題=日付 (`2026年11月7日(土)〜8日(日)`)・会場。下段=参加予定などの札。
- **置き換えるもの** `ImasLeadRow` のイベント用途、`EventNameRow`、`FilteredShowsView` の行。

### 5.5 `ImasShowRow` 公演
- **構成** 先頭=リードバー。題=公演名 (DAY1 など)。副題=日付・会場・開演時刻。末尾=参加の札 / `.chevron`。
- **置き換えるもの** イベント詳細の公演行、`DayEntryRow` の公演。

### 5.6 `ImasSetlistRow` セトリの 1 曲
- **構成** 先頭=曲順 (`M01` は 15pt 等幅、MC・幕間は札)。題=曲名。副題=歌唱者 (`ImasPerformerChip` を折り返す、6 人を超えたら「全員」や人数)。下段=札 (ユニット・全員・カバー・一部・主演・ゲスト) と事実 (初披露・N 回目・回収)。
- **状態** 通常 / 自分が回収した (✓) / 未回収 (下段に「未回収」) / 欠席者を含む (欠席の人は薄字 + 取り消し線)。
- **置き換えるもの** `SetlistRowView`、`SetlistSimpleRowView`。

### 5.7 `ImasRankingRow` 順位
- **構成** 先頭=順位 (1〜3 は `accent`、4 位以下は `ink3`、等幅 17pt)。ジャケ/アバター 44。題・副題。末尾=`.metric` (票・回数)。任意で行の下端に割合の細い線 (`ImasProportionLine`)。
- **使う** 投票の結果、披露回数ランキング、殿堂。

### 5.8 `ImasForecastRow` 予想・機械予測の曲
- **構成** 先頭=順位。ジャケ 48。題=曲名。副題=根拠 1 行 (「オリメン 2/3 出演」など。名前は `ImasPerformerChip`)。末尾=確率 (`ImasMetric` 20pt 等幅) と、みんなの予想は票数と「予想する」ボタン。行の下端に確率の長さの `ImasProportionLine`。
- **見た目の約束** 推測であることを示すため、確率は「%」付きで出し、事実の行 (セトリ) と同じ札を使わない。
- **使う** 公演の「セトリ予想」「機械予測」、マイ予想。

### 5.9 `ImasValueRow` 項目と値
- **構成** 左=項目名 (15pt 灰)。右=値 (15pt 墨、等幅にしたい数字は `.mono`)。末尾=なし / `.chevron` (値が押せるときは値を `accent` に)。
- **種類** 1 行 (既定) / 長い値は `.expandable` (省略されているときだけ開閉が出る)。
- **振る舞い** 長押しで値をコピー (既定 ON)。
- **使う** 楽曲情報、会場・キャパ・日付、チケット価格、プロフィール。
- **置き換えるもの** `ImasLabeledRow` (改名)、`PersonalEventDetailView` の縦積みの項目。

### 5.10 `ImasNavRow` 入口の行
- **構成** 先頭=`.iconTile` (任意)。題。末尾=値 (任意) + `.chevron`。
- **使う** 設定、マイページ、ハブの入口の一覧、フォームから細かい選択へ進むとき。

### 5.11 `ImasToggleRow` / `ImasMenuRow` / `ImasStepperRow`
- 設定・絞り込み・フォームのスイッチ・選択肢・数。中身は OS の `Toggle` / `Picker(.menu)` / `Stepper` で、題と補足 (`subtitle`) の文字だけ部品が揃える。

### 5.12 `ImasActionRow` 行の形のボタン
- **種類** `.standard` (「＋ 曲を追加」など、文字は `accent`) / `.destructive` (「このライブを削除」、文字は `danger`)。
- **使う** フォームの最後の削除、一覧の末尾の追加。

### 5.13 `ImasSelectableRow` 選べる行
- 先頭に `ImasSelectionMark`。行のどこを押しても選択が切り替わる。複数選択は ○/✓、1 つ選択は ✓ のみ。
- **置き換えるもの** `VenuePickerView`・`ListPickerView` の素の checkmark、`SongSearchPickerView` の `DS.pick` 流用、`EventAttendanceSheet`・`TicketBackfillView`・`StoreOrderImportView` の自前トグル。

### 5.14 `ImasRecordRow` 記録 (編集履歴・お知らせ・支出)
- **構成** 先頭=`.iconTile` (種類ごとの記号と色)。題=何をしたか。副題=誰が・いつ (相対時刻)。下段=操作の札 (追加・変更・削除・差し戻し)。
- **置き換えるもの** `MyEditsView` と `RecentEditsView` の記録カード・アイコン・op バッジ (重複していた 2 系統)。

---

## 6. カード・格子・タイル

### 6.1 `ImasCard`
- **用途** 行でない中身を 1 つの面にまとめる (説明・グラフ・プレビュー)。
- **種類** `.standard` (`surface`) / `.tinted` (`heroSurface`、実体色の薄い地。次の出演・担当など) / `.inset` (`surface2`、カードの中の囲み)。
- **余白** 16。角丸 `DS.rCard` (inset は `rInner`)。
- **やらない** 左端に色の縦棒を付ける (色を示すなら `ImasLeadBar` の行にする) / 影を付ける / カードの中にカード。

### 6.2 `ImasCardList`
- 行をカードに入れる。区切り線は行が決める。
- **置き換えるもの** `ImasListContainer` (改名)、List の行ごとの `clipShape` で角を作る疑似グループ (EventListView・FilteredShowsView)。

### 6.3 `ImasFeatureCard` 主役のカード
- **用途** ハブの最上段で「いま一番大事なもの」を 1 枚で見せる (担当アイドル、次のライブ、開催中のお題、つづきから)。
- **構成** 上=目印 (「担当」「あと 37 日」など 12pt 太字・`accent`)。題 (17〜22pt 太字)。要点 1 行。下=ボタン 1〜2 個 (`ImasButton` の主と副)。左上に画像 (アバター・ジャケ) を置ける。
- **地** `.tinted` (実体の色)。固定のグラデーションは使わない。
- **置き換えるもの** プロデュースの担当カード・次のライブ・投票のピンク紫グラデ、アイドル詳細の「次の出演」、ゲームの「つづきから」。

### 6.4 `ImasEntryCard` 入口のカード
- **構成** `.iconTile` (44) + 題 + 1〜2 行の説明 + 矢印。
- **使う** ハブで奥の画面へ行く入口を大きく見せたいとき (一覧で十分なら `ImasNavRow`)。

### 6.5 `ImasStatTile` / `ImasStatGrid` 数のタイル
- **構成** `.iconTile` (28) + 数 (`ImasMetric` 大) + 単位 + 名前。奥へ行けるときは右上に矢印。
- **並べ方** `ImasStatGrid` で 2 列 (3 個なら 3 列)。高さは揃う (数は折り返さず縮む)。

### 6.6 格子のセル
- `ImasIdolCell` — アバター 56 + 名前 (2 行まで)。4 列。
- `ImasArtworkCell` — ジャケ + 曲名/アルバム名。3 列。
- `ImasBrandCell` — ブランドのアイコン 48 + 名前。ゲームの設定・絞り込みのブランド選び。

---

## 7. 入力

| 部品 | 用途 | 中身 |
|---|---|---|
| `ImasSearchField` | 一覧をその場で絞る (ナビバーの中) | 虫眼鏡 + 入力 + ⊗。高さ 44 カプセル。日本語入力の確定を壊さないよう ⊗ は常に置いて見た目だけ消す |
| `ImasFilterField` | 絞り込みシートの「名前で絞り込み」 | 絞り込み記号 + 入力 + ⊗ |
| `ImasTextFieldRow` | フォームの 1 行入力 | 項目名 + 入力 + 入力の下に誤りの文 (`danger` 13pt) |
| `ImasTextAreaRow` | 複数行 (メモ・説明・補足) | プレースホルダ + 文字数 |
| `ImasAmountField` | 金額 (収支) | 「¥」+ 等幅数字 + 桁区切り |
| `ImasDateRow` | 日付・時刻 | OS の DatePicker (compact) |
| `ImasColorPicker` | タグの色など | 色の丸 + 選んだ色に ✓、色名を読み上げ |
| `ImasBrandPicker` | ブランドを選ぶ (ゲーム・絞り込み) | `ImasBrandCell` の格子 + 「すべて」 |

**検索と絞り込みは別物** — 虫眼鏡はアプリで 1 つ (横断検索 `UnifiedSearchView`、結果は push)。一覧を絞るのは `ImasSearchField` と絞り込みシート。

---

## 8. 選ぶ・切り替える・印を付ける

### 8.1 `ImasTabs` (ImasSegmented)
- **用途** 1 つの画面の中で表示を切り替える (詳細のタブ、月/週、今後/開催済み、アイドル/ユニット)。
- **決まり** 2〜4 個。1 つの文言は全角 6 文字まで。選んだ方は白い面 + 墨の文字 (実体色は塗らない)。
- **使わない** 一覧を絞る → `ImasFilterChip` / 別の画面へ行く → `ImasNavRow`。

### 8.2 チップ
| 部品 | 押せる | 用途 | 見え方 |
|---|---|---|---|
| `ImasChip` | いいえ | 情報の小さな札 (ブランド・種類) | 32pt カプセル、`fill` 地・灰文字 (または実体色の淡い地) |
| `ImasFilterChip` | 押すと選択が切り替わる | 絞り込み・カテゴリ・歌唱メンバーの予想 | 未選択 = `fill` 地、選択 = `accent` 塗り + `onAccent` 文字。先頭にアバター 20 や色の点を置ける |
| `ImasRemovableChip` | 押すと外れる | 効いている絞り込み、選んだもの | 実体色の淡い地 + 末尾 × |

- チップは全部 32pt のカプセル、文字 14pt 中太、左右 12。**チップの大きさを画面で変えない。**
- 並べ方: 1 段で横スクロール (`ImasChipRow`) か、折り返し (`ImasChipFlow`)。2 段以上の横スクロールはしない。

### 8.3 `ImasSelectionMark`
- 複数選択 = ○ と塗りの ✓、1 つ選択 = ✓ だけ。色は実体の `accent` (無ければ `DS.sys`)。

### 8.4 印 `ImasMarkToggle` / `ImasMarkBar`
- **印の種類** 担当 (♥・`DS.pick`) / お気に入り (★・`DS.favorite`) / 参加 (✓) / 所有 / メモ / 座席。
- **`ImasMarkBar`** 詳細の頭の下に印のタイル (56pt 角、文字付き) を横に並べる。ON は実体の `accent` 塗り。
- **`ImasMarkToggle`** 1 つだけ置くとき (ヒーローの中・行の末尾)。
- **置き換えるもの** `UserMarkBar`、アイドル詳細のヒーローのピル型トグル、`MyPickToggleButton`、`EventReleasesSection` の所有トグル。

---

## 9. ボタン

| 役割 | 見え方 | 使う所 |
|---|---|---|
| `.primary` 主 | 塗り (`accent`、実体が無い画面は `DS.sys`) + `onAccent` 文字 | 画面で一番大事な操作。**1 画面に 1 つ** |
| `.secondary` 副 | `fill` 地 + 墨文字 (実体がある画面は `chipBg` 地 + `chipText`) | 主の隣、または単独の操作 |
| `.plain` 文字 | 地なし、`accent` 文字 | 「すべて見る」、補助の操作 |
| `.destructive` 破壊 | `danger` 文字 (地は副と同じ) | 削除・取り消し (確認とセット) |

| 大きさ | 高さ | 文字 | 使う所 |
|---|---|---|---|
| `.large` | 50 | 17pt 太字 | 画面の下に固定する主ボタン、空状態の操作、ゲームの開始 |
| `.medium` | 40 | 15pt 太字 | カードの中、ヒーローの中 |
| `.small` | 32 | 13pt 太字 | 行の中 (「予想する」)、ログインの誘い |

- 形はすべて**カプセル**。横幅は `.large` は画面いっぱい、ほかは中身なりか、2 つ並べるときは等分。
- **状態** 通常 / 押下 (0.97 に縮む) / 無効 (地を薄く) / 読み込み中 (文字の代わりにくるくる、幅は変えない)。
- `ImasIconButton` — 記号だけのボタン。32 / 44 の丸。月の送り・再生・閉じる (ステージ)。
- `ImasPressStyle` — 押せるカード・セル用。押すと 0.97 に縮んで少し暗くなる。

**ツールバー** (`ImasToolbarItem`)
| 場所 | 中身 |
|---|---|
| タブ直下の左 | 設定 (歯車) |
| 一覧の右 | 絞り込み (効いている数のバッジ)・追加・その他 (…、2 つ以上はまとめる) |
| 詳細の右 | 共有・その他 |
| シートの左 | 閉じる / キャンセル |
| シートの右 | 保存 / 送信 / 完了 / 適用 |

文字のボタンの文言は §16 の表から選ぶ。ツールバーの色は白黒 (アプリの tint は `DS.sys`、担当色テーマを有効にしたときだけ担当色)。

---

## 10. 札・数字・小物

### 10.1 `ImasBadge` 状態の札 (押せない)
- 20pt の小さいカプセル、11pt 太字。**押せるものには使わない** (押せるならチップ)。
| 種類 | 見え方 | 例 |
|---|---|---|
| `.role(.unit)` | 実体色の淡い地 + 実体色 | ユニット |
| `.role(.all)` | `fill` + 灰 | 全員 |
| `.role(.cover)` | `pick` の淡い地 | カバー |
| `.role(.partial)` | `warning` の淡い地 | 一部 |
| `.role(.lead)` | `accent` 塗り | 主演 |
| `.role(.guest)` | 線だけ | ゲスト |
| `.status(.positive)` | `success` の淡い地 + `successInk` | 参加済・当選・回収 |
| `.status(.attention)` | `warning` の淡い地 | 受付中・締切間近・下書き |
| `.status(.negative)` | `danger` の淡い地 | 落選・中止・差し戻し |
| `.status(.neutral)` | `fill` + 灰 | 終了・未定・配信・LV |
| `.new` | `accent` 塗り | NEW |
- **置き換えるもの** `ImasTagChip`、手書きの Capsule 63 か所 (参加チップ・受付段階・回収要約・タグ票数・タグのカテゴリ・凡例など)。

### 10.2 `ImasMetric` 数字
- 数字 + 単位。数字は等幅 (SF Pro の細長い太字、ゲームのステージと同じ系統)、単位は小さい灰。
| 大きさ | 数字 | 使う所 |
|---|---|---|
| `.large` | 30pt | 統計タイル、回収率 |
| `.medium` | 20pt | 行の末尾 (票・確率・回数) |
| `.small` | 15pt | 曲順・下段の回数 |
- 1〜3 位など強調するときだけ `accent`。

### 10.3 媒体
| 部品 | 大きさ | 決まり |
|---|---|---|
| `ImasAvatar` | 24 / 32 / 40 / 56 / 88 | 画像が無ければモノグラム (淡い実体色の面 + 実体色の名前)。担当は二重輪。輪のぶんの外形は常に確保 |
| `ImasUnitAvatar` / `ImasAvatarStack` | 24〜40 | 重ねは 4 人まで + 「+N」 |
| `ImasArtwork` | 40 / 48 / 72 / 160 | 画像が無ければブランド色の面 + 曲名。角丸は大きさの 18% |
| `ImasIconTile` | 28 / 32 / 36 / 44 / 56 | 記号を淡い実体色の角丸四角に入れる。角丸は大きさの 28% |
| `ImasSwatch` | 8 (点) / 16 / 28 | 色の丸。読み上げは色名 |
| `ImasLeadBar` | 幅 3 | ライブ・公演の行頭。合同は色を縦に分ける |
| `ImasPerformerChip` | 高さ 24 | 歌唱者 1 人 (色の点 + 名前)。欠席は薄字 + 取り消し線 |

### 10.4 メーター
| 部品 | 用途 |
|---|---|
| `ImasStatBar` | 項目ごとの割合 (ブランド別の回収率) |
| `ImasProportionLine` | 行の下端の細い線 (票・確率の大きさ) |
| `ImasProgressRing` | 1 つの割合を大きく (回収率・習熟度) |
| `ImasMeter` | 段階 (習熟度の 10 段・クイズの点数) |

---

## 11. 状態とお知らせ

| 状況 | 部品 | 文言の型 |
|---|---|---|
| 一覧を初めて読む | `ImasSkeleton(.list / .grid)` | — |
| 画面全体を読む | `ImasLoadingState` | — |
| 区画だけ読む | `ImasInlineLoading` | — |
| 保存・送信中 | `.imasSavingOverlay(isSaving, label:)` | 「保存中」「送信中」 |
| 何もない | `ImasEmptyState(.empty)` | 「まだ〇〇がありません」+ 次にできること |
| 絞って 0 件 | `ImasEmptyState(.noResults)` | 「見つかりません」+「絞り込みを解除」 |
| 読めなかった | `ImasEmptyState(.failed(retry:))` | 「読み込めませんでした」+「もう一度」 |
| ログインが要る (画面全体) | `ImasEmptyState(.signInRequired)` | 「〇〇にはログインが必要です」+「ログイン」 |
| ログインが要る (区画) | `ImasSignInPrompt` | 同上を 1 行で |
| 注意させたい | `ImasNotice(.info / .warning / .error / .success)` | 何が起きたか + どうすればいいか (+ ボタン 1 つ) |
| 補足 | `ImasNote` | 囲まない灰色の文 |
| 操作の失敗 | `.imasErrorAlert($error)` | 何ができなかったか + 理由 |
| 消す前の確認 | `.imasConfirmDestructive` | 「〇〇を削除しますか？」/「削除」「キャンセル」 |

- `ImasStateContainer(state:)` が読み込み・空・失敗・中身を出し分ける。画面で `if isLoading { ProgressView() }` を書かない。
- `ImasNotice` と `ImasNote` の使い分け: 読まなくても困らない説明は `ImasNote`。読まないと困る (候補が足りなくて始められない、取得に失敗した、オフライン) ときだけ `ImasNotice`。
- 絵文字を画面の文言に入れない。記号は SF Symbols。

---

## 12. ステージ (ゲームの遊ぶ画面と結果)

ゲーム中だけはライブ会場の暗いステージにする。ライト/ダークで反転させない固定の配色 (`Stage.*`)。

| 部品 | 用途 |
|---|---|
| `StageScaffold` | 背景・ナビバー (× と題と点数)・タブバーを隠す |
| `StageTitle` / `StageScore` | 「ゲーム名 / Q.04 / 10」「SCORE 300」 |
| `StageProgress` | ペンライトが 1 本ずつ灯る進み具合 (20 問を超えたら線のメーター) |
| `StageTicket` | 問題とヒントを載せる生成りのチケット |
| `StageChoiceGrid` / `StageChoiceButton` | 2〜4 択 |
| `StageVerdict` | 正解・不正解 |
| `StageResult` | GRADE・SCORE・段階・見直す |
| `StageRoundButton` | 40 の丸 (×・共有) |

- 書体: 数字は SF Pro の細長い太字・等幅、英字の小さい見出しは SF Mono。
- 押したとき: `ImasPressStyle` (0.97)。ゲームごとの押し心地は作らない。
- **イントロドンもこのステージに揃える** (イントロドン専用の左上だけ丸い角・独自の押し心地・独自の進捗バーはやめる)。
- 設定画面は通常の画面: `ImasSetupHeader` (記号 + 題 + 説明) → `ImasBrandPicker` → 区画 → `ImasCandidateCount` (候補の数) → 足りないとき `ImasNotice(.warning)` → 画面の下に `ImasButton(.primary, .large)`「はじめる」。

---

## 13. 共有画像 (印刷物)

画面ではなく 1 枚の画像なので、アプリの部品ではなく `ShareCard*` の決まりで作る。

- `ShareCardScaffold` — 地 (ほぼ黒)・余白・見出しの書体 (明朝)・アプリ名の帯。`.photo` (写真の上に文字) / `.solo` (1 人・1 曲) / `.poster` (ランキング・ティアー表)。
- 文字と色は `ShareInk` / `ShareCardPalette` だけ。固定のキャンバスなので固定の pt を使ってよい (例外として許可)。
- **置き換えるもの** ソートメーカーとティアー表の独自の組み、クイズの共有画像の別系統。

---

## 14. 早見表 (〜したい → この部品)

| したいこと | 部品 |
|---|---|
| 曲・アイドル・ライブ・公演・ユニットを並べる | `ImasSongRow` / `ImasIdolRow` / `ImasEventRow` / `ImasShowRow` / `ImasUnitRow` |
| セトリを並べる | `ImasSetlistRow` |
| 順位を見せる | `ImasRankingRow` |
| 予想・機械予測を見せる | `ImasForecastRow` |
| 「項目: 値」を見せる | `ImasValueRow` |
| 別の画面へ進む入口 | 一覧なら `ImasNavRow`、ハブで大きく見せるなら `ImasEntryCard` |
| いま一番大事なものを 1 枚で | `ImasFeatureCard` |
| 数を見せる | `ImasStatTile` (`ImasStatGrid`) / 行の末尾なら `ImasMetric` |
| 割合を見せる | `ImasStatBar` / `ImasProgressRing` / `ImasProportionLine` |
| オンオフ (設定) | `ImasToggleRow` |
| 担当・お気に入り・参加・メモを付ける | `ImasMarkBar` (詳細) / スワイプ (一覧) |
| 一覧を絞る | `ImasSearchField` (名前) / `ImasFilterChip` / 絞り込みシート |
| 効いている絞り込みを見せて外させる | `ImasFilterBar` + `ImasRemovableChip` |
| 画面の中で表示を切り替える | `ImasTabs` |
| 状態を示す | `ImasBadge` |
| 画面の主な操作 | `ImasButton(.primary)` (1 画面に 1 つ) |
| 補足する | `ImasNote` |
| 注意させる | `ImasNotice` |
| 待たせる | `ImasSkeleton` / `ImasLoadingState` / `ImasInlineLoading` / `.imasSavingOverlay` |
| 何もない・見つからない・失敗した | `ImasEmptyState` |
| ログインが要る | `ImasSignInPrompt` / `ImasEmptyState(.signInRequired)` / `LoginToEditSheet` |
| 消す前に確かめる | `.imasConfirmDestructive` |
| 1 つ・複数を選ばせる | 選択シート (`IdolPickerView` ほか) + `ImasSelectableRow` |
| 歌唱者を見せる・予想させる | `ImasPerformerChip` / `ImasFilterChip(leading: .avatar)` |

---

## 15. 部品を足す・変えるとき

1. 既存の部品の「種類」で表せないか先に見る (新しい部品より種類を足す方がよい)。
2. `ImasLiveDB/DesignSystem/Components/` に足す。冒頭のコメントに **用途 / 使わない場面 / 構成 / 種類 / 状態** を書く (この文書の節と同じ順)。
3. 部品カタログ (`DesignCatalogView`) に全種類・全状態を足す。ライトとダーク、文字サイズ最大でも崩れないことを見る。
4. Android の `ui/designsystem/` に同じ名前・同じ見た目で足す。
5. この文書に 1 節足し、早見表に 1 行足す。

`tools/check_ds_usage.sh` が止めるもの (`DesignSystem/`・`Stage`・`ShareCard` の中は除く)。
今ある手書き (2026-10-01 時点 135 ファイル・1,137 行) は `tools/ds_usage_baseline.tsv` に載せてあり、
**ファイルごとに増えたときだけ** CI (`.github/workflows/ds-guard.yml`) で落ちる。画面を部品に移して減ったら
`bash tools/check_ds_usage.sh --update` で基準を下げる。該当行は `--list <file>` で出る。
- `cornerRadius:` に数字、`.padding(` / `spacing:` に数字、`.font(.imasScaled(` / `.font(.system(` / `.font(.caption)` 等の直書き
- `Color(red:` / `Color(hex` / `.white` / `.black` / `Color.accentColor` / `.foregroundStyle(.secondary)`
- `Capsule()` / `RoundedRectangle(` の直書き (形は部品が持つ)
- `.alert("エラー"` (→ `.imasErrorAlert`)、`ProgressView()` の直書き (→ 状態の部品)
- `Divider()` の直書き (→ 行が持つ区切り線)

---

## 16. 文言の決まり

**シートのボタン**
| 場面 | 左 | 右 |
|---|---|---|
| 編集・追加 (端末やマスタに残る) | キャンセル | 保存 |
| 投稿・投票・修正リクエスト (みんなに見える) | キャンセル | 送信 |
| 選ぶ (複数) | キャンセル | 完了 |
| 絞り込み | リセット | 適用 |
| 読むだけのシート | — | 閉じる |
| 後で答えてよい問いかけ (チケット代の記録など) | あとで | 記録する |

「やめる」「決定」「OK」(アラート以外) は使わない。文言と置き場所は `.imasSheetToolbar(.edit / .submit / .select / .read)` が決める (画面で「閉じる」「完了」を書かない)。iOS 26 では OS のガラスのボタン (確定は白黒の塗り) になる。

**確認とエラー**
- 確認の題: 「〇〇を削除しますか？」(疑問符は全角)。ボタン: 「削除」(破壊) / 「キャンセル」。印を外すときは「取り消す」(「参加を取り消す」)。
- エラーの題: 「〇〇できませんでした」。本文: 理由 + 次にすること。「エラー」だけの題は使わない。

**日付と数**
| もの | 書き方 |
|---|---|
| 日付 (今年) | 11月7日(土) |
| 日付 (年をまたぐ・一覧の見出しが年でない) | 2026年11月7日(土) |
| 期間 | 11月7日(土)〜8日(日) |
| 時刻 | 18:00 開演 |
| 相対 | 3分前・5時間前・昨日・3日前 (7 日を超えたら日付) |
| 数 | 3 桁区切り。単位は数字の後ろに小さく (89回・2,051件・55,000人) |
| お金 | ¥15,800 |
| 残り | あと 37 日 |

ISO 形式 (2026-11-07) は画面に出さない。

**言葉**
担当 (推しとは書かない) / オリメン / 全体曲 / ユニット曲 / ソロ曲 / 披露 / 回収 (現地で聴けた) / 現地・配信・LV / 公演 (DAY1) / ライブ (催し全体) / セトリ / 歌唱者。
