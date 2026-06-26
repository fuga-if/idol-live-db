package com.fugaif.imaslivedb.data.sync

import com.fugaif.imaslivedb.BuildConfig

/**
 * CloudKit Web Services の接続設定。
 *
 * Android は iOS のネイティブ CloudKit と異なり、CloudKit Web Services (REST) の
 * public database を **read-only の CloudKit API token** で読む。public DB の
 * レコードは world-readable なのでユーザ認証 (ckWebAuthToken) は不要。
 *
 * API_TOKEN の発行手順:
 *   CloudKit Dashboard (icloud.developer.apple.com) → 対象コンテナ →
 *   Tokens → API Tokens → 新規作成 (用途は read。Sign in callback は Post Message、URL空でよい)。
 *   発行された token を **local.properties** に `cloudkit.api.token=...` として設定する
 *   (git 管理外。build.gradle.kts が BuildConfig.CLOUDKIT_API_TOKEN へ注入)。
 *   CI 等では環境変数 CLOUDKIT_API_TOKEN でも可。
 *
 * S2S サーバ鍵 (eckey.pem / CLOUDKIT_KEY_ID) とは別物。S2S 鍵はクライアントに
 * 埋め込んではいけない。この API token は public read 専用なので APK 埋め込み可
 * (ただしソース直書き/コミットは避け、ビルド時注入にする)。
 */
object CloudKitConfig {
    const val BASE = "https://api.apple-cloudkit.com"
    const val CONTAINER = "iCloud.com.fugaif.ImasLiveDB"
    const val ENV = "production"

    /** local.properties / 環境変数からビルド時に注入される public read 用 API token。 */
    val API_TOKEN: String = BuildConfig.CLOUDKIT_API_TOKEN

    val isConfigured: Boolean get() = API_TOKEN.isNotBlank()
}
