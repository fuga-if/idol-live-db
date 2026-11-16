#!/usr/bin/env bash
# Android の画面で、関数の中の関数 (ローカル関数) を `::save` の形でボタン等に渡していないかのチェック。
#
# `::save` の参照は、中で使っている値 (入力中の題など) が違っても「同じ関数」として等しくなる。
# Compose は引数が等しいと部品を描き直さないので、ボタンが古い参照を持ち続け、押すと古い値が送られる。
# 実例: お題の投稿で、題を 1 文字打った時点の参照が残り、題が「あ」だけで投稿された (2026-11-16)。
# 渡すときは `{ save() }` / `{ x -> pick(x) }` のラムダにする (ラムダは値が変わると作り直される)。
#
#   bash tools/check_compose_local_fn_refs.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ROOT='ImasLiveDB-Android/app/src/main/kotlin/com/fugaif/imaslivedb'
failed=0
while IFS= read -r f; do
    # 字下げされた `fun name(` = 関数の中の関数 (クラスのメンバーも当たるが、
    # その時もラムダで渡せば害はない)。
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        hits=$(grep -nE "(=|\(|,) *::${name}\b *([,)]|$)" "$f" | grep -vE "\.(let|map|mapNotNull|flatMap|filter|forEach|mapTo|also|run|takeIf)\( *::${name}" || true)
        if [[ -n "$hits" ]]; then
            echo "❌ $f: ローカル関数 ${name} を ::${name} で渡しています" >&2
            echo "$hits" | sed 's/^/    /' >&2
            failed=1
        fi
    done < <(grep -oE '^ {4,}(private )?(suspend )?fun [a-z][A-Za-z0-9_]*\(' "$f" | sed -E 's/.*fun ([A-Za-z0-9_]+)\(/\1/' | sort -u || true)
done < <(find "$ROOT/ui" "$ROOT/widget" -name '*.kt' 2>/dev/null | sort)

if [[ "$failed" -ne 0 ]]; then
    echo "→ { name() } のラムダで渡してください (古い値が送られるのを防ぐ)。" >&2
    exit 1
fi
echo "✅ ローカル関数の ::参照 をボタン等に渡している所はありません"
