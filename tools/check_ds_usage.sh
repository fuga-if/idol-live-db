#!/usr/bin/env bash
# 画面のコードに「その場限りの見た目」を書いていないかのチェック (docs/DESIGN_SYSTEM.md §15)。
#
# 画面は DesignSystem の部品だけで組む。色・文字の大きさ・余白・角丸の数字や、形・影・グラデーション・
# 素の色の名前・素の進捗や区切り線を書いたら止める。iOS と Android を同じ決まりで見る。
#   iOS:     ImasLiveDB/Views・App・ウィジェット (Capsule / RoundedRectangle / Circle・ProgressView / Divider ほか)
#   Android: ui・widget (RoundedCornerShape / CircleShape・sp と dp の数字・Material の見た目の部品ほか)
#
# 今ある手書きは tools/ds_usage_baseline.tsv に「ファイルごとの行数」として載せてあり、
# **増えたときだけ** 落とす (移した分だけ減らしていく。減ったら --update で書き直す)。
#
#   bash tools/check_ds_usage.sh            # 検査 (CI と同じ)
#   bash tools/check_ds_usage.sh --update   # 基準を今の数に書き直す (減らしたとき)
#   bash tools/check_ds_usage.sh --list <file>  # そのファイルの該当行を出す
#
# 対象外: DesignSystem/ (部品の中身)、配色の定義 (Android の ui/theme・ウィジェットの WidgetTheme)、
#         共有画像 (固定キャンバスなので固定 pt を許す)、クイズのステージの配色定義、部品カタログ。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
BASELINE="tools/ds_usage_baseline.tsv"

# ---- iOS (Swift) ----
# 1 行に 1 つでも当たればその行を数える。
PATTERN='cornerRadius: *[0-9]'
PATTERN+='|\.padding\(([^)]*, *)?[0-9]+(\.[0-9]+)?\)'
PATTERN+='|spacing: *[1-9][0-9]*(\.[0-9]+)?[,)]'
PATTERN+='|\.font\(\.imasScaled\(|\.font\(\.system\(|\.font\(\.(largeTitle|title|title2|title3|headline|body|callout|subheadline|footnote|caption|caption2)\)'
PATTERN+='|Color\(red:|Color\(hex|Color\.accentColor|\.foregroundStyle\(\.(secondary|primary|tertiary)\)'
PATTERN+='|(Color)?\.(white|black)([^A-Za-z]|$)'
PATTERN+='|Capsule\(\)|RoundedRectangle\('
PATTERN+='|\.alert\("エラー"|ProgressView\(\)|ProgressView\(value:|[^A-Za-z]Divider\(\)'
# 記号を色の丸に入れる・影・グラデーション・素の色の名前 (部品が持つもの)
PATTERN+='|Circle\(\)|\.shadow\(|(Linear|Radial|Angular)Gradient\(|\.gradient\b'
PATTERN+='|(Color\.|foregroundStyle\(\.|foregroundColor\(\.|tint\(\.|fill\(\.|background\(\.)(red|green|blue|orange|purple|pink|yellow|gray|mint|teal|cyan|indigo|brown)\b'
# 選択の印の手書き (ImasSelectionMark の写し)
PATTERN+='|"checkmark\.circle\.fill" *: *"circle"'

EXCLUDE='/DesignSystem/|/Views/Share/|ShareCard|QuizStage\.swift|TierListExport\.swift|DesignCatalog'

# ---- Android (Kotlin) ----
ANDROID_ROOT='ImasLiveDB-Android/app/src/main/kotlin/com/fugaif/imaslivedb'
# 色: hex・成分からの色・素の色の名前・Material の配色/書体/形のトークン (DS.* と ImasType から引く)
KT_PATTERN='Color\(0x|Color\((red|green|blue) *=|Color\.(hsv|hsl)\('
KT_PATTERN+='|Color\.(White|Black|Red|Green|Blue|Yellow|Gray|Cyan|Magenta|LightGray|DarkGray)([^A-Za-z]|$)'
KT_PATTERN+='|MaterialTheme\.(colorScheme|typography|shapes)'
# 文字: sp の数字・その場の TextStyle
KT_PATTERN+='|[0-9]\.sp([^A-Za-z]|$)|TextStyle\('
# 余白: padding / contentPadding / spacedBy / Spacer に dp の数字
KT_PATTERN+='|padding\([^)]*[0-9]\.dp|PaddingValues\([^)]*[0-9]\.dp'
KT_PATTERN+='|spacedBy\( *[0-9]+(\.[0-9]+)?\.dp|Spacer\(.*(height|width|size)\( *[0-9]+(\.[0-9]+)?\.dp'
# 形・影・グラデーション (部品が持つもの)
KT_PATTERN+='|RoundedCornerShape\(|CircleShape|CutCornerShape\(|cornerRadius\( *[0-9]'
KT_PATTERN+='|\.shadow\(|[Ee]levation *= *[1-9]|Brush\.(linear|radial|sweep|horizontal|vertical)Gradient'
# 素の区切り線・進捗・「エラー」だけの題 (→ 行が持つ区切り線・状態の部品・ImasErrorAlert)
KT_PATTERN+='|(^|[^A-Za-z])(HorizontalDivider|VerticalDivider|Divider|CircularProgressIndicator|LinearProgressIndicator)\('
KT_PATTERN+='|Text\("エラー"\)'
# Material の見た目の部品 (同じ役目の部品がある: ImasCard・ImasChip・ImasButton・ImasSwitch)
KT_PATTERN+='|(^|[^A-Za-z.])(Card|ElevatedCard|OutlinedCard|FilterChip|AssistChip|InputChip|SuggestionChip|Button|TextButton|OutlinedButton|FilledTonalButton|ElevatedButton|Switch)\('

KT_EXCLUDE='/ui/designsystem/|/ui/theme/|/ui/share/|ShareCard|TierListExportSheet\.kt|/ui/games/QuizStage\.kt|/widget/WidgetTheme\.kt'

files() {
    {
        find ImasLiveDB/Views ImasLiveDB/App ImasLiveDBWidget -name '*.swift' | grep -Ev "$EXCLUDE"
        find "$ANDROID_ROOT/ui" "$ANDROID_ROOT/widget" -name '*.kt' | grep -Ev "$KT_EXCLUDE"
    } | sort
}

pattern_for() {
    case "$1" in
        *.kt) echo "$KT_PATTERN" ;;
        *) echo "$PATTERN" ;;
    esac
}

# 該当行 (行番号つき)。import の行は使っている所ではないので数えない。
matches() {
    grep -nE "$(pattern_for "$1")" "$1" | grep -vE '^[0-9]+:import ' || true
}

count_file() {
    matches "$1" | grep -c . || true
}

if [[ "${1:-}" == "--list" ]]; then
    matches "$2"
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
        matches "$f" | sed 's/^/    /' >&2
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
