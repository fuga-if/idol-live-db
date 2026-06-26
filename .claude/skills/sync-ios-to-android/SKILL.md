---
name: sync-ios-to-android
description: iOS (ImasLiveDB) の変更を Android 版 (ImasLiveDB-Android) に1:1で移植する。iOSを直した直後や「Androidにも反映して」「横展開して」と言われたときに使う。ファイル/コンポーネント構成を iOS と揃えてあるので、同じ場所に同じ差分を当てる。引数で対象(画面名やファイル)を指定可、省略時は直近の git 差分から推測。
---

# sync-ios-to-android

iOS (`ImasLiveDB/`) の変更を Android (`ImasLiveDB-Android/`) に移植する。**Android は iOS とファイル/
コンポーネント構成・デザインシステムを1:1で揃えてある**ので、「同じ意味の変更を同じ場所に当てる」のが基本。

> Android は CloudKit を**ネイティブではなく Web Services (REST + public API token)** で読む。集計系コミュニティ
> (タグ/投票/ポール) は **Worker D1** REST。個人マーク (担当/お気に入り) は iOS と同じく**端末ローカルのみ**(同期しない)。

## 0. まず何が変わったかを把握

```bash
cd (リポジトリルート)
git log --oneline -10            # iOS側の直近変更
git show --stat HEAD             # 変更ファイル
```

引数で対象が指定されていればそれを、なければ iOS 側の差分ファイルから対応する Android ファイルを決める。

## 1. ファイル対応表 (iOS → Android)

| iOS | Android |
|---|---|
| `DesignSystem/DesignTokens.swift` (DS) | `ui/theme/Color.kt` の `object DS` |
| `DesignSystem/ImasTheme.swift` (無限色エンジン) | `ui/theme/ImasTheme.kt` (`ImasTheme.derive` / `ColorMath`、HSL+WCAG を1:1移植) |
| `DesignSystem/ImasComponents.swift` | `ui/components/ImasComponents.kt` (Avatar/Artwork/SectionHeader/StatTile/Segmented/LeadBar/LabeledRow/EmptyState/MetricBadge/StatBar/RankingRow) |
| `App/ContentView.swift` (TabView 5タブ) | `ui/navigation/AppNavigation.kt` + `BottomNavBar.kt` + `NavRoutes.kt` |
| `Views/Calendar/CalendarView.swift` | `ui/schedule/CalendarScreen.kt` + `CalendarViewModel.kt` (月/週) |
| `Views/Components/DetailSheet.swift` の `SongSheetContent` | `ui/songs/SongDetailScreen.kt` (hero + ImasSegmented[情報・歌唱/披露履歴/コミュニティ]) |
| `Views/Idols/IdolDetailView.swift` | `ui/idols/IdolDetailScreen.kt` (hero + [ライブ/楽曲・ユニット/プロフィール]) |
| `Views/Idols/IdolListView.swift` | `ui/idols/IdolListScreen.kt` (ブランド別 + ImasAvatar 行) |
| `Views/Songs/SongListView.swift` / `SongRowView.swift` | `ui/songs/SongListScreen.kt` / `ui/components/SongRow.kt` |
| `Views/Events/EventListView.swift` / `EventDetailView` / `SetlistView` | `ui/events/EventListScreen.kt` / `EventDetailScreen.kt` / `SetlistScreen.kt` |
| `Views/Units/UnitDetailView.swift` | `ui/units/UnitDetailScreen.kt` |
| 統計 | `ui/stats/StatsScreen.kt` (ImasStatBar/ImasRankingRow) |
| 検索 / 設定 | `ui/search/SearchScreen.kt` / `ui/settings/SettingsScreen.kt` |
| ポール/予想 | `ui/polls/PollsScreen.kt` + `data/community/CommunityApi.kt` |
| `Services/CloudKitSyncEngine.swift` / `CKRecordMapper.swift` | `data/sync/CloudKitSyncEngine.kt` / `SyncMappers.kt` / `CloudKitClient.kt` |
| `Services/CommunityAPI.swift` | `data/community/CommunityApi.kt` |
| GRDB Record (`Models/*.swift`) | Room `@Entity` (`data/model/*.kt`) + `data/db/dao/*Dao.kt` |

