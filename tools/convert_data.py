#!/usr/bin/env python3
"""
既存Webアプリ(imas-live-app)のJSONデータ → master.sqlite 変換スクリプト

入力: /tmp/imas_idols.json, /tmp/imas_songs.json, /tmp/imas_setlist.json
出力: ImasLiveDB/Resources/master.sqlite
"""

from __future__ import annotations

import json
import sqlite3
import re
import unicodedata
from pathlib import Path

# 出力先
OUTPUT_DB = Path(__file__).parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite"

# ============================================================
# ローマ字変換テーブル (furigana → romaji)
# ============================================================
ROMAJI_MAP = {
    "あまみ はるか": "amami_haruka",
    "きさらぎ ちはや": "kisaragi_chihaya",
    "ほしい みき": "hoshii_miki",
    "はぎわら ゆきほ": "hagiwara_yukiho",
    "たかつき やよい": "takatsuki_yayoi",
    "きくち まこと": "kikuchi_makoto",
    "みなせ いおり": "minase_iori",
    "しじょう たかね": "shijou_takane",
    "あきづき りつこ": "akizuki_ritsuko",
    "みうら あずさ": "miura_azusa",
    "ふたみ あみ": "futami_ami",
    "ふたみ まみ": "futami_mami",
    "がなは ひびき": "ganaha_hibiki",
    "かすが みらい": "kasuga_mirai",
    "もがみ しずか": "mogami_shizuka",
    "いぶき つばさ": "ibuki_tsubasa",
    "たなか ことは": "tanaka_kotoha",
    "とくがわ まつり": "tokugawa_matsuri",
    "さたけ みなこ": "satake_minako",
    "よこやま なお": "yokoyama_nao",
    "えみりー すちゅあーと": "emily_stewart",
    "きたかみ れいか": "kitakami_reika",
    "まいはま あゆむ": "maihama_ayumu",
    "しのみや かれん": "shinomiya_karen",
    "じゅうごう あけた": "juugou_aketa",  # placeholder
    "ところ めぐみ": "tokoro_megumi",
    "なかたに いく": "nakatani_iku",
    "あまみ はるか": "amami_haruka",
    "たかやま さやこ": "takayama_sayako",  # placeholder
    "すおう ままこ": "suou_momoko",
    "まきの せな": "makino_sena",  # placeholder
    "のの": "nono",  # placeholder
}

# 765ASメンバーリスト（名前で判定）
AS_MEMBERS = {
    "天海 春香", "如月 千早", "星井 美希", "萩原 雪歩",
    "高槻 やよい", "菊地 真", "水瀬 伊織", "四条 貴音",
    "秋月 律子", "三浦 あずさ", "双海 亜美", "双海 真美", "我那覇 響"
}


def slugify(text: str) -> str:
    """テキストからURL-safe slugを生成"""
    text = text.lower().strip()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s_]+', '_', text)
    return text[:80]


def normalize_title(title: str) -> str:
    """曲名を正規化（全角半角・Unicode揺れ・記号揺れを吸収して重複検出に使用）"""
    normalized = unicodedata.normalize('NFKC', title)
    # 全角スペース→半角
    normalized = normalized.replace('\u3000', ' ')
    # 波線の揺れ統一: 〜 ～ ~ → ~
    normalized = normalized.replace('〜', '~').replace('～', '~')
    # 引用符の揺れ統一: " " → "
    normalized = normalized.replace('\u201c', '"').replace('\u201d', '"')
    # 記号の揺れ統一
    normalized = normalized.replace('＊', '*').replace('＆', '&')
    normalized = normalized.replace('♥︎', '♥').replace('♡', '♥')
    normalized = normalized.replace('☆', '★')
    # (新曲) (ショートver.) 等のサフィックスを除去
    normalized = re.sub(r'\s*[(（](?:新曲|ショートver\.).*?[)）]\s*$', '', normalized)
    # 前後空白除去、連続スペースを単一に
    normalized = re.sub(r'\s+', ' ', normalized).strip()
    return normalized.lower()


