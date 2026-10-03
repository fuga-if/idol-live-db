#!/usr/bin/env python3
"""Google Play に AAB を上げてトラックにリリースを置く (Android Publisher API v3)。

鍵: サービスアカウントの JSON。既定は ~/keys/play-publisher.json (リポジトリには置かない)。
手順の説明は docs/ANDROID_RELEASE.md。

  # トラックの今の中身を見る
  python3 tools/play_release.py status

  # AAB を上げて本番に下書きで置く (公開はしない。Play Console で確認して押す)
  python3 tools/play_release.py upload app-release.aab --notes release_notes.txt

  # 既定は --track production --status draft。段階公開まで API で進めるときだけ明示する
  python3 tools/play_release.py upload app-release.aab --notes release_notes.txt \\
      --status inProgress --fraction 0.2

リリースノートのファイルは Play Console と同じ形 (<ja-JP>...</ja-JP><en-US>...</en-US>)。
"""
import argparse
import os
import re
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PACKAGE = "site.fugaapp.imaslivedb"
DEFAULT_KEY = os.path.expanduser("~/keys/play-publisher.json")
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
NOTES_LIMIT = 500


def service(key_path):
    creds = service_account.Credentials.from_service_account_file(key_path, scopes=SCOPES)
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def parse_notes(path):
    text = open(path, encoding="utf-8").read()
    notes = []
    for lang, body in re.findall(r"<([A-Za-z]{2,3}-[A-Za-z]{2,4})>\n?(.*?)\n?</\1>", text, re.S):
        if len(body) > NOTES_LIMIT:
            sys.exit(f"{lang} のリリースノートが {len(body)} 字 (上限 {NOTES_LIMIT})")
        notes.append({"language": lang, "text": body})
    if not notes:
        sys.exit(f"{path} に <ja-JP>...</ja-JP> 形式のノートがない")
    return notes


def cmd_status(api, _args):
    edits = api.edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    try:
        for track in edits.tracks().list(packageName=PACKAGE, editId=edit_id).execute().get("tracks", []):
            for r in track.get("releases", []):
                print(f"{track['track']:12} {r.get('status'):10} {r.get('name', ''):10} "
                      f"versionCodes={r.get('versionCodes')} fraction={r.get('userFraction', '-')}")
    finally:
        edits.delete(packageName=PACKAGE, editId=edit_id).execute()


def cmd_upload(api, args):
    if args.status == "inProgress" and not args.fraction:
        sys.exit("--status inProgress には --fraction が要る")
    notes = parse_notes(args.notes) if args.notes else []
    edits = api.edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    try:
        media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
        bundle = edits.bundles().upload(packageName=PACKAGE, editId=edit_id, media_body=media).execute()
        version_code = bundle["versionCode"]
        print(f"uploaded versionCode={version_code}")

        release = {"versionCodes": [str(version_code)], "status": args.status}
        if args.name:
            release["name"] = args.name
        if notes:
            release["releaseNotes"] = notes
        if args.fraction:
            release["userFraction"] = args.fraction
        edits.tracks().update(
            packageName=PACKAGE, editId=edit_id, track=args.track,
            body={"track": args.track, "releases": [release]},
        ).execute()
        edits.commit(packageName=PACKAGE, editId=edit_id).execute()
        print(f"committed: track={args.track} status={args.status}")
    except Exception:
        edits.delete(packageName=PACKAGE, editId=edit_id).execute()
        raise


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--key", default=os.environ.get("PLAY_PUBLISHER_KEY", DEFAULT_KEY))
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    up = sub.add_parser("upload")
    up.add_argument("aab")
    up.add_argument("--notes")
    up.add_argument("--name", help="リリース名 (省略時は Play が versionName から付ける)")
    up.add_argument("--track", default="production")
    up.add_argument("--status", default="draft", choices=["draft", "inProgress", "completed"])
    up.add_argument("--fraction", type=float, help="段階公開の割合 (0〜1)")
    args = p.parse_args()
    api = service(args.key)
    {"status": cmd_status, "upload": cmd_upload}[args.cmd](api, args)


if __name__ == "__main__":
    main()
