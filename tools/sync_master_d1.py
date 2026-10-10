#!/usr/bin/env python3
"""マスタ (db/master.sql) を公開データ API の D1 (imas-master-db) に全置き換えで流す。

  python3 tools/sync_master_d1.py --local            # ローカル D1 (wrangler dev が読む) に流す。既定
  python3 tools/sync_master_d1.py --remote           # 流すコマンドを表示するだけ
  python3 tools/sync_master_d1.py --remote --yes     # 本番 D1 に流す (オーナーだけが打つ)

やること:
  1. imas-core の web-export (`--api-sql`) で SQL を組む。文書は agent::tools と同じ規則を通る。
  2. `wrangler d1 execute imas-master-db --file` で流す。SQL は表を DROP → CREATE → INSERT
     し直す全置き換えなので、何度流しても同じ結果になる。
  3. meta.version が新しくなり、エッジのキャッシュ鍵が切り替わる (古い応答は 1 時間で消える)。

D1 の無料枠は 1 日の書き込み 10 万行。1 回の同期で書く行数は --count で見られる
(docs/ARCHITECTURE-data-api.md)。1 日に何度も流さないこと。

**本番への書き込みは --remote --yes のときだけ。** このスクリプトは D1 を作らない
(`wrangler d1 create imas-master-db` はオーナーが 1 度だけ打ち、database_id を
imas-data-api/wrangler.jsonc に書く)。
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.path.join(ROOT, "imas-data-api")
SQL = os.path.join(API, ".build", "master-d1.sql")
DB_NAME = "imas-master-db"


def run(cmd, cwd):
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    where = ap.add_mutually_exclusive_group()
    where.add_argument("--local", action="store_true", help="ローカル D1 に流す (既定)")
    where.add_argument("--remote", action="store_true", help="本番 D1 (--yes が無ければコマンドを表示するだけ)")
    ap.add_argument("--yes", action="store_true", help="--remote で実際に流す")
    ap.add_argument("--skip-export", action="store_true", help="SQL の組み直しを飛ばす (.build/master-d1.sql をそのまま流す)")
    ap.add_argument("--count", action="store_true", help="流さず、書く行数の見積もりだけ出す")
    args = ap.parse_args()

    if not args.skip_export:
        run(["npm", "run", "--silent", "export"], API)
    if not os.path.isfile(SQL):
        sys.exit(f"{SQL} が無い (--skip-export を外して SQL を組むこと)")

    if args.count:
        counts = {}
        with open(SQL, encoding="utf-8") as f:
            table = None
            for line in f:
                if line.startswith("INSERT INTO "):
                    table = line.split()[2]
                    counts.setdefault(table, 0)
                    if " VALUES (" in line:
                        counts[table] += 1  # 1 文 1 行 (docs)
                elif table and line.startswith("(") :
                    counts[table] += 1
        print(counts, "合計", sum(counts.values()), "行 (索引の書き込みは別)")
        return

    target = "--remote" if args.remote else "--local"
    cmd = ["npx", "wrangler", "d1", "execute", DB_NAME, target, "--file", SQL, "--yes"]
    if args.remote and not args.yes:
        print("本番 D1 には流していません。流すなら次を打つ (オーナー):")
        print("  cd imas-data-api && " + " ".join(cmd))
        print("または: python3 tools/sync_master_d1.py --remote --yes")
        return
    run(cmd, API)


if __name__ == "__main__":
    main()
