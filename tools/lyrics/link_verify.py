#!/usr/bin/env python3
"""link_verify.py — 歌詞サイトの候補 URL が「その曲」を指しているか機械判定する。

Usage:
    python3 tools/lyrics/link_verify.py            # 判定結果を表示
    python3 tools/lyrics/link_verify.py --apply    # links.tsv の confidence を更新

判定の考え方:
  **キャスト構成が違っても歌詞は同じ**なので、版や人数の一致は要求しない。
  「お願い！シンデレラ」の 9人版・11人版・3人版は歌詞が同一なので、どれを
  指していても目的 (歌詞を読む) は達せられる。

  避けたいのは**同名の全く別の曲**を掴むこと。検索結果には
  コレサワ「シンデレラ」のような無関係な曲が混ざる。

  したがって判定条件は2つだけ:
    1. 候補ページの曲名が、こちらの曲名と一致する
    2. 候補ページの歌手名に、アイマス関連の固有名詞が含まれる
       (アイドル名 395 / 声優名 301 / ユニット名 1539 / ブランド名 を DB から取る)

  1 だけ満たす = 同名の別曲の疑い → low
  両方満たす   = high
  候補なし     = not_found

  ⚠️ **照合には `lyrics_local/lyrics/<song_id>.json` の `scraped` を使う。**
  ここには歌詞サイトの曲名と歌手名が構造化されて入っている。links.tsv の
  `candidate_title` (ページの <title> 文字列) を使ってはいけない:

    - **歌手名が入っているとは限らない。** 「KAWAII ウォーズ 歌詞」のように曲名だけの
      ページがあり、固有名詞の照合が必ず落ちる。2026-09-03 時点で low だった 78 件は
      **全件リンクが正しく**、うち 50 件がこの偽陰性だった。
    - **取得に失敗することがある。** `sc_感謝のコントレイル` は
      `shainikarazu's "kanshanokontoreiru" lyrics page.` という機械生成の題が入っていた
      (`scraped` 側は「感謝のコントレイル / シャイニーカラーズ」で正しい)。

  JSON が無い曲だけ candidate_title に落とす。
"""

import argparse
import io
import json
import os
import re
import sqlite3
import sys
import unicodedata

# 候補欄に「(候補なし)」のような文言が書かれることがあるので、URL の形を要求する。
URL_RE = re.compile(r"^https?://", re.IGNORECASE)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
LINKS_TSV = os.path.join(HERE, "links.tsv")
JSON_DIR = os.path.join(REPO, "lyrics_local", "lyrics")

# 語彙として短すぎると誤爆する (「和」「初」等の1文字ユニット名が
# 無関係なページのタイトルに偶然含まれてしまう)。
MIN_VOCAB_LEN = 3


def norm(s):
    """比較用の正規化。**文字と数字だけを残す。**

    記号を個別に列挙して消す方式だと必ず取りこぼす。実際に取りこぼしていた例:
      Café Parade!  ↔ Cafe Parade!   (アクセント記号)
      ♡Cupids!      ↔ ▽Cupids!       (記号の文字化け)
      SUN♡FLOWER    ↔ SUN FLOWER     (ハート)
      花ざかりWeekend✿ ↔ 花ざかりWeekend
      JOKER↗オールマイティ ↔ JOKER/オールマイティ
    いずれも同名別曲ではなく正しい候補なのに弾かれていた。

    そこで方針を反転し、**残すものを決める**: 文字 (L*) と数字 (N*) のみ。
    アクセントは NFKD で分解して結合記号を捨てる (é → e)。
    """
    s = unicodedata.normalize("NFKC", s or "").lower()
    # アクセント等を分解して結合文字 (Mn) を落とす
    s = unicodedata.normalize("NFKD", s)
    return "".join(
        c for c in s
        if unicodedata.category(c)[0] in ("L", "N")
    )


def load_song_types(db_path):
    """song_id -> song_type。カバー曲の判定に使う。"""
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    types = {r[0]: (r[1] or "") for r in conn.execute("SELECT id, song_type FROM songs")}
    conn.close()
    return types


