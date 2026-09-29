#!/usr/bin/env bash
# worktree ごとにビルド出力を作らず、1 か所の共有置き場へ向ける。冪等。
#
#   bash tools/link_shared_build_dirs.sh [checkout のパス]   # 省略時はカレント
#
# Claude Code の SessionStart フックから毎回呼ぶ (設定は本体の .claude/settings.local.json)。
# worktree 1 個につき cargo の target が 2GB、Gradle の app/build が 0.5〜1GB、
# DerivedData が 2〜3GB できて、並列セッションでディスクが埋まっていた。
#
# 向け先:
#   imas-core/target              -> <本体>/target-shared   (cargo は自前でロックする)
#   ImasLiveDB-Android/app/build  -> $SHARED/gradle/app
#   ImasLiveDB-Android/build      -> $SHARED/gradle/root
#   Xcode の DerivedData は -derivedDataPath "$SHARED/DerivedData" で渡す
#   (XcodeBuildMCP は環境変数 XCODEBUILDMCP_DERIVED_DATA_PATH で同じ所を向く)。
#
# imas-core/target を CARGO_TARGET_DIR で向けないのは、build.sh が target/release を
# 相対参照していて bindgen が落ちるため。リンクなら両立する。
#
# 共有なので、別 worktree で同時に Gradle / xcodebuild を回すとぶつかる
# (xcodebuild は "database is locked" で落ちる)。落ちたら待って回し直す。
set -euo pipefail

REPO="$(git -C "${1:-$PWD}" rev-parse --show-toplevel)"
MAIN="$(cd "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
SHARED="${IMAS_SHARED_BUILD_ROOT:-$HOME/Library/Caches/imas-live-db}"

link() {
  local at="$REPO/$1" to="$2"
  [[ -d "$(dirname "$at")" ]] || return 0
  mkdir -p "$to"
  [[ -L "$at" && "$(readlink "$at")" == "$to" ]] && return 0
  if [[ -d "$at" && ! -L "$at" ]]; then
    chmod -R u+w "$at"
    find "$at" -delete
  fi
  /bin/rm -f "$at"
  ln -s "$to" "$at"
}

link imas-core/target "$MAIN/target-shared"
link ImasLiveDB-Android/app/build "$SHARED/gradle/app"
link ImasLiveDB-Android/build "$SHARED/gradle/root"
mkdir -p "$SHARED/DerivedData"
