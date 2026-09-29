"""SQL の表と CloudKit のレコード型の対応。標準ライブラリだけで書く。

`apply_data.py --check` は貢献者が手元で回す口で、鍵も外部のライブラリも要らない。
この知識を送信の部品 (requests / ecdsa を使う) と同じファイルに置くと、検証だけでも
それらが要ることになるので分けてある。seed_cloudkit.py からも同じ名前で読める。
"""

TABLE_ORDER = [
    "brands",
    # 読みの表は何も参照しないので先頭付近でよい。
    "creators",
    "idols",
    "events",
    "units",
    # ユニットの版は songs より先。 songs.unit_version_id が版を指すので、
    # 先に版を投入しないと参照先が無い状態の Song が一時的に生まれる。
    "unit_versions",
    "songs",
    # 会場は shows より先。 shows.venue_id が会場を指すので、
    # 先に会場側を投入しないと参照先が無い状態の Show が一時的に生まれる。
    "venues",
    "venue_names",
    "venue_halls",
    "shows",
    "idol_brands",
    "unit_members",
    "song_artists",
    "setlist_items",
    "setlist_performers",
    "show_cast",
    # 衣装の目録は先、着用記録は後。着用記録が costumes / shows / setlist_items /
    # idols の全部を指すので、最後尾に置く。
    "costumes",
    "costume_wears",
    # チケット価格は shows にだけぶら下がる。公演の後ならどこでもよい。
    "show_tickets",
    "meta",
]

RECORD_TYPE_MAP = {
    "brands": "Brand",
    "songs": "Song",
    "events": "Event",
    "shows": "Show",
    "setlist_items": "SetlistItem",
    "setlist_performers": "SetlistPerformer",
    "cast": "CastMember",
    "idols": "Idol",
    "idol_cast": "IdolCast",
    "idol_brands": "IdolBrand",
    "units": "ImasUnit",
    "unit_members": "UnitMember",
    "song_artists": "SongArtist",
    "show_cast": "ShowCast",
    "venues": "Venue",
    "venue_names": "VenueName",
    "unit_versions": "UnitVersion",
    "creators": "Creator",
    "venue_halls": "VenueHall",
    "costumes": "Costume",
    "costume_wears": "CostumeWear",
    "show_tickets": "ShowTicket",
    "meta": "MetaData",
}

# --ids / --ids-file で絞るときに見る列。表に無いテーブルは絞れない (全件 push)。
# --replace はこの表にあるテーブルにしか使えない (理由は assert_replace_safe)。
ID_FILTER_COLUMN = {
    "songs": "id",
    "song_artists": "song_id",
    "show_cast": "show_id",
    "setlist_items": "id",
    "idols": "id",
    "setlist_performers": "setlist_item_id",
    "events": "id",
    "shows": "event_id",
    "units": "id",
    "costumes": "id",
    "costume_wears": "costume_id",
}

# 渡す id が「何の id か」。**列名からは決まらない** ので ID_FILTER_COLUMN とは別に持つ:
# songs.id と song_artists.song_id はどちらも曲 id だが、
# setlist_items.id と idols.id は同じ "id" でも別物。
# 同じ空間の表だけをまとめて 1 回の push で絞れる (呼び出し側 apply_data.py がここを読む)。
SCOPED_ID_SPACE = {
    "songs": "song",
    "song_artists": "song",
    "setlist_items": "setlist_item",
    "setlist_performers": "setlist_item",
    "events": "event",
    "shows": "event",
    "show_cast": "show",
    "idols": "idol",
    "units": "unit",
    "costumes": "costume",
    "costume_wears": "costume",
}


def scope_id(conn, table, row_id):
    """その表の 1 行の id → `--ids` に渡す値。

    `--ids` が見るのは行の id ではなく ID_FILTER_COLUMN[table] の列 (shows なら
    event_id)。行 id をそのまま渡すと `WHERE event_id IN (<show id>)` が 0 行に当たり、
    **push が成功したように見えて 1 行も送られない**。読み替えはこの契約を持つ
    ここに置く (呼び出し側で書くと、呼び出し元が増えるたび同じ穴に落ちる)。

    呼び出し側は ID_FILTER_COLUMN にある表だけを渡すこと。
    """
    col = ID_FILTER_COLUMN[table]
    row = conn.execute(f"SELECT {col} FROM {table} WHERE id = ?", (row_id,)).fetchone()
    if row is None:
        raise KeyError(f"{table}.id = {row_id!r} が無い (絞り込む値を決められない)")
    return row[0]
