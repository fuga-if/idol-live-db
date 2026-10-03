# Android のリリース (Google Play)

Play への上げは `tools/play_release.py` (Android Publisher API v3) で行う。Play Console の画面で AAB を手で上げない。
公開 (ロールアウト) を押すのはオーナーが確認してから。スクリプトの既定は「本番トラックに下書き」で止まる。

## 鍵

- サービスアカウントの JSON: `~/keys/play-publisher.json` (リポジトリには置かない)。
  別の場所なら `--key` か環境変数 `PLAY_PUBLISHER_KEY`。
- サービスアカウント: `play-publisher@intro-ec837.iam.gserviceaccount.com` (イントロクイズと共用)。
- Play Console の「ユーザーと権限」で、このアカウントに本アプリ (`site.fugaapp.imaslivedb`) の
  リリース権限を付けておく。付いていないと API は 403 `The caller does not have permission` を返す。
- 依存: `google-auth` / `google-api-python-client` (`python3 -m pip install google-api-python-client google-auth`)。

## 手順

1. バージョンを上げる: `ImasLiveDB-Android/app/build.gradle.kts` の `versionCode` (+1) と `versionName` (iOS に揃える)。
   アプリ内のお知らせ (`ui/settings/Announcements.kt`) に、iOS のお知らせのうち Android にある機能の分を足す。
2. 共有コアを作る: `cd imas-core && ./build.sh --android-only` (jniLibs の `libimas_core.so` を作り直す)。
3. 署名の材料: `ImasLiveDB-Android/local.properties` (`RELEASE_*`) と `app/release.keystore`。
   どちらも gitignore 済みで、worktree には本体の checkout からコピーする。
4. ビルド:
   ```sh
   cd ImasLiveDB-Android
   ./gradlew testDebugUnitTest bundleRelease -Pkotlin.daemon.jvmargs=-Xmx4g
   ```
   Kotlin デーモンの既定ヒープ (2GB) だと R8 前の Compose コンパイルで OutOfMemory になることがある。
   出力は `app/build/outputs/bundle/release/app-release.aab`。`jarsigner -verify` で署名を確かめる。
5. リリースノートを書く。Play Console と同じ形で、1 言語 500 字まで (スクリプトが超過を弾く):
   ```
   <ja-JP>
   ...
   </ja-JP>
   <en-US>
   ...
   </en-US>
   ```
6. 上げる (本番に下書き):
   ```sh
   python3 tools/play_release.py upload ImasLiveDB-Android/app/build/outputs/bundle/release/app-release.aab \
       --notes release_notes.txt
   python3 tools/play_release.py status   # 置かれたか確認
   ```
7. オーナーが Play Console の本番 → 下書きのリリースを開き、確認してロールアウトする (審査に回る)。
   段階公開にするならそこで割合を決める。API で進めるなら
   `--status inProgress --fraction 0.2` (全員なら `--status completed`)。

## 経緯

- 2026-10: クローズドテスト (versionCode 5 / 2.1.0) を経て、初の本番は 2.3.0 / versionCode 6。
