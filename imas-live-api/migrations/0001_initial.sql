-- 0001: 初期テーブル定義（クリーンDB プロビジョニング用）
-- 注意: このファイルはリバースエンジニアリングで復元したもの。
-- 既存のリモートDBには d1_migrations で適用済みとして記録されているため、
-- 新規D1インスタンスのプロビジョニング時のみ使用する。

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY NOT NULL,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    is_banned INTEGER NOT NULL DEFAULT 0,
    contribution_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    author_id TEXT NOT NULL REFERENCES users(id),
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    title TEXT NOT NULL,
    payload TEXT NOT NULL DEFAULT '{}',
    ok_count INTEGER NOT NULL DEFAULT 0,
    ng_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS votes (
    submission_id INTEGER NOT NULL REFERENCES submissions(id),
    user_id TEXT NOT NULL REFERENCES users(id),
    vote TEXT NOT NULL,
    comment TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (submission_id, user_id)
);

CREATE TABLE IF NOT EXISTS brands (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    color TEXT,
    sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS idols (
    id TEXT PRIMARY KEY NOT NULL,
    brand_id TEXT NOT NULL,
    name TEXT NOT NULL,
    name_kana TEXT,
    name_romaji TEXT,
    color TEXT,
    sort_order INTEGER NOT NULL,
    birthday TEXT,
    blood_type TEXT,
    height REAL,
    weight REAL,
    birth_place TEXT,
    age INTEGER,
    bust REAL,
    waist REAL,
    hip REAL,
    constellation TEXT,
    hobbies TEXT,
    talents TEXT,
    description TEXT,
    gender TEXT,
    handedness TEXT
);

CREATE TABLE IF NOT EXISTS idol_brands (
    idol_id TEXT NOT NULL,
    brand_id TEXT NOT NULL,
    is_primary INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (idol_id, brand_id)
);

CREATE TABLE IF NOT EXISTS cast (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    name_kana TEXT,
    name_romaji TEXT
);

CREATE TABLE IF NOT EXISTS idol_cast (
    idol_id TEXT NOT NULL,
    cast_id TEXT NOT NULL,
    is_current INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (idol_id, cast_id)
);

CREATE TABLE IF NOT EXISTS songs (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    title_kana TEXT,
    brand_id TEXT,
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
    lyrics_url TEXT,
    parent_song_id TEXT,
    singer_label TEXT,
    unit_name TEXT,
    unit_id TEXT
);

CREATE TABLE IF NOT EXISTS song_artists (
    song_id TEXT NOT NULL,
    idol_id TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'original',
    PRIMARY KEY (song_id, idol_id, role)
);

CREATE TABLE IF NOT EXISTS units (
    id TEXT PRIMARY KEY NOT NULL,
    brand_id TEXT NOT NULL,
    name TEXT NOT NULL,
    is_permanent INTEGER NOT NULL DEFAULT 1,
    name_alt TEXT
);

CREATE TABLE IF NOT EXISTS unit_members (
    unit_id TEXT NOT NULL,
    idol_id TEXT NOT NULL,
    PRIMARY KEY (unit_id, idol_id)
);

CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY NOT NULL,
    brand_id TEXT,
    name TEXT NOT NULL,
    event_type TEXT NOT NULL,
    is_streaming INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS shows (
    id TEXT PRIMARY KEY NOT NULL,
    event_id TEXT NOT NULL,
    name TEXT NOT NULL,
    date TEXT NOT NULL,
    venue TEXT,
    venue_city TEXT,
    start_time TEXT,
    sort_order INTEGER NOT NULL,
    performer_type TEXT DEFAULT 'cast'
);

CREATE TABLE IF NOT EXISTS show_cast (
    show_id TEXT NOT NULL,
    cast_id TEXT NOT NULL,
    PRIMARY KEY (show_id, cast_id)
);

CREATE TABLE IF NOT EXISTS setlist_items (
    id TEXT PRIMARY KEY NOT NULL,
    show_id TEXT NOT NULL,
    song_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    section TEXT,
    notes TEXT,
    unit_name TEXT,
    UNIQUE(show_id, position)
);

CREATE TABLE IF NOT EXISTS setlist_performers (
    setlist_item_id TEXT NOT NULL,
    cast_id TEXT NOT NULL,
    PRIMARY KEY (setlist_item_id, cast_id)
);

CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT
);

CREATE TABLE IF NOT EXISTS api_rate_limits (
    ip TEXT NOT NULL,
    minute_bucket INTEGER NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (ip, minute_bucket)
);
