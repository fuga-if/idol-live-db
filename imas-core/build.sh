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
#
# --ios-only:     iOS 側の生成物だけ作る (Android NDK が要らない)。
# --android-only: Android 側の生成物だけ作る (Xcode が要らないので Linux でも回る)。
#
#   CI をこの 2 つに割るため。どちらの CI も生成物が git 管理外なのでコアのビルドが
#   要るが、iOS の runner に NDK を入れるのも Linux で xcframework を作ろうとするのも
#   無駄 (というより後者は不可能)。
set -euo pipefail
cd "$(dirname "$0")/.."  # リポジトリルート
source "$HOME/.cargo/env"

CRATE=imas-core
OUT=build/imas-core
ANDROID_APP=ImasLiveDB-Android/app

DO_IOS=1
DO_ANDROID=1
for arg in "$@"; do
  case "$arg" in
    --ios-only)     DO_ANDROID=0 ;;
    --android-only) DO_IOS=0 ;;
    *) echo "不明な引数: $arg (使えるのは --ios-only / --android-only)" >&2; exit 2 ;;
  esac
done

# バインディング生成に使う host cdylib の拡張子。macOS は .dylib、Linux は .so。
# ここを決め打ちにしていたせいで Linux の CI では動かなかった。
case "$(uname -s)" in
  Darwin) HOST_EXT=dylib ;;
  *)      HOST_EXT=so ;;
esac

# NDK の所在を自動解決 (未設定時)。sdk.dir は Android 側 local.properties と同じ既定を辿る
if [[ $DO_ANDROID -eq 1 && -z "${ANDROID_NDK_HOME:-}" ]]; then
  for sdk in "${ANDROID_HOME:-}" /opt/homebrew/share/android-commandlinetools "$HOME/Library/Android/sdk"; do
    [[ -d "$sdk/ndk" ]] || continue
    ANDROID_NDK_HOME="$sdk/ndk/$(ls "$sdk/ndk" | sort -V | tail -1)"
    export ANDROID_NDK_HOME
    break
  done
fi
if [[ $DO_ANDROID -eq 1 ]]; then
  [[ -d "${ANDROID_NDK_HOME:-}" ]] || { echo "NDK が見つからない。ANDROID_NDK_HOME を設定するか sdkmanager 'ndk;27.2.12479018' を実行" >&2; exit 1; }
fi

echo "==> host ビルド (バインディング生成用 cdylib)"
cargo build --manifest-path $CRATE/Cargo.toml --release
HOST_DYLIB=$CRATE/target/release/libimas_core.$HOST_EXT

echo "==> バインディング生成 (Swift + Kotlin)"
rm -rf $OUT/swift $OUT/headers
mkdir -p $OUT/swift $OUT/headers
# uniffi-bindgen は cwd の Cargo.toml から crate 情報を引くため crate 内から実行する
if [[ $DO_IOS -eq 1 ]]; then
  (cd $CRATE && cargo run --release --bin uniffi-bindgen -- \
    generate --library target/release/libimas_core.$HOST_EXT --language swift --out-dir ../$OUT/swift)
fi
if [[ $DO_ANDROID -eq 1 ]]; then
  (cd $CRATE && cargo run --release --bin uniffi-bindgen -- \
    generate --library target/release/libimas_core.$HOST_EXT --language kotlin --out-dir ../$ANDROID_APP/src/main/kotlin)
fi
if [[ $DO_IOS -eq 1 ]]; then
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
fi

if [[ $DO_ANDROID -eq 1 ]]; then
  echo "==> Android ビルド (arm64-v8a + x86_64)"
  (cd $CRATE && cargo ndk \
    -t arm64-v8a -t x86_64 \
    -o ../$ANDROID_APP/src/main/jniLibs \
    build --release)
fi

echo "==> 完了 ($([[ $DO_IOS -eq 1 ]] && echo -n "iOS ")$([[ $DO_ANDROID -eq 1 ]] && echo -n "Android"))"
