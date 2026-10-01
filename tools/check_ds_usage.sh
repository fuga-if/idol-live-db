#!/usr/bin/env bash
# 画面のコードに「その場限りの見た目」を書いていないかのチェック (docs/DESIGN_SYSTEM.md §15)。
#
# 画面 (ImasLiveDB/Views・App) は DesignSystem の部品だけで組む。色・文字の大きさ・余白・
# 角丸の数字や、形 (Capsule / RoundedRectangle)・素の ProgressView / Divider を書いたら止める。
#
# 今ある手書きは tools/ds_usage_baseline.tsv に「ファイルごとの行数」として載せてあり、
# **増えたときだけ** 落とす (移した分だけ減らしていく。減ったら --update で書き直す)。
#
#   bash tools/check_ds_usage.sh            # 検査 (CI と同じ)
#   bash tools/check_ds_usage.sh --update   # 基準を今の数に書き直す (減らしたとき)
#   bash tools/check_ds_usage.sh --list <file>  # そのファイルの該当行を出す
#
# 対象外: DesignSystem/ (部品の中身)、共有画像 (固定キャンバスなので固定 pt を許す)、
#         クイズのステージの配色定義、部品カタログ。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
BASELINE="tools/ds_usage_baseline.tsv"

# 1 行に 1 つでも当たればその行を数える。
PATTERN='cornerRadius: *[0-9]'
PATTERN+='|\.padding\(([^)]*, *)?[0-9]+(\.[0-9]+)?\)'
PATTERN+='|spacing: *[1-9][0-9]*(\.[0-9]+)?[,)]'
PATTERN+='|\.font\(\.imasScaled\(|\.font\(\.system\(|\.font\(\.(largeTitle|title|title2|title3|headline|body|callout|subheadline|footnote|caption|caption2)\)'
PATTERN+='|Color\(red:|Color\(hex|Color\.accentColor|\.foregroundStyle\(\.(secondary|primary|tertiary)\)'
PATTERN+='|(Color)?\.(white|black)([^A-Za-z]|$)'
PATTERN+='|Capsule\(\)|RoundedRectangle\('
PATTERN+='|\.alert\("エラー"|ProgressView\(\)|[^A-Za-z]Divider\(\)'

EXCLUDE='/DesignSystem/|/Views/Share/|ShareCard|QuizStage\.swift|TierListExport\.swift|DesignCatalog'

files() {
    find ImasLiveDB/Views ImasLiveDB/App -name '*.swift' | grep -Ev "$EXCLUDE" | sort
}

count_file() {
    grep -cE "$PATTERN" "$1" || true
}

if [[ "${1:-}" == "--list" ]]; then
    grep -nE "$PATTERN" "$2" || true
    exit 0
fi

if [[ "${1:-}" == "--update" ]]; then
    {
        echo -e "# file\tlines  (tools/check_ds_usage.sh が数えた手書きの行。減らしたら --update で書き直す)"
        files | while read -r f; do
            n=$(count_file "$f")
            if [[ "$n" -gt 0 ]]; then echo -e "$f\t$n"; fi
        done
    } > "$BASELINE"
    total=$(grep -v '^#' "$BASELINE" | awk -F'\t' '{s+=$2} END {print s+0}')
    echo "基準を書き直しました: $BASELINE (計 $total 行)"
    exit 0
fi

[[ -f "$BASELINE" ]] || { echo "error: $BASELINE がありません (--update で作る)" >&2; exit 2; }

failed=0
total=0
while read -r f; do
    n=$(count_file "$f")
    total=$((total + n))
    base=$(awk -F'\t' -v f="$f" '$1 == f { print $2 }' "$BASELINE")
    base=${base:-0}
    if [[ "$n" -gt "$base" ]]; then
        echo "❌ $f: 手書きの見た目が $base 行 → $n 行に増えました" >&2
        grep -nE "$PATTERN" "$f" | sed 's/^/    /' >&2
        failed=1
    fi
done < <(files)

if [[ "$failed" -ne 0 ]]; then
    echo "→ 色・文字・余白・角丸・形は DesignSystem の部品で。足りない部品は DesignSystem に足す (docs/DESIGN_SYSTEM.md §15)。" >&2
    exit 1
fi

base_total=$(grep -v '^#' "$BASELINE" | awk -F'\t' '{s+=$2} END {print s+0}')
echo "✅ 手書きの見た目は増えていません (今 $total 行 / 基準 $base_total 行)"
if [[ "$total" -lt "$base_total" ]]; then
    echo "   減った分を基準に反映するには: bash tools/check_ds_usage.sh --update"
fi