## 2. 変換ルール (SwiftUI → Compose)

- **SF Symbol** (`systemImage:"mic.fill"`) → Material `ImageVector` (`Icons.Filled.Mic`)。無ければ近い名前を選ぶ。
- **Nuke/LazyImage** → Coil `SubcomposeAsyncImage` (`ImasAvatar`/`ImasArtwork` が内包)。
- **`.imasTitle2`/`.imasSubhead`** 等のフォント → `fontSize`(sp) を `DesignTokens.swift` の値で (title2=22, headline=17, body=17, subhead=15, footnote=13, caption=12)。
- **色は必ず `ImasTheme.derive(seed=アイドル色, brand=ブランド色)` から**。`DS.ink/ink2/ink3/surface/fill/sep/pick/favorite` を直接。素の `Color`/`MaterialTheme.colorScheme.primary` は使わない。
- **CloudKit フィールドは camelCase** (`brandId`), **Worker D1 の JSON は snake_case** (`vote_count`, `my_tag_ids`, `top_sets`)。マッパーで取り違えない。
- **ViewModel は `_uiState.value` を直読みする関数を Composable から呼ばない** (Compose が依存追跡できず空表示になる)。**収集した `state` から純粋に算出**する。
- スキーマ(`@Entity`/`@Database`)を変えたら **version を上げる**。`fallbackToDestructiveMigration` で DB が消えるが、`CloudKitSyncEngine` は **brandCount==0 なら強制フル同期**するので再投入される。

## 3. CloudKit/スキーマを変えた場合 (新カラム等)

iOS の `CKRecordMapper` にフィールドが増えたら Android も:
1. `data/model/*.kt` の `@Entity` にカラム追加。
2. `data/db/AppDatabase.kt` の `version` を +1。
3. `SyncMappers.kt` のマッパーに `r.str("camelField")` 追加。
4. (新テーブルなら) `SyncDao` に upsert、`CloudKitSyncEngine` の `steps` にステップ追加、`AppDatabase` の entities に登録。

## 4. ビルド & 実機検証 (必須)

```bash
cd ImasLiveDB-Android
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

./gradlew assembleDebug --no-daemon 2>&1 | grep -E "BUILD|error:|^e: "   # ビルド

# エミュは HW アクセラレーション必須 (swiftshader だと詳細画面で ANR)
adb devices | grep -q emulator || nohup emulator -avd Pixel_8 -no-snapshot -no-audio -gpu host >/tmp/emu.log 2>&1 &
adb wait-for-device
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.fugaif.imaslivedb/.MainActivity
# 該当画面へ遷移 → adb exec-out screencap -p > /tmp/s.png → sips -Z 1200 で縮小して目視
```

- 初回/スキーマ更新後はフル同期 (約2分・117k件) を待ってから確認。
- エミュDB を見たいとき: `adb shell run-as com.fugaif.imaslivedb cat databases/master.sqlite{,-wal,-shm}` を全部 pull して sqlite3 (WAL 込み)。

## 5. コミット

- **mainに直接コミット** (PR/ブランチ無し)。1機能=1コミット。
- keystore / token / 認証情報は `local.properties` (git管理外)。`*.keystore` は `.gitignore` 済。
- リリース: `local.properties` に `RELEASE_STORE_FILE/PASSWORD/KEY_ALIAS/KEY_PASSWORD` + `app/release.keystore`。
  `versionCode` を上げて `./gradlew assembleRelease` で署名済みAPK。

## 注意

- iOS にあって Android に**まだ無い機能** (画像ギャラリー/ウィジェット/編集フロー等) は、対応する Android 基盤が無ければ無理に作らず、ユーザーに「基盤から作るか」を確認する。
- 関連メモリ: `project_android_cloudkit_sync` (Android の現状・既知バグ・ビルド環境)。