def load_vocab(db_path):
    """アイマス関連と判定できる固有名詞を DB から集める。"""
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    vocab = set()

    for (name,) in conn.execute("SELECT name FROM idols WHERE name <> ''"):
        vocab.add(name)
    # 声優は idols.voice_actors から idol_voice_actors テーブルへ移った
    # (代役・交代を期間つきで持つため)。歴代すべてを語彙に入れる — 収録時点の
    # 声優名が歌詞サイトに載っているので、現任だけだと古い曲を落とす。
    for (va,) in conn.execute("SELECT name FROM idol_voice_actors WHERE name <> ''"):
        # 「五十嵐裕美」単体のことも、複数を区切っていることもある
        for part in re.split(r"[、,／/]", va):
            vocab.add(part.strip())
    for (name,) in conn.execute("SELECT name FROM units WHERE name <> ''"):
        vocab.add(name)
    for (name,) in conn.execute("SELECT name FROM brands WHERE name <> ''"):
        vocab.add(name)
    # songs 側のアーティスト表記も語彙にする。units に無いグループ名 (μ's / Aqours /
    # Liella! 等のラブライブ系や、コラボ相手) はここからしか拾えない。
    # 「DB が持っているアーティスト名はすべて有効な手がかり」という一般則にする。
    for (label,) in conn.execute(
            "SELECT DISTINCT singer_label FROM songs WHERE singer_label IS NOT NULL AND singer_label <> ''"):
        for part in re.split(r"[、,／/（）()]", label):
            vocab.add(part.strip())
    for (label,) in conn.execute(
            "SELECT DISTINCT unit_name FROM songs WHERE unit_name IS NOT NULL AND unit_name <> ''"):
        for part in re.split(r"[、,／/（）()]", label):
            vocab.add(part.strip())
    conn.close()

    # ブランドの通称・レーベル名。DB に無いが歌詞サイトのクレジットに出る。
    vocab |= {
        "アイドルマスター", "THE IDOLM@STER", "アイマス",
        "765PRO ALLSTARS", "765 MILLIONSTARS", "765 MILLION ALLSTARS",
        "315 ALLSTARS", "CINDERELLA PROJECT", "シンデレラガールズ",
        "ミリオンライブ", "シャイニーカラーズ", "SideM", "学園アイドルマスター",
        "初星学園", "ハツボシ", "ASTERISM",
        # ローマ字表記。歌詞サイトのクレジットは @ を使わないことがある。
        "THE IDOLMASTER", "IDOLMASTER", "CINDERELLA GIRLS", "MILLION LIVE",
        "SHINY COLORS", "GAKUEN IDOLMASTER",
    }

    normed = {norm(v) for v in vocab if len(v.strip()) >= MIN_VOCAB_LEN}
    normed.discard("")
    # 短い固有名詞 (彩 / W / ＊(Asterisk) / vα-liv 等) は本文中に紛れると誤爆するが、
    # 歌詞サイトのページタイトルは「アーティスト名 曲名 歌詞」の形なので、
    # **先頭との照合に限れば**安全に使える。別集合として返す。
    leading = {norm(v) for v in vocab if v.strip()}
    leading.discard("")
    return normed, leading


def base_title(title):
    """版サフィックスを落とした曲名。歌詞サイト側は版名が付くことが多い。

    「READY!!(M＠STER VERSION)」に対してこちらは「READY!!」なので、
    こちらの曲名が相手に含まれるかを見る形にする。
    """
    t = unicodedata.normalize("NFKC", title or "")
    # 波ダッシュは U+301C 〜 と U+FF5E ～ の2種類がある。片方だけだと
    # 「Flip Flop 〜For SS3A rearrange〜」のような版名を剥がせない。
    # 長音符 ー (U+30FC) をダッシュ代わりに使う表記もある (こいかぜ ー花葉ー)。
    # サフィックスは入れ子になりうるので、変化しなくなるまで繰り返し剥がす。
    for _ in range(4):
        before = t
        t = re.sub(r"\s*[（(][^（()）]*[）)]\s*$", "", t)
        t = re.sub(r"\s+[-‐−–—ー].+[-‐−–—ー]\s*$", "", t)
        t = re.sub(r"\s*[~～〜].+[~～〜]\s*$", "", t)
        t = t.strip()
        if t == before:
            break
    return t


def scraped_fields(song_id):
    """投入用 JSON に残した歌詞サイトの取得結果 (曲名・歌手名)。無ければ空。"""
    path = os.path.join(JSON_DIR, "%s.json" % song_id)
    if not os.path.exists(path):
        return {}
    try:
        with io.open(path, encoding="utf-8") as f:
            return json.load(f).get("scraped") or {}
    except (ValueError, OSError):
        return {}


