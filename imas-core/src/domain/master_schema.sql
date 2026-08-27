CREATE TABLE anniversaries (
    id TEXT PRIMARY KEY NOT NULL,
    brand_id TEXT NOT NULL REFERENCES brands(id),
    label TEXT NOT NULL,
    date TEXT NOT NULL,
    kind TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE brands (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, short_name TEXT NOT NULL, color TEXT, sort_order INTEGER NOT NULL);
CREATE TABLE events (id TEXT PRIMARY KEY NOT NULL, brand_id TEXT, name TEXT NOT NULL, event_type TEXT NOT NULL, is_streaming INTEGER NOT NULL DEFAULT 0, is_solo INTEGER NOT NULL DEFAULT 1, kind TEXT NOT NULL DEFAULT 'live', ticket_deadline TEXT, ticket_lottery_date TEXT, ticket_url TEXT, joint_brand_ids TEXT, ticket_open_date TEXT);
CREATE TABLE idol_brands (idol_id TEXT NOT NULL, brand_id TEXT NOT NULL, is_primary INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (idol_id, brand_id));
CREATE TABLE idol_voice_actors (
  id TEXT PRIMARY KEY NOT NULL,
  idol_id TEXT NOT NULL,
  name TEXT NOT NULL,
  valid_from TEXT,
  valid_to TEXT
);
CREATE TABLE idols (id TEXT PRIMARY KEY NOT NULL, brand_id TEXT NOT NULL, name TEXT NOT NULL, name_kana TEXT, name_romaji TEXT, color TEXT, sort_order INTEGER NOT NULL, birthday TEXT, blood_type TEXT, height REAL, weight REAL, birth_place TEXT, age INTEGER, bust REAL, waist REAL, hip REAL, constellation TEXT, hobbies TEXT, talents TEXT, description TEXT, gender TEXT, handedness TEXT, family_name TEXT, given_name TEXT, nickname TEXT, debut_date TEXT, attribute TEXT, is_external INTEGER NOT NULL DEFAULT 0, aliases TEXT);
CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT);
CREATE TABLE setlist_items (id TEXT PRIMARY KEY NOT NULL, show_id TEXT NOT NULL, song_id TEXT NOT NULL, position INTEGER NOT NULL, section TEXT, notes TEXT, unit_name TEXT, UNIQUE(show_id, position));
CREATE TABLE "setlist_performers" (
            setlist_item_id TEXT NOT NULL,
            idol_id TEXT NOT NULL,
            PRIMARY KEY (setlist_item_id, idol_id),
            FOREIGN KEY (setlist_item_id) REFERENCES setlist_items(id) ON DELETE CASCADE,
            FOREIGN KEY (idol_id) REFERENCES idols(id) ON DELETE CASCADE
        );
CREATE TABLE "show_cast" (
            show_id TEXT NOT NULL,
            idol_id TEXT NOT NULL, cast_role TEXT NOT NULL DEFAULT 'member',
            PRIMARY KEY (show_id, idol_id),
            FOREIGN KEY (show_id) REFERENCES shows(id) ON DELETE CASCADE,
            FOREIGN KEY (idol_id) REFERENCES idols(id) ON DELETE CASCADE
        );
CREATE TABLE shows (id TEXT PRIMARY KEY NOT NULL, event_id TEXT NOT NULL, name TEXT NOT NULL, date TEXT NOT NULL, venue TEXT, venue_city TEXT, start_time TEXT, sort_order INTEGER NOT NULL, performer_type TEXT DEFAULT 'cast', venue_id TEXT, hall TEXT, stream_platform TEXT);
CREATE TABLE song_artists (song_id TEXT NOT NULL, idol_id TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'original', PRIMARY KEY (song_id, idol_id, role));
CREATE TABLE song_units (
  song_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  PRIMARY KEY (song_id, unit_id)
);
CREATE TABLE songs (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, title_kana TEXT, brand_id TEXT, song_type TEXT NOT NULL, release_date TEXT, duration_sec INTEGER, composer TEXT, lyricist TEXT, arranger TEXT, cd_series TEXT, cd_title TEXT, artwork_url TEXT, preview_url TEXT, apple_music_id TEXT, apple_music_album_id TEXT, isrc TEXT, lyrics_url TEXT, parent_song_id TEXT, singer_label TEXT, unit_name TEXT, unit_id TEXT, series_group TEXT, jasrac_code TEXT, unit_version_id TEXT);
CREATE TABLE staff (
    id TEXT PRIMARY KEY NOT NULL,
    brand_id TEXT NOT NULL REFERENCES brands(id),
    name TEXT NOT NULL,
    name_kana TEXT,
    name_romaji TEXT,
    role TEXT,
    birthday TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE unit_members (unit_id TEXT NOT NULL, idol_id TEXT NOT NULL, PRIMARY KEY (unit_id, idol_id));
CREATE TABLE unit_versions (
            id TEXT PRIMARY KEY NOT NULL, unit_id TEXT NOT NULL, code TEXT,
            name TEXT NOT NULL, catchphrase TEXT, logo_url TEXT,
            valid_from TEXT, valid_to TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
CREATE TABLE units (id TEXT PRIMARY KEY NOT NULL, brand_id TEXT NOT NULL, name TEXT NOT NULL, is_permanent INTEGER NOT NULL DEFAULT 1, name_alt TEXT);
CREATE TABLE venue_halls (
            id TEXT PRIMARY KEY NOT NULL, venue_id TEXT NOT NULL, name TEXT NOT NULL,
            capacity INTEGER
        );
CREATE TABLE venue_names (
            id TEXT PRIMARY KEY NOT NULL, venue_id TEXT NOT NULL, name TEXT NOT NULL,
            valid_from TEXT, valid_to TEXT
        );
CREATE TABLE venues (
            id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, name_kana TEXT,
            prefecture TEXT, city TEXT, aliases TEXT, capacity INTEGER,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
CREATE INDEX idx_anniversaries_brand ON anniversaries(brand_id);
CREATE INDEX idx_anniversaries_date ON anniversaries(date);
CREATE INDEX idx_events_is_solo ON events(is_solo);
CREATE INDEX idx_idol_voice_actors_idol ON idol_voice_actors(idol_id);
CREATE INDEX idx_idols_attribute ON idols(attribute);
CREATE INDEX idx_idols_is_external ON idols(is_external);
CREATE INDEX idx_setlist_items_show ON setlist_items(show_id);
CREATE INDEX idx_setlist_items_song ON setlist_items(song_id);
CREATE INDEX idx_setlist_performers_idol ON setlist_performers(idol_id);
CREATE INDEX idx_show_cast_idol ON show_cast(idol_id);
CREATE INDEX idx_shows_date ON shows(date);
CREATE INDEX idx_shows_event ON shows(event_id);
CREATE INDEX idx_shows_venue_id ON shows(venue_id);
CREATE INDEX idx_song_units_song ON song_units(song_id);
CREATE INDEX idx_song_units_unit ON song_units(unit_id);
CREATE INDEX idx_songs_brand ON songs(brand_id);
CREATE INDEX idx_songs_composer ON songs(composer);
CREATE INDEX idx_songs_series_group ON songs(series_group);
CREATE INDEX idx_songs_unit_version ON songs(unit_version_id);
CREATE INDEX idx_staff_birthday ON staff(birthday);
CREATE INDEX idx_staff_brand ON staff(brand_id);
CREATE INDEX idx_unit_versions_unit ON unit_versions(unit_id);
CREATE INDEX idx_venue_halls_venue ON venue_halls(venue_id);
CREATE INDEX idx_venue_names_venue ON venue_names(venue_id);
