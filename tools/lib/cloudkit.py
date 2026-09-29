"""CloudKit Web Services との通信 (Server-to-Server 鍵の署名・送信・再試行・一括送信・読み取り)。

tools/ から CloudKit に触る経路はここを通す。署名の作り方・429 の待ち方・バッチの
大きさ・エラーの数え方を 1 か所に置き、ツールごとに片方だけ変わるのを防ぐ。

requests と ecdsa は、実際に署名・送信するときにだけ読み込む (鍵の要らない検証や
テストは、それら無しで動く)。テストは http_post と sleep を偽物に差し替える。
"""
from __future__ import annotations

import base64
import hashlib
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

BASE_URL = "https://api.apple-cloudkit.com"
CONTAINER = "iCloud.com.fugaif.ImasLiveDB"
BATCH_SIZE = 200
MAX_RETRIES = 5
INITIAL_BACKOFF = 1.0  # seconds


def records_path(env: str, operation: str) -> str:
    """公開 DB のレコード API のパス。operation は modify / query / lookup。"""
    return f"/database/1/{CONTAINER}/{env}/public/records/{operation}"


class Signer:
    """S2S 鍵で要求に署名する。"""

    def __init__(self, key_id: str, pem: str):
        from ecdsa import SigningKey  # 署名するときだけ要る

        self.key_id = key_id
        self._key = SigningKey.from_pem(pem)

    def headers(self, body: bytes, subpath: str) -> dict:
        from ecdsa.util import sigencode_der

        date_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        body_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
        message = f"{date_str}:{body_hash}:{subpath}"
        signature = base64.b64encode(
            self._key.sign(message.encode(), hashfunc=hashlib.sha256, sigencode=sigencode_der)
        ).decode()
        return {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": self.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date_str,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        }


def load_signer(key_id: str, key_file) -> Signer:
    return Signer(key_id, Path(key_file).read_text())


def _requests_post(url: str, body: bytes, headers: dict):
    import requests  # 送るときだけ要る

    return requests.post(url, data=body, headers=headers)


# 送信の口 (url, body, headers) → 応答 (status_code / json() / text / raise_for_status())。
http_post = _requests_post
sleep = time.sleep


def post_json(url: str, payload: dict, signer: Signer | None = None) -> dict:
    """POST して応答の JSON を返す。429 は待って署名し直し、最大 MAX_RETRIES 回まで送る。

    CloudKit API は recordName に非 ASCII 文字 (全角仮名・異体字 等) を含む場合、
    `\\uXXXX` 形式の escape よりも UTF-8 raw を期待するため ensure_ascii=False。
    署名の日時は送るたびに作り直す (待った後に古い日時のまま送らない)。
    """
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    subpath = url.replace(BASE_URL, "")
    for attempt in range(MAX_RETRIES):
        headers = signer.headers(body, subpath) if signer else {"Content-Type": "application/json"}
        resp = http_post(url, body, headers)
        if resp.status_code == 200:
            return resp.json()
        if resp.status_code == 429:
            wait = INITIAL_BACKOFF * (2 ** attempt)
            print(f"  [rate limit] sleeping {wait:.1f}s before retry {attempt + 1}/{MAX_RETRIES}")
            sleep(wait)
        else:
            print(f"  [HTTP {resp.status_code}] {resp.text[:500]}", file=sys.stderr)
            resp.raise_for_status()
    raise RuntimeError("Max retries exceeded for CloudKit request")


def record_errors(result: dict) -> list:
    """modify / lookup の応答のうち、レコード単位で失敗したもの。"""
    return [r for r in result.get("records", []) if "serverErrorCode" in r]


def upload_operations(ops: list, url: str, dry_run: bool, label: str, post,
                      batch_size: int = BATCH_SIZE, pause: float = 1.0) -> tuple[int, int]:
    """ops を batch_size ずつ送り、(成功, レコード単位のエラー) の件数を返す。

    post(url, payload) は送信の関数 (署名するセッションごとに呼び出し側が渡す)。
    バッチが例外で落ちたら 3 秒待って 1 回だけやり直し、それでも落ちたら例外を上げる
    (CloudKit がまれに "could not find handler for endpoint" の 404 を返す。連続した
    要求を絞っているらしい)。
    """
    total = len(ops)
    processed = 0
    error_count = 0
    for batch_start in range(0, total, batch_size):
        batch = ops[batch_start : batch_start + batch_size]
        if dry_run:
            print(f"  [dry-run] would upload {len(batch)} records (batch starting at {batch_start})")
            processed += len(batch)
            continue

        if batch_start > 0:
            sleep(pause)
        payload = {"operations": batch}
        try:
            result = post(url, payload)
        except Exception as e:
            print(f"  [warn] batch upload failed, retrying once: {e}", file=sys.stderr)
            sleep(3.0)
            try:
                result = post(url, payload)
            except Exception as e2:
                print(f"  [error] batch upload failed after retry: {e2}", file=sys.stderr)
                raise

        errors = record_errors(result)
        if errors:
            error_count += len(errors)
            print(f"  [warn] {len(errors)} record errors in batch:", file=sys.stderr)
            for err in errors[:3]:
                print(f"    {err}", file=sys.stderr)

        processed += len(batch)
        print(f"  uploaded {processed}/{total} {label} records")

    return (processed - error_count, error_count)


def query_all(url: str, record_type: str, post, desired_keys=None) -> list:
    """指定 RecordType の全レコードを continuationMarker でページング取得する (読み取りだけ)。

    フィルタ無しクエリは recordName 順を要求するが recordName は queryable でない。
    modifiedAt は iOS 差分同期 (modifiedAt > lastSync) が使うため必ず queryable なので、
    modifiedAt > 0 でフィルタ＆ソートして全件を列挙する (全レコードに modifiedAt が入る)。
    desired_keys を渡すと、そのフィールドだけを返させる (件数を数えるだけのとき用)。
    """
    out, cursor = [], None
    while True:
        payload = {
            "query": {
                "recordType": record_type,
                "filterBy": [{
                    "fieldName": "modifiedAt",
                    "comparator": "GREATER_THAN",
                    "fieldValue": {"value": 0, "type": "TIMESTAMP"},
                }],
                "sortBy": [{"fieldName": "modifiedAt", "ascending": True}],
            },
            "resultsLimit": 200,
        }
        if desired_keys is not None:
            payload["desiredKeys"] = list(desired_keys)
        if cursor:
            payload["continuationMarker"] = cursor
        result = post(url, payload)
        out.extend(result.get("records", []))
        # CloudKit は次ページがある時だけ continuationMarker を返す (無ければ最終ページ)
        cursor = result.get("continuationMarker")
        if not cursor:
            break
    return out


def is_soft_deleted(record: dict) -> bool:
    """deletedAt が入っているレコード (export は削除として扱い、取り込まない)。"""
    return bool(record.get("fields", {}).get("deletedAt", {}).get("value"))


def count_live(url: str, record_type: str, post) -> int:
    """soft delete されていないレコードの件数 (export が取り込むのと同じ数え方)。"""
    records = query_all(url, record_type, post, desired_keys=["deletedAt"])
    return sum(1 for r in records if not is_soft_deleted(r))


def lookup(url: str, record_names: list, post, desired_keys=None,
           batch_size: int = BATCH_SIZE) -> dict:
    """recordName → 応答のレコードを返す (読み取りだけ)。

    無いレコードは serverErrorCode (NOT_FOUND) の付いた応答になる。応答は頼んだ順に
    並ぶので、recordName が付いていない応答は同じ位置で頼んだ名前に対応づける。
    """
    out = {}
    for i in range(0, len(record_names), batch_size):
        names = record_names[i : i + batch_size]
        payload = {"records": [{"recordName": n} for n in names]}
        if desired_keys is not None:
            payload["desiredKeys"] = list(desired_keys)
        for pos, record in enumerate(post(url, payload).get("records", [])):
            name = record.get("recordName") or (names[pos] if pos < len(names) else None)
            out[name] = record
    return out
