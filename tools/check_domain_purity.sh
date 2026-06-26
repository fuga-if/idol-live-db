#!/usr/bin/env bash
# Domain 層の純粋性チェック (Hexagonal の依存方向ガード)。
#
# Domain (Ports / UseCases / Entities) は SwiftUI / GRDB / CloudKit を import しない。
# import すると Presentation/Adapters への依存が逆流し「なんちゃってレイヤー」になる。
# 詳細は docs/ARCHITECTURE.md「レイヤ違反の検査」。
#
# 使い方: Scripts/check_domain_purity.sh   (リポジトリルートから)
# pre-commit / CI に組み込む候補。違反があれば exit 1。
set -euo pipefail

DOMAIN_DIR="ImasLiveDB/Domain"
FORBIDDEN='^import (SwiftUI|GRDB|CloudKit)'

if [[ ! -d "$DOMAIN_DIR" ]]; then
    echo "error: $DOMAIN_DIR が見つかりません (リポジトリルートで実行してください)" >&2
    exit 2
fi

violations=$(grep -rnE "$FORBIDDEN" "$DOMAIN_DIR" || true)

if [[ -n "$violations" ]]; then
    echo "❌ Domain 純粋性違反: 以下のファイルが SwiftUI/GRDB/CloudKit を import しています" >&2
    echo "$violations" >&2
    echo "→ 永続化/UI 依存は Adapters 側へ。Domain は Foundation のみに保つこと。" >&2
    exit 1
fi

echo "✅ Domain 純粋: $DOMAIN_DIR に SwiftUI/GRDB/CloudKit の import なし"
