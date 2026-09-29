# imas-core

ImasLiveDB の共有ドメインコア。iOS (Swift) / Android (Kotlin) から UniFFI 経由で同じロジックを呼ぶ。
方式検討と移行計画は [docs/SHARED_CORE_STUDY.md](../docs/SHARED_CORE_STUDY.md)。

## 規約

- ここに置けるのは **OS SDK / UI / DB エンジンに依存しない純粋ロジックのみ** (docs/ARCHITECTURE.md の Domain 核と同じ)
- 「現在時刻」等の環境値は関数引数で受け取る (テストで境界を再現するため)。既定値の注入は各プラットフォームの薄いラッパが担う
- iOS / Android のラッパは呼び口だけ。判定・計算をラッパに書いたら負け (二重管理が再発する)

## ビルド

生成物 (xcframework / .so / 両言語バインディング) はすべて git 管理外。クリーンチェックアウト後は一度これを実行する:

```bash
./imas-core/build.sh
```

前提: rustup (`aarch64-apple-ios{,-sim}` `x86_64-apple-ios` `{aarch64,x86_64}-linux-android`), cargo-ndk, Android NDK, Xcode。
Rust だけ触るなら `cargo test` で完結する (クロスビルド不要)。

## テストの分担

- **Rust (`cargo test`)**: ロジック本体の単体テスト。ここが一次
- **iOS `ImasLiveDBTests` / Android JVM テスト**: FFI 疎通の確認 (既存のプラットフォームテストがラッパ経由で同じ判定を検証する)
