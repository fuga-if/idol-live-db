#!/bin/bash
# imas-core (Rust) を iOS xcframework + Android jniLibs + 両言語バインディングにビルドする。
#
# 生成物 (すべて git 管理外・ビルド時に再生成):
#   build/imas-core/ImasCore.xcframework          … iOS リンク対象
#   build/imas-core/swift/imas_core.swift          … Swift バインディング (XcodeGen が sources に含める)
#   ImasLiveDB-Android/app/src/main/jniLibs/<abi>/libimas_core.so
#   ImasLiveDB-Android/app/src/main/kotlin/uniffi/imas_core/imas_core.kt … Kotlin バインディング
#
# 前提: rustup (targets: aarch64-apple-ios{,-sim}, {aarch64,x86_64}-linux-android), cargo-ndk, NDK
set -euo pipefail
cd "$(dirname "$0")/.."  # リポジトリルート
source "$HOME/.cargo/env"

CRATE=imas-core
OUT=build/imas-core
ANDROID_APP=ImasLiveDB-Android/app

# NDK の所在を自動解決 (未設定時)。sdk.dir は Android 側 local.properties と同じ既定を辿る
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  for sdk in "${ANDROID_HOME:-}" /opt/homebrew/share/android-commandlinetools "$HOME/Library/Android/sdk"; do
    [[ -d "$sdk/ndk" ]] || continue
    ANDROID_NDK_HOME="$sdk/ndk/$(ls "$sdk/ndk" | sort -V | tail -1)"
    export ANDROID_NDK_HOME
    break
  done
fi
[[ -d "${ANDROID_NDK_HOME:-}" ]] || { echo "NDK が見つからない。ANDROID_NDK_HOME を設定するか sdkmanager 'ndk;27.2.12479018' を実行" >&2; exit 1; }

echo "==> host ビルド (バインディング生成用 cdylib)"
cargo build --manifest-path $CRATE/Cargo.toml --release
HOST_DYLIB=$CRATE/target/release/libimas_core.dylib

echo "==> バインディング生成 (Swift + Kotlin)"
rm -rf $OUT/swift $OUT/headers
mkdir -p $OUT/swift $OUT/headers
# uniffi-bindgen は cwd の Cargo.toml から crate 情報を引くため crate 内から実行する
(cd $CRATE && cargo run --release --bin uniffi-bindgen -- \
  generate --library target/release/libimas_core.dylib --language swift --out-dir ../$OUT/swift)
(cd $CRATE && cargo run --release --bin uniffi-bindgen -- \
  generate --library target/release/libimas_core.dylib --language kotlin --out-dir ../$ANDROID_APP/src/main/kotlin)
# ヘッダと modulemap は xcframework 側に同梱する (Swift ファイルだけ sources に残す)
mv $OUT/swift/imas_coreFFI.h $OUT/headers/
mv $OUT/swift/imas_coreFFI.modulemap $OUT/headers/module.modulemap

echo "==> iOS ビルド (device + simulator universal)"
cargo build --manifest-path $CRATE/Cargo.toml --release --target aarch64-apple-ios
cargo build --manifest-path $CRATE/Cargo.toml --release --target aarch64-apple-ios-sim
cargo build --manifest-path $CRATE/Cargo.toml --release --target x86_64-apple-ios
mkdir -p $CRATE/target/ios-sim-universal
lipo -create \
  $CRATE/target/aarch64-apple-ios-sim/release/libimas_core.a \
  $CRATE/target/x86_64-apple-ios/release/libimas_core.a \
  -output $CRATE/target/ios-sim-universal/libimas_core.a

echo "==> xcframework 作成"
rm -rf $OUT/ImasCore.xcframework
xcodebuild -create-xcframework \
  -library $CRATE/target/aarch64-apple-ios/release/libimas_core.a -headers $OUT/headers \
  -library $CRATE/target/ios-sim-universal/libimas_core.a -headers $OUT/headers \
  -output $OUT/ImasCore.xcframework

echo "==> Android ビルド (arm64-v8a + x86_64)"
(cd $CRATE && cargo ndk \
  -t arm64-v8a -t x86_64 \
  -o ../$ANDROID_APP/src/main/jniLibs \
  build --release)

echo "==> 完了"
