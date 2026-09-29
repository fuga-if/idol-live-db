#!/usr/bin/env python3
"""`xcrun simctl list devices available --json` から iPhone シミュレータを 1 台選ぶ。

CI runner のイメージによって利用可能なシミュレータ名 (iPhone 16 / 17 / …) が変わるため、
destination に名前を決め打ちすると「device not found」で落ちる。実在するものから選ぶ。

出力は GitHub Actions の $GITHUB_OUTPUT 形式 (`udid=...`)。
使い方: pick_simulator.py <simctl の JSON ファイル>
"""
import json
import sys


def main() -> int:
    with open(sys.argv[1], encoding="utf-8") as f:
        runtimes = json.load(f)["devices"]

    candidates = [
        (runtime, device)
        for runtime, devices in runtimes.items()
        for device in devices
        if device.get("isAvailable", True) and device["name"].startswith("iPhone")
    ]
    if not candidates:
        print("利用可能な iPhone シミュレータが見つかりません", file=sys.stderr)
        return 1

    # 同じ機種が複数 runtime にある場合は新しい runtime を優先する
    # (runtime 識別子は ...iOS-26-4 のような形なので文字列順で十分)。
    runtime, device = sorted(candidates, key=lambda c: c[0])[-1]
    print(f"udid={device['udid']}")
    print(f"選んだシミュレータ: {device['name']} ({runtime})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
