# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /path/to/android-sdk/tools/proguard/proguard-android.txt

# Keep Room entities
-keep class com.fugaif.imaslivedb.models.** { *; }
-keep class com.fugaif.imaslivedb.database.** { *; }

# Keep data classes used for Compose
-keep class com.fugaif.imaslivedb.** { *; }

# Coil
-dontwarn coil.**

# Media3 / ExoPlayer
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# --- Rust コア (UniFFI + JNA) ------------------------------------------------
#
# JNA はネイティブ側から `Pointer.peer` などのフィールドを **フィールド ID で直接**
# 触る。R8 がこれを消したり名前を変えたりすると、実行時に
# `UnsatisfiedLinkError: Can't obtain peer field ID for class com.sun.jna.Pointer`
# で JNA の初期化ごと落ちる。
#
# 落ちても SnapshotStore は「SQL 経路のみで継続」に縮退するので**クラッシュしない**。
# そのぶん静かで、release ビルドだけコアが丸ごと死んでいても気付けない
# (あいまい検索・検索ハイライト・スナップショット経由の全クエリが無言で無効になる)。
# 実際に release の新規インストールで踏んで見つけた。
#
# 上の `-keep class com.fugaif.imaslivedb.** { *; }` はアプリのパッケージしか守らない。
# 生成バインディングは `uniffi.imas_core` に居るので別途名指しが要る。
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-keep class uniffi.imas_core.** { *; }
-dontwarn java.awt.**

# Spotify App Remote SDK (app/spotify-sdk)。SDK は Jackson の写像も同梱しているが、使うのは Gson の写像
# (既定)。Jackson と注釈の型は入れていないので、無いことを警告にしない。状態の型は Gson が反射で
# 組むので名前ごと残す (SDK 同梱の規則に加えて、SDK の型を丸ごと残す)。
-dontwarn com.fasterxml.jackson.**
-dontwarn com.spotify.base.annotations.**
-keep class com.spotify.protocol.** { *; }
-keep class com.spotify.android.appremote.** { *; }
