---
name: submit-to-appstore
description: |
  アイドルライブDB (ImasLiveDB) を App Store Connect API で archive → upload → AppStoreVersion 作成 → 審査提出まで一気通貫で実行するスキル。fastlane/bundler を使わず curl+JWT で完結する (bundler バージョン問題を回避)。
  使用タイミング: 「審査出して」「App Store に submit」「本番審査」「リリースして」等。
  破壊的アクション(version作成・submit)はユーザー承認を取ってから実行する。
---

# Submit to App Store — アイドルライブDB 審査提出スキル

archive から審査キュー投入まで CLI(ASC API) で完結。Web UI も fastlane も使わない。

## 前提情報
- **App ID (ASC)**: `6763342297`  / **Bundle ID**: `com.fugaif.ImasLiveDB` / **Team ID**: `GQ3WP34LFW`
- **Project**: `ImasLiveDB.xcodeproj` (xcodegen 生成) / **Scheme**: `ImasLiveDB`
- **Version 設定**: `project.yml` の `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (2箇所・Debug/Release)。変更後は必ず `xcodegen generate`。
- **ASC API key**: Issuer `aac2f8bc-4887-40ed-ab81-0ca8d9ce08c9` / Key `VQ9KQXWKA7` / `/Users/fuga/.appstoreconnect/private_keys/AuthKey_VQ9KQXWKA7.p8`
- **JWT**: Python `pyjwt`+`cryptography` (導入済)。`/tmp/jwt_asc.py` で発行 (20分有効)。
- **ExportOptions**: `build/asc/ExportOptions.plist` (method=app-store-connect, destination=upload, signingStyle=automatic, teamID=GQ3WP34LFW) — destination=upload なので export でアップロードまで完了。

## ワークフロー
1. **現状把握**: JWT発行 → `GET /apps/6763342297/appStoreVersions` と `/builds?filter[app]=6763342297&sort=-uploadedDate` で現行version/最新buildを確認。次の MARKETING_VERSION / CURRENT_PROJECT_VERSION (build番号は単調増加) を決める。
2. **Version bump**: `project.yml` を編集 → `xcodegen generate`。
3. **リリース前チェック (確立手順)**: Release+新規インストールの起動確認は**シミュレータか別端末**で (オーナー実機の担当/お気に入りは端末ローカルのみなので、アンインストールで消える)。内蔵お知らせ(AnnouncementCatalog)と What's New(`fastlane/metadata/{ja,en-US}/release_notes.txt`) を更新。
4. **Archive** (5-10分):
   ```bash
   xcodebuild -project ImasLiveDB.xcodeproj -scheme ImasLiveDB -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/asc/ImasLiveDB-<MV>-<CPV>.xcarchive \
     -allowProvisioningUpdates -authenticationKeyPath /Users/fuga/.appstoreconnect/private_keys/AuthKey_VQ9KQXWKA7.p8 \
     -authenticationKeyID VQ9KQXWKA7 -authenticationKeyIssuerID aac2f8bc-4887-40ed-ab81-0ca8d9ce08c9 archive
   ```
   `** ARCHIVE SUCCEEDED **` を確認。
5. **Export+Upload** (3-5分): 同じ auth key 引数 + `-exportArchive -exportOptionsPlist build/asc/ExportOptions.plist`。`Uploaded ImasLiveDB` + `** EXPORT SUCCEEDED **`。GoogleAppMeasurement の dSYM warning は無害。
6. **Build VALID 待ち** (5-30分): `GET /builds?...` で対象 build の `processingState=VALID` を待ち、build ID を控える。
7. **AppStoreVersion 作成 (★承認)**: `POST /appStoreVersions` (platform IOS, versionString, releaseType: AFTER_APPROVAL=承認後自動公開 / MANUAL=手動公開)。V_ID 取得。
8. **build 紐付け**: `PATCH /appStoreVersions/{V_ID}/relationships/build` (204)。
9. **What's New**: `GET /appStoreVersions/{V_ID}/appStoreVersionLocalizations` で ja/en-US の loc ID を取り、`PATCH /appStoreVersionLocalizations/{id}` で whatsNew 更新 (自動生成されるので POST でなく PATCH)。
10. **reviewSubmission**: `POST /reviewSubmissions` (platform IOS, app) → RS_ID。`POST /reviewSubmissionItems` で appStoreVersion を追加。state=READY_FOR_REVIEW (まだ未提出)。
11. **Submit (★最終承認・取り消し不可)**: `PATCH /reviewSubmissions/{RS_ID}` `{"attributes":{"submitted":true}}` → state=WAITING_FOR_REVIEW。

## JWT スクリプト (/tmp/jwt_asc.py)
```python
import jwt, time
KID="VQ9KQXWKA7"; ISS="aac2f8bc-4887-40ed-ab81-0ca8d9ce08c9"
pk=open("/Users/fuga/.appstoreconnect/private_keys/AuthKey_VQ9KQXWKA7.p8").read()
n=int(time.time())
print(jwt.encode({"iss":ISS,"iat":n,"exp":n+1200,"aud":"appstoreconnect-v1"},pk,algorithm="ES256",headers={"kid":KID,"typ":"JWT"}))
```

## 承認が必要なステップ
- Step7 (version作成 + What's New確認) と Step11 (submit・取り消し不可) は必ずユーザー承認。
- archive/export/upload/build紐付け/localization PATCH は承認不要 (やり直せる)。

## 注意
- fastlane は bundler 2.5.16 ピンで詰まるので使わない (この API 直叩きが正)。
- iOS の担当/お気に入りは iCloud KVS バックアップ対象。リリース前テストでアンインストールするとローカルは消えるが iCloud から復元される (配信は数秒〜遅延あり)。実機の実データでアンインストール検証はしない。
- リジェクト後の再提出は古い reviewSubmissionItem を `removed:true` で外して version を解放してから新規 RS を作る (REMOVED 反映待ち)。
