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
    1. 候補ページのタイトルに、こちらの曲名が含まれる
    2. 候補ページのタイトルに、アイマス関連の固有名詞が含まれる
       (アイドル名 395 / 声優名 301 / ユニット名 1539 / ブランド名 を DB から取る)

  1 だけ満たす = 同名の別曲の疑い → low
  両方満たす   = high
  候補なし     = not_found
"""

import argparse
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


def load_vocab(db_path):
    """アイマス関連と判定できる固有名詞を DB から集める。"""
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    vocab = set()

    for (name,) in conn.execute("SELECT name FROM idols WHERE name <> ''"):
        vocab.add(name)
    for (va,) in conn.execute(
            "SELECT voice_actors FROM idols WHERE voice_actors IS NOT NULL AND voice_actors <> ''"):
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

    # ブランドの通称・レーベル名。DB に無いが歌ネットのクレジットに出る。
    vocab |= {
        "アイドルマスター", "THE IDOLM@STER", "アイマス",
        "765PRO ALLSTARS", "765 MILLIONSTARS", "765 MILLION ALLSTARS",
        "315 ALLSTARS", "CINDERELLA PROJECT", "シンデレラガールズ",
        "ミリオンライブ", "シャイニーカラーズ", "SideM", "学園アイドルマスター",
        "初星学園", "ハツボシ", "ASTERISM",
        # ローマ字表記。歌ネットのクレジットは @ を使わないことがある。
        "THE IDOLMASTER", "IDOLMASTER", "CINDERELLA GIRLS", "MILLION LIVE",
        "SHINY COLORS", "GAKUEN IDOLMASTER",
    }

    normed = {norm(v) for v in vocab if len(v.strip()) >= MIN_VOCAB_LEN}
    normed.discard("")
    # 短い固有名詞 (彩 / W / ＊(Asterisk) / vα-liv 等) は本文中に紛れると誤爆するが、
    # 歌ネットのページタイトルは「アーティスト名 曲名 歌詞 - 歌ネット」の形なので、
    # **先頭との照合に限れば**安全に使える。別集合として返す。
    leading = {norm(v) for v in vocab if v.strip()}
    leading.discard("")
    return normed, leading


def base_title(title):
    """版サフィックスを落とした曲名。歌ネット側は版名が付くことが多い。

    「READY!!(M＠STER VERSION)」に対してこちらは「READY!!」なので、
    こちらの曲名が相手に含まれるかを見る形にする。
    """
    t = unicodedata.normalize("NFKC", title or "")
    t = re.sub(r"\s*[（(][^（()）]*[）)]\s*$", "", t)
    t = re.sub(r"\s+[-‐−–—].+[-‐−–—]\s*$", "", t)
    t = re.sub(r"\s*[~～].+[~～]\s*$", "", t)
    return t.strip()


def judge(row, vocab, leading_vocab):
    """(confidence, 理由) を返す。"""
    cand = row.get("candidate_title", "")
    url = row.get("candidate_url", "")
    if not URL_RE.match(url) or not cand:
        return "not_found", "候補なし"

    cand_n = norm(cand)
    title_n = norm(row["title"])
    base_n = norm(base_title(row["title"]))

    title_hit = (title_n and title_n in cand_n) or (base_n and base_n in cand_n)
    if not title_hit:
        return "low", "候補タイトルに曲名が含まれない"

    matched = [v for v in vocab if v and v in cand_n]
    if matched:
        return "high", "曲名一致 + 関連名詞 %d件" % len(matched)

    # 短い固有名詞はタイトル先頭 (= アーティスト表記) との照合だけ許す。
    lead = [v for v in leading_vocab if v and cand_n.startswith(v)]
    if lead:
        return "high", "曲名一致 + 先頭の関連名詞 (%s)" % max(lead, key=len)[:20]

    return "low", "アイマス関連の固有名詞がタイトルに無い (同名別曲の疑い)"


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
        conf, why = judge(r, vocab, leading_vocab)
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
