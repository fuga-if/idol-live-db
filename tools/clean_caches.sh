#!/usr/bin/env bash
# 使い終わった worktree と、再生成できるビルドの残りかすを片付ける。
#
#   bash tools/clean_caches.sh           # 消す候補と大きさを出すだけ (何も消さない)
#   bash tools/clean_caches.sh --yes     # 消す
#
# Claude Code の SessionEnd フックから --yes で呼ぶ (設定は本体の .claude/settings.local.json)。
#
# 消す worktree (.claude/worktrees の下) は次を全部満たすものだけ:
#   - ロックされていない
#   - 未コミットの変更が無い (無視ファイルは見ない)
#   - HEAD が develop / main (ローカルか origin) に取り込み済み
#   - 中をカレントにしているプロセスが無い
#   - その worktree のセッション記録 (~/.claude/projects/<パス>) と git の index が
#     $WT_IDLE_HOURS 時間 (既定 48) 以上更新されていない
#     (ロックはセッションが動いている間しか付かず、スレッドは日をまたいで再開されるので、
#      ロックとプロセスだけでは使用中を判定できない)
# どれかを外れる worktree は残す。消えるのは取り込み済みの履歴だけなので、作業は失われない。
#
# ほかに消すもの:
#   - 本体 build/ の古いビルド出力 (imas-core / Export / asc / *.xcarchive 以外)
#   - XcodeBuildMCP の作業場のうち、もう無い worktree のもの
#   - 利用できなくなったシミュレータ
# 共有置き場 (target-shared・~/Library/Caches/imas-live-db) は使い回すので消さない。
set -euo pipefail

APPLY=0
WT_IDLE_HOURS="${WT_IDLE_HOURS:-48}"
BUILD_IDLE_HOURS="${BUILD_IDLE_HOURS:-6}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) APPLY=1 ;;
    *) echo "知らない引数: $1" >&2; exit 2 ;;
  esac
  shift
done

MAIN="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
WT_ROOT="$MAIN/.claude/worktrees"
MCP_WS="$HOME/Library/Developer/XcodeBuildMCP/workspaces"
now=$(date +%s)

# idle <時間> <パス>...: どのパスも <時間> 以上更新されていない
idle() {
  local sec=$(($1 * 3600)) p
  shift
  for p in "$@"; do
    [[ -e "$p" ]] || continue
    [[ $((now - $(stat -f %m "$p"))) -ge $sec ]] || return 1
  done
}

# worktree のセッション記録のうち最新のもの (Claude Code は英数字以外を - にした名前で置く)
transcript() {
  local dir="$HOME/.claude/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$1")"
  [[ -d "$dir" ]] && ls -td "$dir" "$dir"/* 2>/dev/null | head -1
}

merged() {
  local head="$1" ref
  for ref in develop main origin/develop origin/main; do
    git -C "$MAIN" rev-parse -q --verify "$ref^{commit}" >/dev/null || continue
    git -C "$MAIN" merge-base --is-ancestor "$head" "$ref" && return 0
  done
  return 1
}

# いま誰かがカレントにしている場所 (動いているセッション・シェル)
busy_cwds="$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' || true)"
in_use() { awk -v p="$1" '$0 == p || index($0, p "/") == 1 { f = 1 } END { exit !f }' <<<"$busy_cwds"; }

worktrees=()
dirs=()

# --- worktree ---
path="" head="" locked=0
flush() {
  [[ -n "$path" && "$path" == "$WT_ROOT"/* && -d "$path" ]] || return 0
  [[ $locked -eq 1 ]] && return 0
  in_use "$path" && return 0
  [[ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ]] || return 0
  merged "$head" || return 0
  idle "$WT_IDLE_HOURS" "$(git -C "$path" rev-parse --path-format=absolute --git-dir)/index" \
    "$(transcript "$path")" || return 0
  worktrees+=("$path")
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; path="${line#worktree }" head="" locked=0 ;;
    "HEAD "*) head="${line#HEAD }" ;;
    locked*) locked=1 ;;
  esac
done < <(git -C "$MAIN" worktree list --porcelain)
flush

# --- 本体 build/ の古い出力 ---
if [[ -d "$MAIN/build" ]]; then
  for d in "$MAIN/build"/*; do
    [[ -e "$d" ]] || continue
    case "$(basename "$d")" in
      imas-core|Export|asc|*.xcarchive) continue ;;
    esac
    idle "$BUILD_IDLE_HOURS" "$d" && dirs+=("$d")
  done
fi

# --- XcodeBuildMCP の作業場 (名前は <worktree 名>-<hash>) ---
if [[ -d "$MCP_WS" ]]; then
  for d in "$MCP_WS"/bridge-cse_*; do
    [[ -e "$d" ]] || continue
    name="$(basename "$d")"
    live=0
    [[ -d "$WT_ROOT/${name%-*}" ]] && live=1
    for w in ${worktrees[@]+"${worktrees[@]}"}; do
      [[ "$(basename "$w")" == "${name%-*}" ]] && live=0
    done
    [[ $live -eq 0 ]] && idle "$BUILD_IDLE_HOURS" "$d" && dirs+=("$d")
  done
fi

if [[ ${#worktrees[@]} -eq 0 && ${#dirs[@]} -eq 0 ]]; then
  echo "片付けるものは無い。"
else
  echo "消す候補:"
  du -sh ${worktrees[@]+"${worktrees[@]}"} ${dirs[@]+"${dirs[@]}"} 2>/dev/null | sort -h
fi
df -h /System/Volumes/Data | tail -1

if [[ $APPLY -eq 0 ]]; then
  echo
  echo "消すには: bash tools/clean_caches.sh --yes"
  exit 0
fi

wipe() { chmod -R u+w "$1" 2>/dev/null || true; find "$1" -delete; }

for w in ${worktrees[@]+"${worktrees[@]}"}; do
  git -C "$MAIN" worktree remove --force "$w" 2>/dev/null || true
  [[ -e "$w" ]] && wipe "$w"
done
for d in ${dirs[@]+"${dirs[@]}"}; do wipe "$d"; done
git -C "$MAIN" worktree prune
xcrun simctl delete unavailable 2>/dev/null || true

echo
echo "片付けた。"
df -h /System/Volumes/Data | tail -1