def furigana_to_romaji(furigana: str) -> str | None:
    """ふりがな → ローマ字（テーブル引き、なければNone）"""
    if not furigana:
        return None
    key = furigana.lower().strip()
    return ROMAJI_MAP.get(key)


def make_idol_id(name: str, brand_id: str, furigana: str = "") -> str:
    """アイドルID生成: brand_familyname_givenname"""
    # 姓名を分割
    parts = name.replace("　", " ").split()
    if len(parts) >= 2:
        slug = slugify(f"{parts[0]}_{parts[1]}")
    else:
        slug = slugify(name)
    return f"{brand_id}_{slug}"


def make_cast_id(cv_name: str) -> str:
    """キャストID生成"""
    return f"cast_{slugify(cv_name.replace(' ', ''))}"


def determine_brand(idol_data: dict) -> str:
    """アイドルのブランド判定"""
    name = idol_data.get("name", "")
    affiliation = idol_data.get("affiliation", "")
    if affiliation == "961プロダクション":
        return "765as"
    if name in ("宮本フレデリカ", "一ノ瀬志希"):
        return "cg"
    if name in AS_MEMBERS:
        return "765as"
    return "ml"


def parse_live_name(live_name: str) -> tuple[str, str]:
    """
    ライブ名 → (event名, show名) に分解

    例:
    "... 10thLIVE TOUR Act-1 H@PPY 4 YOU! [DAY1]" → ("... 10thLIVE TOUR", "Act-1 H@PPY 4 YOU! DAY1")
    "... 5thLIVE BRAND NEW PERFORM@NCE!!! 1日目" → ("... 5thLIVE BRAND NEW PERFORM@NCE!!!", "1日目")
    """
    # パターン1: [DAY1] / [DAY2] 形式
    m = re.search(r'\s*\[(DAY\d+)\]\s*$', live_name)
    if m:
        show_name = m.group(1)
        base = live_name[:m.start()].strip()
        # Act-N サブイベント名があれば show_name に含める
        act_m = re.search(r'\s+(Act-\d+\s+.+)$', base)
        if act_m:
            show_name = f"{act_m.group(1)} {show_name}"
            base = base[:act_m.start()].strip()
        return (base, show_name)

    # パターン2: DAY1 / DAY2 形式 (括弧なし)
    m = re.search(r'\s+(DAY\d+)\s+(.+)$', live_name)
    if m:
        base = live_name[:m.start()].strip()
        show_name = f"{m.group(1)} {m.group(2)}"
        return (base, show_name)

    # パターン3: N日目 形式
    m = re.search(r'\s+(\d+日目)$', live_name)
    if m:
        return (live_name[:m.start()].strip(), m.group(1))

    # パターン4: 都市名公演 形式
    m = re.search(r'\s+([\u4e00-\u9fff]+公演(?:\d+日目)?)$', live_name)
    if m:
        return (live_name[:m.start()].strip(), m.group(1))

    # パターン5: SSA公演N日目
    m = re.search(r'\s+(SSA公演\d+日目)$', live_name)
    if m:
        return (live_name[:m.start()].strip(), m.group(1))

    # 分解できない場合はそのまま
    return (live_name, live_name)


def make_event_id(event_name: str) -> str:
    """イベントID生成"""
    # 特徴的な部分を抽出してスラグ化
    s = event_name.lower()
    s = re.sub(r'the idolm@ster\s*', '', s)
    s = re.sub(r'million live!?\s*', 'ml_', s)
    s = re.sub(r'765 millionstars?\s*', '765ms_', s)
    s = re.sub(r'[^\w\s]', '', s)
    s = re.sub(r'\s+', '_', s.strip())
    return s[:80] if s else slugify(event_name)


