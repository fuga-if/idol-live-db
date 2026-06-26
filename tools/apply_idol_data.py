#!/usr/bin/env python3
"""
apply_idol_data.py - Populate idols, idol_cast, idol_brands, units, unit_members tables
from im@sparql SPARQL cached data.

一度きりの取り込み用スクリプト。入力 (/tmp/imas_*.json) は im@sparql から手動で
取得・生成した JSON を想定する (このスクリプトは取得を行わない)。
"""

import json
import re
import sqlite3
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Optional

DB_PATH = str(Path(__file__).resolve().parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite")
SPARQL_PATH = "/tmp/imas_sparql_full.json"
UNITS_PATH = "/tmp/imas_units_all.json"

# Brand mapping from SPARQL values to DB brand_ids
BRAND_MAP = {
    "765AS": "765as",
    "MillionLive": "ml",
    "CinderellaGirls": "cg",
    "SideM": "sidem",
    "ShinyColors": "sc",
    "Gakuen": "gakuen",
    "DearlyStars": "876",
    "va-liv": "876",  # va-liv maps to 876 brand
    "Other": "765as",
}

# Sort order for brand-level idol ordering
BRAND_SORT_BASE = {
    "765as": 0,
    "ml": 1000,
    "cg": 2000,
    "sidem": 3000,
    "sc": 4000,
    "gakuen": 5000,
    "876": 6000,
    "961": 7000,
}


def slugify(text: str) -> str:
    """Convert Japanese/mixed text to a slug suitable for IDs."""
    text = text.strip()
    # Normalize unicode
    text = unicodedata.normalize("NFC", text)
    # Convert full-width alphanumeric to half-width
    text = text.translate(str.maketrans(
        "　！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～",
        " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    ))
    # Replace spaces (full-width and half-width) with underscore
    text = re.sub(r"[\s\u3000]+", "_", text)
    # Keep: ASCII alphanumeric, hiragana, katakana, kanji, underscore, dash, middle dot
    text = re.sub(r"[^\w\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff・\-]", "", text)
    # Replace middle dot with underscore
    text = re.sub(r"[・]", "_", text)
    # Collapse multiple underscores
    text = re.sub(r"_+", "_", text)
    text = text.strip("_")
    return text.lower()


def make_idol_id(brand_id: str, name: str) -> str:
    """Create idol ID in format brand_id_slugified_name."""
    slug = slugify(name)
    return f"{brand_id}_{slug}"


def make_cast_id(cv_name: str) -> str:
    """Create cast ID in format cast_slugified_cv_name."""
    # Use the same pattern as existing cast entries: cast_ + name as-is (no slug)
    # but we need it to match existing entries
    slug = slugify(cv_name)
    return f"cast_{slug}"


def val(entry: dict, key: str) -> Optional[str]:
    """Safely get value from SPARQL binding entry."""
    v = entry.get(key, {}).get("value")
    return v if v else None


def safe_float(v) -> Optional[float]:
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def safe_int(v) -> Optional[int]:
    if v is None:
        return None
    try:
        return int(float(v))
    except (ValueError, TypeError):
        return None


def merge_idols(bindings: list) -> list:
    """
    Merge duplicate entries (caused by multiple hobbies/talents in SPARQL).
    Group by (name, brand) and collect all hobbies/talents.
    """
    # Key: (name, brand, cv) -> merged entry
    merged: dict[tuple, dict] = {}

    for b in bindings:
        name = val(b, "name")
        brand = val(b, "brand")
        cv = val(b, "cv")
        key = (name, brand, cv)

        if key not in merged:
            merged[key] = {
                "name": name,
                "nameKana": val(b, "nameKana"),
                "color": val(b, "color"),
                "cv": cv,
                "birthday": val(b, "birthday"),
                "brand": brand,
                "bloodType": val(b, "bloodType"),
                "height": val(b, "height"),
                "weight": val(b, "weight"),
                "birthPlace": val(b, "birthPlace"),
                "age": val(b, "age"),
                "bust": val(b, "bust"),
                "waist": val(b, "waist"),
                "hip": val(b, "hip"),
                "constellation": val(b, "constellation"),
                "hobbies": set(),
                "talents": set(),
                "description": val(b, "description"),
                "gender": val(b, "gender"),
                "handedness": val(b, "handedness"),
            }

        entry = merged[key]
        hobby = val(b, "hobby")
        talent = val(b, "talent")
        if hobby:
            entry["hobbies"].add(hobby)
        if talent:
            entry["talents"].add(talent)

    # Convert sets to sorted comma-separated strings
    result = []
    for entry in merged.values():
        entry["hobbies"] = "、".join(sorted(entry["hobbies"])) if entry["hobbies"] else None
        entry["talents"] = "、".join(sorted(entry["talents"])) if entry["talents"] else None
        result.append(entry)

    return result


def determine_primary_brand(name: str, sparql_brand: str) -> tuple:
    """
    Returns (primary_brand_id, [all_brand_ids]) for an idol.
    Handles special cases for cross-brand idols.
    """
    primary = BRAND_MAP.get(sparql_brand, "765as")
    all_brands = [primary]

    # 秋月涼: belongs to both 876 and sidem
    if name == "秋月涼":
        all_brands = list({"876", "sidem"})
        # Primary brand is sidem (where she primarily appears in SideM)
        primary = "sidem"

    # ジュピター members: 761/961 and sidem
    jupiter_members = {"天ヶ瀬冬馬", "伊集院北斗", "御手洗翔太"}
    if name in jupiter_members:
        all_brands = list({"961", "sidem"})
        primary = "sidem"

    return primary, all_brands


def load_data():
    with open(SPARQL_PATH) as f:
        sparql_data = json.load(f)
    with open(UNITS_PATH) as f:
        units_data = json.load(f)
    return sparql_data["results"]["bindings"], units_data["results"]["bindings"]


def get_unit_brand(members_in_db: list, conn) -> Optional[str]:
    """Determine brand for a unit based on member brands."""
    if not members_in_db:
        return None
    cur = conn.cursor()
    brands = []
    for idol_id in members_in_db:
        cur.execute("SELECT brand_id FROM idols WHERE id = ?", (idol_id,))
        row = cur.fetchone()
        if row:
            brands.append(row[0])

    if not brands:
        return None

    from collections import Counter
    brand_counts = Counter(brands)
    # Return the most common brand
    return brand_counts.most_common(1)[0][0]


def main():
    raw_bindings, unit_bindings = load_data()

    # Merge duplicate idol entries (multiple hobbies/talents)
    idols = merge_idols(raw_bindings)

    # Deduplicate by (name, brand) - keep first occurrence
    # Some idols appear in multiple brands (秋月涼, Jupiter members) - these are separate entries
    seen_name_brand = set()
    unique_idols = []
    for idol in idols:
        key = (idol["name"], idol["brand"])
        if key not in seen_name_brand:
            seen_name_brand.add(key)
            unique_idols.append(idol)

    print(f"Unique idols after merge: {len(unique_idols)}")

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    # Load existing cast entries into memory for quick lookup
    cur.execute("SELECT id, name FROM cast")
    existing_cast = {}
    for cast_id, cast_name in cur.fetchall():
        existing_cast[cast_name] = cast_id

    # Track statistics
    brand_counts = defaultdict(int)
    idol_cast_count = 0
    new_cast_count = 0

    # Build a name -> idol_id map for unit matching
    idol_name_to_id: dict[str, str] = {}

    # Sort idols for consistent sort_order
    # Group by brand and assign sort_order within brand
    brand_idol_groups: dict[str, list] = defaultdict(list)
    for idol in unique_idols:
        sparql_brand = idol.get("brand") or "Other"
        primary_brand, _ = determine_primary_brand(idol["name"], sparql_brand)
        brand_idol_groups[primary_brand].append(idol)

    # INSERT idols
    for brand_id, idol_list in brand_idol_groups.items():
        for idx, idol in enumerate(idol_list):
            name = idol["name"]
            sparql_brand = idol.get("brand") or "Other"
            primary_brand, all_brands = determine_primary_brand(name, sparql_brand)

            # Determine the effective brand_id for this record
            # For cross-brand idols, use the primary brand
            effective_brand = primary_brand

            idol_id = make_idol_id(effective_brand, name)
            sort_base = BRAND_SORT_BASE.get(effective_brand, 9000)
            sort_order = sort_base + idx

            color = idol.get("color")
            if color and not color.startswith("#"):
                color = f"#{color}"

            cur.execute(
                """INSERT OR IGNORE INTO idols
                   (id, brand_id, name, name_kana, color, sort_order, birthday, blood_type,
                    height, weight, birth_place, age, bust, waist, hip, constellation,
                    hobbies, talents, description, gender, handedness)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    idol_id,
                    effective_brand,
                    name,
                    idol.get("nameKana"),
                    color,
                    sort_order,
                    idol.get("birthday"),
                    idol.get("bloodType"),
                    safe_float(idol.get("height")),
                    safe_float(idol.get("weight")),
                    idol.get("birthPlace"),
                    safe_int(idol.get("age")),
                    safe_float(idol.get("bust")),
                    safe_float(idol.get("waist")),
                    safe_float(idol.get("hip")),
                    idol.get("constellation"),
                    idol.get("hobbies"),
                    idol.get("talents"),
                    idol.get("description"),
                    idol.get("gender"),
                    idol.get("handedness"),
                ),
            )

            if cur.rowcount > 0:
                brand_counts[effective_brand] += 1

            # Register name -> id mapping (only first entry wins for unit matching)
            if name not in idol_name_to_id:
                idol_name_to_id[name] = idol_id

            # INSERT idol_brands
            for brand in all_brands:
                is_primary = 1 if brand == primary_brand else 0
                cur.execute(
                    "INSERT OR IGNORE INTO idol_brands (idol_id, brand_id, is_primary) VALUES (?, ?, ?)",
                    (idol_id, brand, is_primary),
                )

            # Handle CV -> idol_cast link
            cv_name = idol.get("cv")
            if cv_name:
                cast_id_slug = make_cast_id(cv_name)

                # Check if cast already exists (exact name match or generated ID)
                if cv_name in existing_cast:
                    cast_id = existing_cast[cv_name]
                elif cast_id_slug in existing_cast.values():
                    cast_id = cast_id_slug
                else:
                    # Insert new cast entry
                    cur.execute(
                        "INSERT OR IGNORE INTO cast (id, name) VALUES (?, ?)",
                        (cast_id_slug, cv_name),
                    )
                    if cur.rowcount > 0:
                        new_cast_count += 1
                        existing_cast[cv_name] = cast_id_slug
                    cast_id = cast_id_slug

                # Link idol to cast
                cur.execute(
                    "INSERT OR IGNORE INTO idol_cast (idol_id, cast_id, is_current) VALUES (?, ?, 1)",
                    (idol_id, cast_id),
                )
                if cur.rowcount > 0:
                    idol_cast_count += 1

    conn.commit()

    # --- Units ---
    print(f"\nProcessing {len(unit_bindings)} units...")

    unit_count = 0
    unit_member_count = 0
    skipped_units = 0

    for unit_entry in unit_bindings:
        unit_name = unit_entry["unitName"]["value"]
        members_raw = unit_entry.get("members", {}).get("value", "")

        if not members_raw:
            skipped_units += 1
            continue

        # Parse members: pipe-separated, mix of Japanese and English names
        member_parts = [m.strip() for m in members_raw.split("|") if m.strip()]

        # Match Japanese names to our idol table
        matched_idol_ids = []
        for part in member_parts:
            if part in idol_name_to_id:
                idol_id = idol_name_to_id[part]
                if idol_id not in matched_idol_ids:
                    matched_idol_ids.append(idol_id)

        # Only create unit if at least 2 members are in our idols table
        if len(matched_idol_ids) < 2:
            skipped_units += 1
            continue

        # Determine unit brand from members
        unit_brand_id = get_unit_brand(matched_idol_ids, conn)

        unit_id = slugify(unit_name)
        # Ensure unit_id is not empty - use hash of original name for stability
        if not unit_id:
            import hashlib
            unit_id = "unit_" + hashlib.md5(unit_name.encode("utf-8")).hexdigest()[:8]

        cur.execute(
            "INSERT OR IGNORE INTO units (id, brand_id, name, is_permanent) VALUES (?, ?, ?, 1)",
            (unit_id, unit_brand_id, unit_name),
        )
        if cur.rowcount > 0:
            unit_count += 1

        # Insert unit members
        for idol_id in matched_idol_ids:
            cur.execute(
                "INSERT OR IGNORE INTO unit_members (unit_id, idol_id) VALUES (?, ?)",
                (unit_id, idol_id),
            )
            if cur.rowcount > 0:
                unit_member_count += 1

    conn.commit()
    conn.close()

    # --- Print statistics ---
    print("\n=== Statistics ===")
    print("\nIdols inserted per brand:")
    total_idols = 0
    for brand_id in sorted(brand_counts.keys()):
        count = brand_counts[brand_id]
        print(f"  {brand_id:10s}: {count:4d}")
        total_idols += count
    print(f"  {'TOTAL':10s}: {total_idols:4d}")

    print(f"\nNew cast entries added: {new_cast_count}")
    print(f"idol_cast links created: {idol_cast_count}")
    print(f"\nUnits created: {unit_count}")
    print(f"Units skipped (<2 matched members): {skipped_units}")
    print(f"unit_members links created: {unit_member_count}")


if __name__ == "__main__":
    main()
