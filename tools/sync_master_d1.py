#!/usr/bin/env python3
"""マスタ (db/master.sql) を公開データ API の D1 (imas-master-db) に全置き換えで流す。

  python3 tools/sync_master_d1.py --local            # ローカル D1 (wrangler dev が読む) に流す。既定
  python3 tools/sync_master_d1.py --remote           # 流すコマンドを表示するだけ
  python3 tools/sync_master_d1.py --remote --yes     # 本番 D1 に流す (オーナーだけが打つ)

入力の master.sql (どれか 1 つ。既定は --from-bot):
  --from-bot         bot/data-refresh の最新の db/master.sql (git fetch して git show)。既定。
                     日次の CloudKit 書き出しのうち、FK 検査を通ったもの
  --from-cloudkit    いま CloudKit (production) から書き出す。tools/export_cloudkit.py を呼ぶ。
                     鍵が要る (--key-file か tools/eckey.pem、CLOUDKIT_KEY_ID)。
                     オーナーが CloudKit に push した直後に即反映したいとき。FK 検査はしないので
                     `bash tools/build_db.sh` 相当の検査を自分で通すこと
  --from-develop     develop の db/master.sql。古いことがあるので、最終更新日を出して警告する
  --master-sql PATH  この master.sql をそのまま使う (CI が export の artifact を渡す)

やること:
  1. imas-core の web-export (`--api-sql`) で SQL を組む。文書は agent::tools と同じ規則を通る。
  2. `wrangler d1 execute imas-master-db --file` で流す。SQL は表を DROP → CREATE → INSERT
     し直す全置き換えなので、何度流しても同じ結果になる。
  3. meta.version (日付 + 組んだ SQL の内容ハッシュ) が新しくなり、エッジのキャッシュ鍵が
     切り替わる (古い応答は 1 時間で消える)。

D1 の無料枠は 1 日の書き込み 10 万行。1 回の同期で書く行数は --count で見られる
(docs/ARCHITECTURE-data-api.md)。1 日に何度も流さないこと。

毎日の同期は GitHub Actions (.github/workflows/refresh-data.yml の sync-data-api) が
`--remote --yes --master-sql db/master.sql` で行う。手元から打つのは緊急用。

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
BUILD = os.path.join(API, ".build")
SQL = os.path.join(BUILD, "master-d1.sql")
INPUT = os.path.join(BUILD, "master-input.sql")  # --from-* で取ってきた入力の置き場 (gitignore の .build)
BOT_REF = "bot/data-refresh"
MASTER_PATH = "db/master.sql"
DB_NAME = "imas-master-db"


def run(cmd, cwd):
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def git(*cmd):
    return subprocess.run(["git", *cmd], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def write_input(text):
    os.makedirs(BUILD, exist_ok=True)
    with open(INPUT, "w", encoding="utf-8") as f:
        f.write(text)
    return INPUT


def from_bot():
    run(["git", "fetch", "origin", BOT_REF], ROOT)
    ref = "FETCH_HEAD"
    when = git("log", "-1", "--format=%cI", ref).strip()
    print(f"入力: {BOT_REF} の {MASTER_PATH} (コミット日時 {when})", flush=True)
    return write_input(git("show", f"{ref}:{MASTER_PATH}"))


def from_develop():
    when = git("log", "-1", "--format=%cI", "develop", "--", MASTER_PATH).strip()
    print(f"警告: develop の {MASTER_PATH} は最終更新 {when}。日次の CloudKit 書き出しは "
          f"{BOT_REF} にあり、develop へはオーナーの PR で入るまで古いまま。"
          "CloudKit の最新を反映するなら --from-bot か --from-cloudkit。", file=sys.stderr, flush=True)
    return write_input(git("show", f"develop:{MASTER_PATH}"))


def from_cloudkit(key_file):
    """CloudKit から今書き出す。export_cloudkit.py は作業ツリーの db/master.sql を書き換えるので、
    使い捨ての git worktree で回し、オーナーの作業ツリーには触れない。"""
    import shutil
    import tempfile

    key = os.path.abspath(key_file or os.path.join(ROOT, "tools", "eckey.pem"))
    if not os.path.isfile(key):
        sys.exit(f"CloudKit の鍵が無い: {key} (--key-file で指定)")
    base = from_bot()  # PRESERVED_TABLES は既存の dump から引き継ぐので、土台は bot の最新
    tmp = tempfile.mkdtemp(prefix="imas-ck-")
    wt = os.path.join(tmp, "wt")
    run(["git", "worktree", "add", "--detach", wt, "develop"], ROOT)
    try:
        shutil.copyfile(base, os.path.join(wt, MASTER_PATH))
        run([sys.executable, os.path.join(wt, "tools", "export_cloudkit.py"), "--production",
             "--key-file", key], wt)
        os.makedirs(BUILD, exist_ok=True)
        shutil.copyfile(os.path.join(wt, MASTER_PATH), INPUT)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=ROOT)
        shutil.rmtree(tmp, ignore_errors=True)
    print("注意: CloudKit の書き出しは FK 検査 (tools/build_db.sh) を通していない。", file=sys.stderr)
    return INPUT


def build_sql(master_sql):
    """imas-core の web-export で、master.sql から D1 に流す SQL を組む (`npm run export` と同じ)。"""
    os.makedirs(BUILD, exist_ok=True)
    run(["cargo", "run", "--release", "--locked", "--features", "web-export", "--bin", "web-export", "--",
         "--sql", os.path.abspath(master_sql), "--api-sql", SQL,
         "--work-db", os.path.join(BUILD, "work.sqlite")], os.path.join(ROOT, "imas-core"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    where = ap.add_mutually_exclusive_group()
    where.add_argument("--local", action="store_true", help="ローカル D1 に流す (既定)")
    where.add_argument("--remote", action="store_true", help="本番 D1 (--yes が無ければコマンドを表示するだけ)")
    ap.add_argument("--yes", action="store_true", help="--remote で実際に流す")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--from-bot", action="store_true", help=f"{BOT_REF} の最新の {MASTER_PATH} (既定)")
    src.add_argument("--from-cloudkit", action="store_true", help="CloudKit から今書き出す (鍵が要る)")
    src.add_argument("--from-develop", action="store_true", help=f"develop の {MASTER_PATH} (古いので警告を出す)")
    src.add_argument("--master-sql", metavar="PATH", help="この master.sql を使う")
    ap.add_argument("--key-file", help="--from-cloudkit の CloudKit 秘密鍵 (既定は export_cloudkit.py の既定)")
    ap.add_argument("--skip-export", action="store_true", help="SQL の組み直しを飛ばす (.build/master-d1.sql をそのまま流す)")
    ap.add_argument("--count", action="store_true", help="流さず、書く行数の見積もりだけ出す")
    args = ap.parse_args()

    if not args.skip_export:
        if args.master_sql:
            if not os.path.isfile(args.master_sql):
                sys.exit(f"{args.master_sql} が無い")
            master = args.master_sql
        elif args.from_cloudkit:
            master = from_cloudkit(args.key_file)
        elif args.from_develop:
            master = from_develop()
        else:
            master = from_bot()
        build_sql(master)
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
