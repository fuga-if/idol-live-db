import Foundation

/// 担当(推し)カラーをアプリ全体テーマに使うときの、保存すべき値の解決。
///
/// 解決規則の本体は imas-core (Rust) の `domain/oshi_theme_resolution.rs` にある。
/// 「OFF のときは色だけ消して選択 ID は残す」「選択中の担当が外れていたら先頭へ
/// 黙って寄せる」という 2 つの非自明な判断とその理由もそちらに記載。
/// 結果型 `OshiThemeResolution` (idolId が nil = 現在の選択を変更しない) と
/// 射影型 `OshiThemePickIdol` は uniffi 生成バインディングが提供する。
///
/// ここは `Idol` を判定に要る 2 フィールド (id / color) の射影へ落として
/// 1 回の FFI 呼び出しへ委譲するだけの薄いラッパ。
/// 引数ラベルを `picks` にしているのは、生成バインディングの同名関数 (`pickIdols:`) と
/// ラベルまで同じにすると空配列リテラルで型推論が曖昧になるため。
func resolveOshiTheme(
    isEnabled: Bool,
    currentIdolId: String,
    picks: [Idol]
) -> OshiThemeResolution {
    resolveOshiTheme(
        isEnabled: isEnabled,
        currentIdolId: currentIdolId,
        pickIdols: picks.map { OshiThemePickIdol(id: $0.id, color: $0.color) }
    )
}
