#!/usr/bin/env python3
"""tools/cloudkit_schema.ckdb の変更が「CloudKit へ安全に流せる形か」を確かめる。

    python3 tools/check_ckdb_schema.py                       # 構文だけ見る
    python3 tools/check_ckdb_schema.py --base origin/develop # 基準との差分も見る

CloudKit の Production スキーマは**足すことしかできない** (型や列は一度昇格すると消せない)。
だから PR の段階で「消す・型を変える」を落とし、オーナーが Dashboard で昇格するときに
迷わないようにする。鍵も cktool も要らないので、コントリビューターの手元と CI の両方で回る。

見ること:
  - RECORD TYPE の二重定義が無い (2026-09-13 まで validate も import も通らない状態が放置された)
  - 基準から record type / 列が消えていない、列の型が変わっていない
  - 既存列のインデックス (QUERYABLE 等) が外れていない (差分同期が全件失敗する)
  - 新しい record type が modifiedAt / deletedAt を正しいインデックスで持つ
    (ImasLiveDB/Services/README_CloudKit_Schema.md)
  - (警告のみ) 型と列が export-schema と同じ並び (ASCII 順) になっている。
    ずれていても流せるが、次に export した人の差分が並び替えで埋もれる

GitHub Actions の中では、問題の行に注釈 (::error / ::warning) も付ける。

`--summary <path>` を付けると、オーナーがマージ後にやる手順を Markdown で書き出す
(GitHub Actions の job summary 用)。
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Tuple

REPO = Path(__file__).resolve().parent.parent
CKDB_REL = "tools/cloudkit_schema.ckdb"

# 全 record type が持つべき運用列とインデックス (差分同期・soft delete に要る)。
REQUIRED_FIELDS = {
    "modifiedAt": ("TIMESTAMP", {"QUERYABLE", "SORTABLE"}),
    "deletedAt": ("TIMESTAMP", {"QUERYABLE"}),
}
# アプリが自前で持たない、CloudKit 標準の型 (必須列の検査から外す)。
SYSTEM_TYPES = {"Users"}

_TYPE_RE = re.compile(r"^\s*RECORD TYPE\s+(\w+)\s*\((.*?)\n\s*\);", re.S | re.M)
_FIELD_RE = re.compile(r'^\s*("?[\w]+"?)\s+([A-Z0-9_]+(?:<[A-Z0-9_]+>)?)((?:\s+[A-Z]+)*)\s*,?\s*$')


class Field(NamedTuple):
    type: str
    indexes: frozenset
    line: int = 0  # ckdb 内の行番号 (注釈用。比較には使わない)


class Problem(NamedTuple):
    message: str
    line: int = 0  # 検査したファイルの行番号。0 は行を指せないもの (消えた列など)


Schema = Dict[str, Dict[str, Field]]


def parse(text: str) -> Tuple[Schema, List[str]]:
    """ckdb の本文から {record type: {列名: Field}} と、二重定義された型名を返す。"""
    schema: Schema = {}
    duplicates: List[str] = []
    for m in _TYPE_RE.finditer(text):
        name, body = m.group(1), m.group(2)
        if name in schema:
            duplicates.append(name)
        body_line = text.count("\n", 0, m.start(2)) + 1
        fields: Dict[str, Field] = {}
        for i, line in enumerate(body.splitlines()):
            if not line.strip() or line.strip().startswith("GRANT"):
                continue
            fm = _FIELD_RE.match(line)
            if not fm:
                continue
            col = fm.group(1).strip('"')
            fields[col] = Field(fm.group(2), frozenset(fm.group(3).split()), body_line + i)
        schema[name] = fields
    return schema, duplicates


def check(new: Schema, duplicates: List[str], base: Optional[Schema]) -> Tuple[List[Problem], List[str]]:
    """(エラー, 追加された項目) を返す。エラーが空なら安全に流せる。"""
    errors: List[Problem] = []
    added: List[str] = []

    for name in duplicates:
        errors.append(Problem(
            f"RECORD TYPE {name} が 2 回定義されている (cktool の validate / import が通らない)。"
            " 片方に寄せて 1 つにする"
        ))

    for name, fields in new.items():
        if name in SYSTEM_TYPES or (base is not None and name in base):
            continue
        for col, (typ, need) in REQUIRED_FIELDS.items():
            f = fields.get(col)
            if f is None or f.type != typ or not need <= f.indexes:
                errors.append(Problem(
                    f"新しい RECORD TYPE {name} に `{col} {typ} {' '.join(sorted(need))}` が無い"
                    " (無いとアプリの差分同期が全件失敗する)",
                    f.line if f else 0,
                ))

    if base is None:
        return errors, added

    for name, base_fields in base.items():
        if name not in new:
            errors.append(Problem(
                f"RECORD TYPE {name} が消えている。Production では型を消せないので、定義は残しておく"
            ))
            continue
        for col, bf in base_fields.items():
            nf = new[name].get(col)
            if nf is None:
                errors.append(Problem(
                    f"{name}.{col} が消えている。Production では列を消せないので、"
                    "行は残したままアプリ側で読まないようにする"
                ))
            elif nf.type != bf.type:
                errors.append(Problem(
                    f"{name}.{col} の型が {bf.type} → {nf.type} に変わっている。"
                    "型は変えられないので、元の行に戻して別名の列を足す",
                    nf.line,
                ))
            elif not bf.indexes <= nf.indexes:
                lost = " ".join(sorted(bf.indexes - nf.indexes))
                errors.append(Problem(
                    f"{name}.{col} から {lost} が外れている (既存の検索・同期が壊れる)。元に戻す",
                    nf.line,
                ))

    for name, fields in new.items():
        if name not in base:
            added.append(f"RECORD TYPE `{name}` (新規)")
            continue
        for col, f in fields.items():
            bf = base[name].get(col)
            if bf is None:
                idx = " ".join(sorted(f.indexes))
                added.append(f"`{name}.{col}` {f.type} {idx}".rstrip())
            elif f.indexes != bf.indexes:
                idx = " ".join(sorted(f.indexes - bf.indexes))
                added.append(f"`{name}.{col}` にインデックス {idx} を追加")
    return errors, added


def order_warnings(new: Schema) -> List[Problem]:
    """export-schema と同じ並び (ASCII 順。大文字が先) になっていない所を返す。"""
    warnings: List[Problem] = []
    names = list(new)
    for prev, name in zip(names, names[1:]):
        if name < prev:
            first = next(iter(new[name].values()), None)
            warnings.append(Problem(
                f"RECORD TYPE {name} は {prev} より前 (ASCII 順の位置) に置く",
                first.line - 1 if first else 0,
            ))
    for name, fields in new.items():
        cols = [c for c in fields if not c.startswith("___")]
        for prev, col in zip(cols, cols[1:]):
            if col < prev:
                warnings.append(Problem(
                    f"{name}.{col} は {prev} より前 (ASCII 順の位置) に置く",
                    fields[col].line,
                ))
    return warnings


def read_base(ref: str) -> Optional[str]:
    """git の ref から ckdb を読む。その ref に無ければ None (新規ファイル扱い)。"""
    r = subprocess.run(
        ["git", "show", f"{ref}:{CKDB_REL}"], cwd=REPO, capture_output=True, text=True
    )
    if r.returncode != 0:
        if "does not exist" in r.stderr or "exists on disk, but not in" in r.stderr:
            return None
        raise SystemExit(
            f"Error: {ref} の {CKDB_REL} を読めない: {r.stderr.strip()}\n"
            "  基準のブランチを取ってきてから、もう一度実行してください:\n"
            "    git fetch origin develop\n"
            "  fork から作業している場合は、本家を upstream として足して比べます:\n"
            "    git remote add upstream https://github.com/fuga-if/idol-live-db.git\n"
            "    git fetch upstream develop\n"
            "    python3 tools/check_ckdb_schema.py --base upstream/develop"
        )
    return r.stdout


def summary_markdown(errors: List[Problem], added: List[str], warnings: List[Problem] = ()) -> str:
    lines = ["## CloudKit スキーマの変更", ""]
    if errors:
        lines += ["### ❌ このままでは CloudKit へ流せません", ""]
        lines += [f"- {e.message}" for e in errors]
        lines += ["", "CloudKit の Production は**足すことしかできません** (消す・型を変えるは戻せない)。"
                  "直し方は各行の後半に書いてあります。迷ったら PR のコメントで気軽に聞いてください。", ""]
    if warnings:
        lines += ["### ⚠️ 並び順 (直さなくても流せます)", ""]
        lines += [f"- {w.message}" for w in warnings]
        lines += ["", "ckdb は `cktool export-schema` の出力と同じ並びにしておくと、次の人の差分が読みやすくなります。", ""]
    if added and not errors:
        lines += ["### ✅ 追加される項目", ""] + [f"- {a}" for a in added] + [""]
        lines += [
            "**コントリビューターの作業はここまでで完了です。** 本番への反映はマージ後にオーナーが行います"
            " (マージすると反映待ちの Issue が自動で立ちます)。",
            "",
            "### マージ後にオーナーがやること",
            "",
            "1. `xcrun cktool export-schema` で Development の現状を取り、PR 版の ckdb との差がこの PR の追加分だけか確かめる"
            " (Development 側にしか無い変更を import で落とさないため)",
            "2. `xcrun cktool validate-schema --file tools/cloudkit_schema.ckdb`",
            "3. `xcrun cktool import-schema --file tools/cloudkit_schema.ckdb` (Development)",
            "4. CloudKit Dashboard → **Deploy Schema Changes** で Production へ昇格",
            "5. そのあとで新しい列を使うデータを `apply_data.py --push` する (昇格前だと弾かれる)",
            "",
            "詳しくは `docs/DATA_PIPELINE.md` の「スキーマを足した場合」。",
        ]
    elif not errors:
        lines += ["✅ CloudKit 側でやることはありません (追加項目なし)。"]
    return "\n".join(lines) + "\n"


def annotate(kind: str, path: str, p: Problem) -> str:
    """GitHub Actions のワークフローコマンド。PR の Files changed の該当行に出る。"""
    where = f"file={path},line={p.line}" if p.line else f"file={path}"
    msg = p.message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return f"::{kind} {where},title=cloudkit_schema.ckdb::{msg}"


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", help="比べる git ref (例: origin/develop)。省略時は構文だけ見る")
    ap.add_argument("--file", default=str(REPO / CKDB_REL), help="検査する ckdb")
    ap.add_argument("--summary", help="Markdown の要約を追記するファイル ($GITHUB_STEP_SUMMARY など)")
    args = ap.parse_args(argv)

    path = Path(args.file)
    new, dups = parse(path.read_text(encoding="utf-8"))
    base = None
    if args.base:
        base_text = read_base(args.base)
        base = parse(base_text)[0] if base_text is not None else None

    errors, added = check(new, dups, base)
    warnings = order_warnings(new)

    for a in added:
        print(f"+ {a}")
    for w in warnings:
        print(f"⚠ {w.message}" + (f" ({path.name}:{w.line})" if w.line else ""))
    for e in errors:
        print(f"✗ {e.message}" + (f" ({path.name}:{e.line})" if e.line else ""), file=sys.stderr)
    if errors:
        print("\nCloudKit の Production は足すことしかできません。上の ✗ を直してから、もう一度実行してください。",
              file=sys.stderr)
    else:
        print(f"OK: {len(new)} record types" + (f", 追加 {len(added)} 件" if added else ""))

    if os.environ.get("GITHUB_ACTIONS") == "true":
        try:
            rel = path.resolve().relative_to(REPO).as_posix()
        except ValueError:
            rel = path.as_posix()
        for e in errors:
            print(annotate("error", rel, e))
        for w in warnings:
            print(annotate("warning", rel, w))

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as fh:
            fh.write(summary_markdown(errors, added, warnings))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
