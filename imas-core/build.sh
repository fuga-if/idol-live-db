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

# ディレクトリを中身ごと消す。`rm -rf` を使わないのは、環境によってはブロックされていて
# **黙って残る**ため (実際それで古い xcframework を掴んだ)。chmod + find なら同じ結果になる。
remove_dir() {
  [[ -d "$1" ]] || return 0
  chmod -R u+w "$1"
  find "$1" -delete
}

# 成果物の置き場所は cargo に訊く。`$CRATE/target` と決め打ちすると、CARGO_TARGET_DIR や
# 別の場所への共有で target が移ったとき、古い成果物を黙って読む。
TARGET_DIR=$(cargo metadata --locked --format-version 1 --no-deps --manifest-path $CRATE/Cargo.toml |
  sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')
[[ -n "$TARGET_DIR" ]] || { echo "cargo metadata から target_directory を読めない" >&2; exit 1; }

echo "==> host ビルド (バインディング生成用 cdylib)"
# 下の bindgen の bin と同じ feature で作る (feature が違うと cargo run がライブラリを作り直す)。
cargo build --locked --manifest-path $CRATE/Cargo.toml --release --features bindgen
HOST_DYLIB=$TARGET_DIR/release/libimas_core.$HOST_EXT

echo "==> バインディング生成 (Swift + Kotlin)"
# uniffi-bindgen は cwd の Cargo.toml から crate 情報を引くため crate 内から実行する
if [[ $DO_IOS -eq 1 ]]; then
  # 掃除は再生成する側だけ。ここを無条件にしていたので --android-only が
  # iOS のバインディングを消して、Xcode ビルドが出来ない状態にしていた。
  remove_dir $OUT/swift
  remove_dir $OUT/headers
  mkdir -p $OUT/swift $OUT/headers
  (cd $CRATE && cargo run --locked --release --features bindgen --bin uniffi-bindgen -- \
    generate --library "$HOST_DYLIB" --language swift --out-dir ../$OUT/swift)
fi
if [[ $DO_ANDROID -eq 1 ]]; then
  (cd $CRATE && cargo run --locked --release --features bindgen --bin uniffi-bindgen -- \
    generate --library "$HOST_DYLIB" --language kotlin --out-dir ../$ANDROID_APP/src/main/kotlin)
fi
if [[ $DO_IOS -eq 1 ]]; then
# ヘッダと modulemap は xcframework 側に同梱する (Swift ファイルだけ sources に残す)
mv $OUT/swift/imas_coreFFI.h $OUT/headers/
mv $OUT/swift/imas_coreFFI.modulemap $OUT/headers/module.modulemap

echo "==> iOS ビルド (device + simulator universal)"
cargo build --locked --manifest-path $CRATE/Cargo.toml --release --target aarch64-apple-ios
cargo build --locked --manifest-path $CRATE/Cargo.toml --release --target aarch64-apple-ios-sim
cargo build --locked --manifest-path $CRATE/Cargo.toml --release --target x86_64-apple-ios
mkdir -p $TARGET_DIR/ios-sim-universal
lipo -create \
  $TARGET_DIR/aarch64-apple-ios-sim/release/libimas_core.a \
  $TARGET_DIR/x86_64-apple-ios/release/libimas_core.a \
  -output $TARGET_DIR/ios-sim-universal/libimas_core.a

echo "==> xcframework 作成"
# 既存を消してから作る。`xcodebuild -create-xcframework` は上書きせず
# 「同名の項目が既にあります」で止まるが、**そのとき終了コードは 0**。
# つまり消し損ねると、古い xcframework が残ったまま「成功」に見える
# (コアを直したのにアプリに反映されない、という形で後から効いてくる)。
remove_dir $OUT/ImasCore.xcframework
xcodebuild -create-xcframework \
  -library $TARGET_DIR/aarch64-apple-ios/release/libimas_core.a -headers $OUT/headers \
  -library $TARGET_DIR/ios-sim-universal/libimas_core.a -headers $OUT/headers \
  -output $OUT/ImasCore.xcframework

# 終了コードが当てにならないので、出来上がりを自分で確かめる。
for slice in ios-arm64 ios-arm64_x86_64-simulator; do
  if [[ ! -f $OUT/ImasCore.xcframework/$slice/libimas_core.a ]]; then
    echo "xcframework の $slice が作られていない" >&2
    exit 1
  fi
done
fi

if [[ $DO_ANDROID -eq 1 ]]; then
  echo "==> Android ビルド (arm64-v8a + x86_64)"
  (cd $CRATE && cargo ndk \
    -t arm64-v8a -t x86_64 \
    -o ../$ANDROID_APP/src/main/jniLibs \
    build --locked --release)
fi

echo "==> 完了 ($([[ $DO_IOS -eq 1 ]] && echo -n "iOS ")$([[ $DO_ANDROID -eq 1 ]] && echo -n "Android"))"
