"""曲名・人名を突き合わせるときの畳み方と、歌詞検索の正規化。標準ライブラリだけで書く。

ツールごとに規則が少しずつ違う (空白の範囲・大小文字・全角/半角)。揃えると当たる件数が
変わるので揃えてはいない。名前を付けてここに並べ、どのツールがどれを使うかを見えるように
して、同じ規則の写しを作らない。新しく要るときは、まずここにあるものを使う。
"""

import re
import unicodedata


def squash_spaces(text: str) -> str:
    """空白 (全角空白・改行・タブも含む) を潰す。「所 恵美」と「所恵美」を同じにする。"""
    return re.sub(r"\s+", "", text)


def squash_spaces_lower(text: str) -> str:
    """空白を潰し、大小文字も畳む。`765PRO ALLSTARS` と `765ProAllstars` を同じにする。"""
    return re.sub(r"\s+", "", text).lower()


def drop_spaces_lower(text: str) -> str:
    """半角と全角の空白だけを落とし、大小文字を畳む (改行やタブは残す)。None は空文字。"""
    return (text or "").replace(" ", "").replace("　", "").lower()


def nfkc_drop_spaces(text: str) -> str:
    """NFKC で全角/半角を均し、半角と全角の空白を落とす (大小文字は区別する)。"""
    return unicodedata.normalize("NFKC", text).replace(" ", "").replace("　", "")


def normalize_for_search(text: str) -> str:
    """歌詞検索の正規化 (song_lyrics.body_norm と検索語に掛けるもの)。

    正は Worker の normalizeForSearch (imas-live-api/src/routes/lyrics.ts)。PUT のたびに
    body_norm を書き、検索語もこれで正規化する。ここはその Python 版で、規則を変えるときは
    両方を同時に変える (片方だけだと、検索で当たるのに窓が作れない曲や、索引から漏れる
    曲が出る)。向き (ひらがな → カタカナ) はアプリの畳み込み (imas-text-fold) と逆だが、
    変えないと決めてある。

    - ひらがな (U+3041〜U+3096) → カタカナ
    - 全角英数記号 (U+FF01〜U+FF5E) → 半角 (英字は小文字)
    - それ以外は小文字にするだけ

    **1 文字 → 1 文字** の変換だけにする。検索は body_norm 上で一致位置を求め、その位置で
    body から窓を切るので、長さの変わる変換を入れるとスニペットが壊れる。
    大小文字の対応表は実行環境の Unicode の版に従う (Worker 側も同じ)。
    """
    out = []
    for ch in text:
        code = ord(ch)
        if 0x3041 <= code <= 0x3096:          # ひらがな → カタカナ
            out.append(chr(code + 0x60))
        elif 0xFF01 <= code <= 0xFF5E:        # 全角英数記号 → 半角
            out.append(chr(code - 0xFEE0).lower())
        else:
            out.append(ch.lower())
    return "".join(out)