def make_show_id(event_id: str, show_name: str) -> str:
    """公演ID生成"""
    return f"{event_id}_{slugify(show_name)}"[:100]


def determine_song_type(song_data: dict) -> str:
    """曲タイプ判定"""
    if song_data.get("isAll"):
        return "all"
    if song_data.get("isSolo"):
        return "solo"
    if song_data.get("isUnit"):
        return "unit"
    return "unit"


def make_song_id(title: str, brand_id: str = "ml") -> str:
    """楽曲ID生成"""
    return f"{brand_id}_{slugify(title)}"[:80]


def create_schema(conn: sqlite3.Connection):
    """スキーマ作成"""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS brands (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            short_name TEXT NOT NULL,
            color TEXT,
            sort_order INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS idols (
            id TEXT PRIMARY KEY,
            brand_id TEXT NOT NULL REFERENCES brands(id),
            name TEXT NOT NULL,
            name_kana TEXT,
            name_romaji TEXT,
            color TEXT,
            sort_order INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cast (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            name_kana TEXT,
            name_romaji TEXT
        );

        CREATE TABLE IF NOT EXISTS idol_cast (
            idol_id TEXT NOT NULL REFERENCES idols(id),
            cast_id TEXT NOT NULL REFERENCES cast(id),
            is_current INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (idol_id, cast_id)
        );

        CREATE TABLE IF NOT EXISTS songs (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            title_kana TEXT,
            brand_id TEXT REFERENCES brands(id),
            song_type TEXT NOT NULL,
            release_date TEXT,
            duration_sec INTEGER,
            composer TEXT,
            lyricist TEXT,
            arranger TEXT,
            cd_series TEXT,
            cd_title TEXT,
            artwork_url TEXT,
            preview_url TEXT,
            apple_music_id TEXT,
            apple_music_album_id TEXT,
            isrc TEXT,
            lyrics_url TEXT
        );

        CREATE TABLE IF NOT EXISTS song_artists (
            song_id TEXT NOT NULL REFERENCES songs(id),
            idol_id TEXT NOT NULL REFERENCES idols(id),
            role TEXT NOT NULL DEFAULT 'original',
            PRIMARY KEY (song_id, idol_id, role)
        );

        CREATE TABLE IF NOT EXISTS units (
            id TEXT PRIMARY KEY,
            brand_id TEXT NOT NULL REFERENCES brands(id),
            name TEXT NOT NULL,
            is_permanent INTEGER NOT NULL DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS unit_members (
            unit_id TEXT NOT NULL REFERENCES units(id),
            idol_id TEXT NOT NULL REFERENCES idols(id),
            PRIMARY KEY (unit_id, idol_id)
        );

        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            brand_id TEXT REFERENCES brands(id),
            name TEXT NOT NULL,
            event_type TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS shows (
            id TEXT PRIMARY KEY,
            event_id TEXT NOT NULL REFERENCES events(id),
            name TEXT NOT NULL,
            date TEXT NOT NULL,
            venue TEXT,
            venue_city TEXT,
            start_time TEXT,
            sort_order INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS show_cast (
            show_id TEXT NOT NULL REFERENCES shows(id),
            cast_id TEXT NOT NULL REFERENCES cast(id),
            PRIMARY KEY (show_id, cast_id)
        );

        CREATE TABLE IF NOT EXISTS setlist_items (
            id TEXT PRIMARY KEY,
            show_id TEXT NOT NULL REFERENCES shows(id),
            song_id TEXT NOT NULL REFERENCES songs(id),
            position INTEGER NOT NULL,
            section TEXT,
            notes TEXT,
            UNIQUE(show_id, position)
        );

        CREATE TABLE IF NOT EXISTS setlist_performers (
            setlist_item_id TEXT NOT NULL REFERENCES setlist_items(id),
            cast_id TEXT NOT NULL REFERENCES cast(id),
            PRIMARY KEY (setlist_item_id, cast_id)
        );

        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        -- Indexes
        CREATE INDEX IF NOT EXISTS idx_songs_brand ON songs(brand_id);
        CREATE INDEX IF NOT EXISTS idx_songs_title_kana ON songs(title_kana);
        CREATE INDEX IF NOT EXISTS idx_songs_type ON songs(song_type);
        CREATE INDEX IF NOT EXISTS idx_idols_brand ON idols(brand_id);
        CREATE INDEX IF NOT EXISTS idx_idols_name_kana ON idols(name_kana);
        CREATE INDEX IF NOT EXISTS idx_shows_event ON shows(event_id);
        CREATE INDEX IF NOT EXISTS idx_shows_date ON shows(date);
        CREATE INDEX IF NOT EXISTS idx_setlist_items_show ON setlist_items(show_id);
        CREATE INDEX IF NOT EXISTS idx_setlist_items_song ON setlist_items(song_id);
        CREATE INDEX IF NOT EXISTS idx_setlist_performers_item ON setlist_performers(setlist_item_id);
        CREATE INDEX IF NOT EXISTS idx_setlist_performers_cast ON setlist_performers(cast_id);
        CREATE INDEX IF NOT EXISTS idx_song_artists_song ON song_artists(song_id);
        CREATE INDEX IF NOT EXISTS idx_song_artists_idol ON song_artists(idol_id);
        CREATE INDEX IF NOT EXISTS idx_idol_cast_idol ON idol_cast(idol_id);
        CREATE INDEX IF NOT EXISTS idx_idol_cast_cast ON idol_cast(cast_id);
        CREATE INDEX IF NOT EXISTS idx_show_cast_show ON show_cast(show_id);
        CREATE INDEX IF NOT EXISTS idx_show_cast_cast ON show_cast(cast_id);
        CREATE INDEX IF NOT EXISTS idx_unit_members_unit ON unit_members(unit_id);
        CREATE INDEX IF NOT EXISTS idx_unit_members_idol ON unit_members(idol_id);
    """)


def insert_brands(conn: sqlite3.Connection):
    """ブランド初期データ"""
    brands = [
        ("765as", "THE IDOLM@STER", "アイマス", "#fe0000", 1),
        ("cg", "THE IDOLM@STER CINDERELLA GIRLS", "デレマス", "#2681c8", 2),
        ("ml", "THE IDOLM@STER MILLION LIVE!", "ミリオン", "#ffc30b", 3),
        ("sidem", "THE IDOLM@STER SideM", "SideM", "#0fbe94", 4),
        ("sc", "THE IDOLM@STER SHINY COLORS", "シャニマス", "#6bb6b9", 5),
        ("gakuen", "学園アイドルマスター", "学マス", "#f39800", 6),
        ("valiv", "PROJECT IM@S vα-liv", "ヴイアラ", "#7f51dc", 7),
    ]
    conn.executemany(
        "INSERT OR REPLACE INTO brands VALUES (?, ?, ?, ?, ?)", brands
    )


def insert_idols(conn: sqlite3.Connection, idols_data: list) -> dict:
    """アイドル + キャスト + idol_cast を挿入。name→idol_id マッピングを返す"""
    name_to_idol_id = {}
    cast_ids = set()

    for i, idol in enumerate(idols_data):
        name = idol["name"]
        brand_id = determine_brand(idol)
        idol_id = make_idol_id(name, brand_id)

        # 重複ID回避
        base_id = idol_id
        suffix = 2
        while idol_id in name_to_idol_id.values():
            idol_id = f"{base_id}_{suffix}"
            suffix += 1

        furigana = idol.get("furigana", "")
        romaji = furigana_to_romaji(furigana)
        color = idol.get("color")

        conn.execute(
            "INSERT OR REPLACE INTO idols VALUES (?, ?, ?, ?, ?, ?, ?)",
            (idol_id, brand_id, name, furigana, romaji, color, i + 1)
        )
        name_to_idol_id[name] = idol_id

        # キャスト
        cv = idol.get("cv", "").strip()
        if cv:
            cast_id = make_cast_id(cv)
            if cast_id not in cast_ids:
                conn.execute(
                    "INSERT OR REPLACE INTO cast VALUES (?, ?, ?, ?)",
                    (cast_id, cv, None, None)
                )
                cast_ids.add(cast_id)

            conn.execute(
                "INSERT OR REPLACE INTO idol_cast VALUES (?, ?, ?)",
                (idol_id, cast_id, 1)
            )

    return name_to_idol_id


def insert_songs(conn: sqlite3.Connection, songs_data: list, name_to_idol_id: dict) -> dict:
    """楽曲 + song_artists を挿入。title→song_id マッピングを返す"""
    title_to_song_id = {}
    used_ids = set()
    normalized_to_song_id: dict[str, str] = {}  # 正規化タイトル → song_id（重複検出用）
    duplicate_count = 0

    for song in songs_data:
        title = song["title"]
        normalized = normalize_title(title)
        song_type = determine_song_type(song)
        song_id = make_song_id(title)

        # 正規化済みタイトルによる重複チェック（全角半角・スペース揺れ）
        if normalized in normalized_to_song_id:
            existing_id = normalized_to_song_id[normalized]
            print(f"  ⚠ 重複曲検出: '{title}' → '{existing_id}' にマッピング")
            title_to_song_id[title] = existing_id
            duplicate_count += 1
            continue

        # 重複ID回避
        base_id = song_id
        suffix = 2
        while song_id in used_ids:
            song_id = f"{base_id}_{suffix}"
            suffix += 1
        used_ids.add(song_id)
        normalized_to_song_id[normalized] = song_id

        conn.execute(
            "INSERT OR REPLACE INTO songs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (song_id, title, None, "ml", song_type,
             song.get("releaseDate"), None,
             song.get("composer"), song.get("lyricist"), song.get("arranger"),
             song.get("cdSeries"), song.get("cdTitle"),
             None, None, None, None, None, None)
        )
        title_to_song_id[title] = song_id

        # song_artists
        for artist_name in song.get("artists", []):
            # 名前のスペースの揺れを吸収
            norm_name = artist_name.replace("　", " ").strip()
            idol_id = name_to_idol_id.get(norm_name)
            if idol_id:
                conn.execute(
                    "INSERT OR REPLACE INTO song_artists VALUES (?, ?, ?)",
                    (song_id, idol_id, "original")
                )

    if duplicate_count:
        print(f"    → 重複除去: {duplicate_count}件")
    return title_to_song_id


def determine_event_brand(live_name: str, brand: str) -> str | None:
    """イベントのブランドID判定"""
    if "MILLION LIVE" in live_name or "MILLIONSTARS" in live_name:
        return "ml"
    if "M@STERS OF IDOL WORLD" in live_name:
        return None  # 合同
    if "ORCHESTRA" in live_name:
        return None  # 合同
    if "MASTER EXPO" in live_name:
        return None
    brand_map = {"million": "ml", "cinderella": "cg", "765as": "765as",
                 "shinycolors": "sc", "sidem": "sidem"}
    return brand_map.get(brand)


def determine_event_type(live_name: str) -> str:
    """イベントタイプ判定"""
    if "FESTIVAL" in live_name.upper() or "FESTIV@L" in live_name:
        return "festival"
    if "RADIO" in live_name:
        return "fanmeeting"
    if "EXPO" in live_name:
        return "fanmeeting"
    return "live"


def insert_setlist(conn: sqlite3.Connection, setlist_data: list,
                   title_to_song_id: dict, name_to_idol_id: dict):
    """セトリデータ → events + shows + setlist_items + setlist_performers"""

    # ライブ名でグルーピング
    from collections import defaultdict
    shows_by_live = defaultdict(list)
    for entry in setlist_data:
        shows_by_live[entry["liveName"]].append(entry)

    event_ids = {}  # event_name → event_id
    show_ids = {}   # live_name → show_id
    cv_to_cast_id = {}  # キャッシュ

    # キャスト名→cast_id マッピングを構築
    rows = conn.execute("SELECT id, name FROM cast").fetchall()
    for row in rows:
        cv_to_cast_id[row[1]] = row[0]

    # アイドル名→キャスト名マッピング
    idol_to_cv = {}
    rows = conn.execute("""
        SELECT i.name, c.name, c.id FROM idols i
        JOIN idol_cast ic ON i.id = ic.idol_id
        JOIN cast c ON ic.cast_id = c.id
    """).fetchall()
    for row in rows:
        idol_to_cv[row[0]] = (row[1], row[2])

    for live_name, entries in shows_by_live.items():
        event_name, show_name = parse_live_name(live_name)

        # Event
        if event_name not in event_ids:
            event_id = make_event_id(event_name)
            # 重複回避
            base = event_id
            suffix = 2
            while event_id in event_ids.values():
                event_id = f"{base}_{suffix}"
                suffix += 1
            event_ids[event_name] = event_id

            brand = entries[0].get("brand", "")
            event_brand_id = determine_event_brand(live_name, brand)
            event_type = determine_event_type(event_name)

            conn.execute(
                "INSERT OR REPLACE INTO events VALUES (?, ?, ?, ?)",
                (event_id, event_brand_id, event_name, event_type)
            )

        event_id = event_ids[event_name]

        # Show
        show_id = make_show_id(event_id, show_name)
        if live_name in show_ids:
            show_id = show_ids[live_name]
        else:
            # 重複回避
            base_show_id = show_id
            suffix = 2
            existing = set(show_ids.values())
            while show_id in existing:
                show_id = f"{base_show_id}_{suffix}"
                suffix += 1
            show_ids[live_name] = show_id

            first_entry = entries[0]
            date = first_entry.get("date", "")
            venue = first_entry.get("venue", "")

            # sort_order: 同イベント内の公演順
            same_event_shows = [k for k, v in show_ids.items()
                                if parse_live_name(k)[0] == event_name]
            sort_order = len(same_event_shows)

            conn.execute(
                "INSERT OR REPLACE INTO shows VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (show_id, event_id, show_name, date, venue, None, None, sort_order)
            )

        # Setlist items + performers
        for entry in entries:
            track_no = entry.get("trackNo", 0)
            song_name = entry.get("songName", "")
            notes = None

            # ショートバージョン → 原曲にマッピング + notesに記録
            import re as _re
            short_match = _re.search(r'\s*\((?:short|Short)\s*ver\.?\)\s*$', song_name)
            if short_match:
                original_name = song_name[:short_match.start()]
                notes = "short ver."
                # 原曲を探す
                song_id = title_to_song_id.get(original_name)
                if not song_id:
                    # 原曲が見つからない場合は通常のsong_nameで検索
                    song_id = title_to_song_id.get(song_name)
            else:
                song_id = title_to_song_id.get(song_name)

            # 楽曲がDBにない場合は作成（ショートバージョンは原曲名で作成）
            if not song_id:
                effective_name = song_name[:short_match.start()] if short_match else song_name
                song_id = make_song_id(effective_name)
                base = song_id
                suffix = 2
                while conn.execute("SELECT 1 FROM songs WHERE id=?", (song_id,)).fetchone():
                    song_id = f"{base}_{suffix}"
                    suffix += 1

                brand = entry.get("brand", "million")
                brand_map = {"million": "ml", "cinderella": "cg", "765as": "765as",
                             "shinycolors": "sc", "sidem": "sidem"}
                song_brand = brand_map.get(brand, "ml")

                conn.execute(
                    "INSERT OR REPLACE INTO songs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (song_id, effective_name, None, song_brand, "unit", None, None, None, None, None, None, None, None, None, None, None, None, None)
                )
                title_to_song_id[effective_name] = song_id

            setlist_item_id = f"{show_id}_{track_no:03d}"

            try:
                conn.execute(
                    "INSERT OR REPLACE INTO setlist_items VALUES (?, ?, ?, ?, ?, ?)",
                    (setlist_item_id, show_id, song_id, track_no, None, notes)
                )
            except sqlite3.IntegrityError:
                continue

            # Performers: idolNames を使ってキャストを紐づけ
            idol_names = entry.get("idolNames", [])
            for idol_name in idol_names:
                normalized = idol_name.replace("　", " ").strip()
                if normalized in idol_to_cv:
                    cv_name, cast_id = idol_to_cv[normalized]
                    try:
                        conn.execute(
                            "INSERT OR REPLACE INTO setlist_performers VALUES (?, ?)",
                            (setlist_item_id, cast_id)
                        )
                    except sqlite3.IntegrityError:
                        pass

            # show_cast にも追加
            for idol_name in idol_names:
                normalized = idol_name.replace("　", " ").strip()
                if normalized in idol_to_cv:
                    _, cast_id = idol_to_cv[normalized]
                    try:
                        conn.execute(
                            "INSERT OR REPLACE INTO show_cast VALUES (?, ?)",
                            (show_id, cast_id)
                        )
                    except sqlite3.IntegrityError:
                        pass


def insert_meta(conn: sqlite3.Connection):
    """メタデータ挿入"""
    conn.executemany(
        "INSERT OR REPLACE INTO meta VALUES (?, ?)",
        [
            ("schema_version", "1"),
            ("data_version", "1"),
            ("baseline_version", "1"),
            ("last_sync_at", ""),
        ]
    )


def main():
    print("=== アイドルライブDB データ変換 ===")

    # データ読み込み
    with open("/tmp/imas_idols.json") as f:
        idols_data = json.load(f)
    with open("/tmp/imas_songs.json") as f:
        songs_data = json.load(f)
    with open("/tmp/imas_setlist.json") as f:
        setlist_data = json.load(f)

    print(f"  アイドル: {len(idols_data)}件")
    print(f"  楽曲:     {len(songs_data)}件")
    print(f"  セトリ:   {len(setlist_data)}件")

    # 出力先ディレクトリ
    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    conn = sqlite3.connect(str(OUTPUT_DB))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=OFF")  # 挿入時はOFF

    try:
        create_schema(conn)

        print("  ブランド挿入中...")
        insert_brands(conn)

        print("  アイドル・キャスト挿入中...")
        name_to_idol_id = insert_idols(conn, idols_data)
        print(f"    → {len(name_to_idol_id)}件")

        print("  楽曲挿入中...")
        title_to_song_id = insert_songs(conn, songs_data, name_to_idol_id)
        print(f"    → {len(title_to_song_id)}件")

        print("  セトリ挿入中...")
        insert_setlist(conn, setlist_data, title_to_song_id, name_to_idol_id)

        insert_meta(conn)

        conn.commit()

        # 統計出力
        for table in ["brands", "idols", "cast", "idol_cast", "songs",
                       "song_artists", "events", "shows", "setlist_items",
                       "setlist_performers", "show_cast"]:
            count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            print(f"    {table}: {count}件")

        conn.execute("PRAGMA foreign_keys=ON")
        # 外部キー整合性チェック
        errors = conn.execute("PRAGMA foreign_key_check").fetchall()
        if errors:
            print(f"  ⚠ 外部キーエラー: {len(errors)}件")
            for e in errors[:5]:
                print(f"    {e}")
        else:
            print("  ✓ 外部キー整合性OK")

    finally:
        conn.close()

    size_mb = OUTPUT_DB.stat().st_size / 1024 / 1024
    print(f"\n  出力: {OUTPUT_DB} ({size_mb:.2f} MB)")
    print("=== 完了 ===")


if __name__ == "__main__":
    main()