def judge(row, vocab, leading_vocab, song_type=""):
    """(confidence, 理由) を返す。"""
    cand = row.get("candidate_title", "")
    url = row.get("candidate_url", "")
    if not URL_RE.match(url) or not cand:
        return "not_found", "候補なし"

    # 構造化された取得結果があればそちらを見る (理由はモジュール冒頭)。
    scraped = scraped_fields(row["song_id"])
    page_title = scraped.get("page_title") or cand
    page_artist = scraped.get("page_artist") or cand

    title_n = norm(page_title)
    want_n = norm(row["title"])
    base_n = norm(base_title(row["title"]))

    # 版違いは素の曲名のページを指すので、どちら向きの包含も一致とみなす。
    title_hit = bool(title_n) and (
        (want_n and (want_n in title_n or title_n in want_n))
        or (base_n and (base_n in title_n or title_n in base_n))
    )

    artist_n = norm(page_artist)
    matched = [v for v in vocab if v and v in artist_n]
    if not matched:
        # 短い固有名詞は歌手名の先頭との照合だけ許す (誤爆を避ける)。
        matched = [v for v in leading_vocab if v and artist_n.startswith(v)]

    if title_hit and matched:
        return "high", "曲名一致 + 歌手名に関連名詞 %d件" % len(matched)

    if not title_hit and matched:
        # 歌手が一致しているので別曲を掴んでいる線は薄い。表記ゆれが疑わしい
        # (リローディング/RELOADING・俠/侠・ØωØver/OωOver・神さま/神様 等)。
        return "low", "歌手名は一致するが曲名の表記が違う: %r (要確認)" % page_title[:40]

    if not title_hit:
        return "low", "候補ページの曲名が違う: %r" % page_title[:40]

    # カバー曲は原曲アーティストのページが正解なので、アイマス語彙に当たらないのが
    # 当たり前。同名別曲の疑いとは別の状態なので区別する。
    # ただし公有曲 (ジングルベル等) は同名の別アレンジが大量にあるため、
    # 自動では lyrics_url に昇格させない (export は high のみを出す)。
    if song_type == "cover":
        return "cover", "カバー曲。原曲アーティストのページと思われる (要確認)"

    return "low", "曲名は一致するが歌手名にアイマス関連の固有名詞が無い"


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        rows = []
        for line in f:
            if not line.strip():
                continue
            v = line.rstrip("\n").split("\t")
            v += [""] * (len(header) - len(v))
            rows.append(dict(zip(header, v)))
    return header, rows


def write_tsv(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(header) + "\n")
        for r in rows:
            f.write("\t".join(re.sub(r"[\t\r\n]+", " ", r.get(c, "")) for c in header) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--links", default=LINKS_TSV)
    ap.add_argument("--apply", action="store_true", help="confidence を書き換える")
    args = ap.parse_args()

    vocab, leading_vocab = load_vocab(args.db)
    song_types = load_song_types(args.db)
    print("判定語彙: %d件 (%d文字以上) + 先頭照合用 %d件"
          % (len(vocab), MIN_VOCAB_LEN, len(leading_vocab)))

    header, rows = read_tsv(args.links)
    changed = 0
    counts = {}
    for r in rows:
        # 候補 URL が無い行は触らない。検索したが見つからなかった曲には
        # マージ時に not_found を立ててあり、それを消すと次のスライスで
        # 再検索されて予算を無駄にする。
        if not r.get("candidate_url"):
            continue
        conf, why = judge(r, vocab, leading_vocab, song_types.get(r["song_id"], ""))
        counts[conf] = counts.get(conf, 0) + 1
        if r.get("confidence") != conf:
            changed += 1
            print("  %-28s %-10s → %-10s %s"
                  % (r["title"][:26], r.get("confidence") or "-", conf, why))
        r["confidence"] = conf
        r["note"] = why

    print("\n判定結果:")
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        print("  %-10s %d" % (k, v))
    print("変更: %d件" % changed)

    if args.apply:
        write_tsv(args.links, header, rows)
        print("\nwrote %s" % args.links)
    else:
        print("\n(--apply なしなので書き込んでいない)")


if __name__ == "__main__":
    main()
