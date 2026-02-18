"""
extract.py — Read geotagged photo metadata from macOS Photos.sqlite.

Parses GPS coordinates, timestamps, and reverse geocoding data (binary plists)
from Apple's Photos database. Returns a clean pandas DataFrame.
"""

import os
import sqlite3
import plistlib
from datetime import datetime, timezone
from typing import Optional, Tuple

import pandas as pd

# Apple Cocoa epoch: Jan 1, 2001 → offset from Unix epoch (Jan 1, 1970)
COCOA_EPOCH_OFFSET = 978307200

# Default Photos library database path
DEFAULT_DB_PATH = os.path.expanduser(
    "~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"
)

# How many years back to look
YEARS_BACK = 6


def _cocoa_to_datetime(cocoa_timestamp):
    """Convert Apple Cocoa timestamp to Python datetime."""
    if cocoa_timestamp is None:
        return None
    unix_ts = cocoa_timestamp + COCOA_EPOCH_OFFSET
    return datetime.fromtimestamp(unix_ts, tz=timezone.utc)


def _resolve_uid(objects: list, val) -> Optional[str]:
    """
    Resolve an NSKeyedArchiver reference to its string value.

    Apple's NSKeyedArchiver stores cross-references as plistlib.UID objects
    (not plain ints). Each UID's integer value is an index into the $objects
    array. We resolve the UID → index → string.
    """
    idx = None
    if isinstance(val, plistlib.UID):
        idx = int(val)
    elif isinstance(val, int):
        idx = val

    if idx is not None and 0 <= idx < len(objects):
        resolved = objects[idx]
        if isinstance(resolved, str) and resolved != "$null":
            return resolved
    if isinstance(val, str) and val != "$null":
        return val
    return None


def _parse_reverse_location(blob) -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str], Optional[str]]:
    """
    Parse a binary plist blob from ZREVERSELOCATIONDATA.

    Apple stores reverse-geocoded location data as an NSKeyedArchiver binary
    plist. The $objects array contains a postalAddress dict with explicit keys
    (_country, _city, _state, etc.) whose values are UID references into the
    same $objects array.

    Returns (country, city, state, sub_admin, sub_locality) — all raw Apple
    values. City normalization happens separately in _normalize_city().
    """
    if blob is None:
        return None, None, None, None, None

    try:
        plist = plistlib.loads(blob)
    except Exception:
        return None, None, None, None, None

    if not isinstance(plist, dict):
        return None, None, None, None, None

    objects = plist.get("$objects")
    if not objects or not isinstance(objects, list):
        return None, None, None, None, None

    # Primary: find the postalAddress dict (has _country, _city keys)
    for obj in objects:
        if isinstance(obj, dict) and "_country" in obj:
            country = _resolve_uid(objects, obj.get("_country"))
            city = _resolve_uid(objects, obj.get("_city"))
            state = _resolve_uid(objects, obj.get("_state"))
            sub_admin = _resolve_uid(objects, obj.get("_subAdministrativeArea"))
            sub_locality = _resolve_uid(objects, obj.get("_subLocality"))
            return country, city, state, sub_admin, sub_locality

    return None, None, None, None, None


def _normalize_city(country, city, state, sub_admin):
    """
    Normalize city to metro level.

    Apple's _city is district-level for big metros:
    - Turkey: _city=Beşiktaş, _state=Istanbul → use state
    - UK/Greece: _city=Hounslow, _subAdmin=London → use subAdmin
    - France: _city=Clichy, _state=Île-de-France → use state→metro mapping
    - Ireland: _city=Dublin 2 → strip postal district number
    - US/Italy/others: _city is already correct (New York, Florence)
    """
    if country == "Türkiye" and state:
        return state
    if country in ("United Kingdom", "Greece") and sub_admin:
        return sub_admin
    if country == "France" and state:
        # French regions → metro city (only Île-de-France for now)
        return _FRANCE_REGION_TO_METRO.get(state, city or state)
    if country == "Ireland" and city:
        # Strip postal district numbers: "Dublin 2" → "Dublin"
        return _strip_postal_district(city)
    return city or sub_admin or state or "Unknown"


# French region → metro city mapping
_FRANCE_REGION_TO_METRO = {
    "Île-de-France": "Paris",
}


def _strip_postal_district(city):
    """Strip postal district numbers: 'Dublin 2' → 'Dublin'."""
    import re
    m = re.match(r'^(.+?)\s+\d+$', city)
    return m.group(1) if m else city


def _compute_cutoff_cocoa():
    """Compute the Cocoa timestamp for YEARS_BACK years ago."""
    now = datetime.now(tz=timezone.utc)
    cutoff = now.replace(year=now.year - YEARS_BACK)
    cutoff_unix = cutoff.timestamp()
    return cutoff_unix - COCOA_EPOCH_OFFSET


def extract_photo_data(db_path=None, debug_plists=False):
    """
    Extract geotagged photo data from the macOS Photos database.

    Args:
        db_path: Path to Photos.sqlite. Uses default if None.
        debug_plists: If True, print the structure of the first few plists
                      for schema investigation.

    Returns:
        pd.DataFrame with columns:
            latitude, longitude, date, year, month, filename,
            country, city, district, state
    """
    if db_path is None:
        db_path = DEFAULT_DB_PATH

    if not os.path.exists(db_path):
        raise FileNotFoundError(
            f"Photos database not found at: {db_path}\n"
            "Make sure your Photos library is at the default location."
        )

    six_years_ago = _compute_cutoff_cocoa()

    # Open database read-only to avoid any risk of modification
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)

    try:
        cursor = conn.execute(
            """
            SELECT
                z.Z_PK,
                z.ZLATITUDE,
                z.ZLONGITUDE,
                z.ZDATECREATED,
                a.ZORIGINALFILENAME,
                a.ZREVERSELOCATIONDATA
            FROM ZASSET z
            LEFT JOIN ZADDITIONALASSETATTRIBUTES a ON a.ZASSET = z.Z_PK
            WHERE z.ZLATITUDE != -180.0
              AND z.ZLONGITUDE != -180.0
              AND z.ZLATITUDE IS NOT NULL
              AND z.ZLONGITUDE IS NOT NULL
              AND z.ZTRASHEDSTATE = 0
              AND z.ZDATECREATED >= ?
            ORDER BY z.ZDATECREATED
            """,
            (six_years_ago,),
        )

        rows = cursor.fetchall()
    finally:
        conn.close()

    if not rows:
        print("No geotagged photos found in the last 6 years.")
        return pd.DataFrame(
            columns=[
                "latitude", "longitude", "date", "year", "month",
                "filename", "country", "city", "district", "state",
            ]
        )

    # Debug: inspect plist structure if requested
    if debug_plists:
        print("\n=== DEBUG: First 3 plist structures ===")
        for row in rows[:3]:
            blob = row[5]
            if blob:
                try:
                    plist = plistlib.loads(blob)
                    print(f"\nPhoto {row[0]} ({row[4]}):")
                    _debug_print_plist(plist)
                except Exception as e:
                    print(f"  Failed to parse: {e}")
        print("=== END DEBUG ===\n")

    records = []
    missing_indices = []  # indices needing fallback geocoding

    for row in rows:
        pk, lat, lon, cocoa_ts, filename, rev_blob = row

        dt = _cocoa_to_datetime(cocoa_ts)
        country, raw_city, state, sub_admin, sub_locality = _parse_reverse_location(rev_blob)
        metro_city = _normalize_city(country, raw_city, state, sub_admin) if country else None
        district = raw_city or sub_locality or sub_admin or ""

        records.append(
            {
                "latitude": lat,
                "longitude": lon,
                "date": dt,
                "year": dt.year if dt else None,
                "month": dt.strftime("%Y-%m") if dt else None,
                "filename": filename or f"photo_{pk}",
                "country": country,
                "city": metro_city,
                "district": district,
                "state": state or "",
            }
        )

        if not country:
            missing_indices.append(len(records) - 1)

    # Batch reverse-geocode photos that Apple didn't geocode
    if missing_indices:
        _fill_missing_geocoding(records, missing_indices)

    df = pd.DataFrame(records)
    df["date"] = pd.to_datetime(df["date"], utc=True)

    # Fix encoding mismatches between Apple (proper Unicode) and
    # reverse_geocoder (ASCII). E.g., "Mugla" → "Muğla"
    df["city"] = df["city"].replace(_CITY_NAME_FIXES)

    # Drop photos with no usable location data
    before = len(df)
    df = df[df["city"] != "Unknown"].reset_index(drop=True)
    dropped = before - len(df)
    if dropped:
        print(f"Dropped {dropped} photos with unknown location.")

    return df


# Known ASCII→Unicode fixes from reverse_geocoder vs Apple data
_CITY_NAME_FIXES = {
    "Mugla": "Muğla",
    "Izmir": "İzmir",
    "Canakkale": "Çanakkale",
    "Sanliurfa": "Şanlıurfa",
}


def _fill_missing_geocoding(records, missing_indices):
    """
    Use offline reverse geocoding to fill in photos that have GPS
    coordinates but no Apple reverse-geocoding data.
    """
    try:
        import reverse_geocoder as rg
        import pycountry
    except ImportError:
        # Libraries not available — fall back to Unknown
        for idx in missing_indices:
            r = records[idx]
            r["country"] = r["country"] or "Unknown"
            r["city"] = r["city"] or "Unknown"
            r.setdefault("district", "")
        return

    coords = [(records[i]["latitude"], records[i]["longitude"]) for i in missing_indices]
    results = rg.search(coords, verbose=False)

    for idx, geo in zip(missing_indices, results):
        cc = geo.get("cc", "")
        c = pycountry.countries.get(alpha_2=cc)
        country_name = c.name if c else cc

        city_name = geo.get("name", "")
        admin1 = geo.get("admin1", "")

        records[idx]["country"] = country_name or "Unknown"
        records[idx]["city"] = admin1 or city_name or "Unknown"
        records[idx]["district"] = city_name or ""
        if not records[idx]["state"]:
            records[idx]["state"] = admin1 or ""


def _debug_print_plist(plist, indent=0):
    """Pretty-print a plist structure for debugging."""
    prefix = "  " * indent
    if isinstance(plist, dict):
        for key, val in plist.items():
            if key == "$objects" and isinstance(val, list):
                print(f"{prefix}{key}: [{len(val)} objects]")
                for i, obj in enumerate(val[:20]):
                    if isinstance(obj, str):
                        print(f"{prefix}  [{i}] str: {obj!r}")
                    elif isinstance(obj, dict):
                        print(f"{prefix}  [{i}] dict: {list(obj.keys())}")
                    elif isinstance(obj, (int, float, bool)):
                        print(f"{prefix}  [{i}] {type(obj).__name__}: {obj}")
                    elif isinstance(obj, bytes):
                        print(f"{prefix}  [{i}] bytes({len(obj)})")
                    else:
                        print(f"{prefix}  [{i}] {type(obj).__name__}")
            elif isinstance(val, (dict, list)):
                print(f"{prefix}{key}:")
                _debug_print_plist(val, indent + 1)
            elif isinstance(val, bytes):
                print(f"{prefix}{key}: bytes({len(val)})")
            else:
                print(f"{prefix}{key}: {val!r}")
    elif isinstance(plist, list):
        for i, item in enumerate(plist[:10]):
            print(f"{prefix}[{i}]: {item!r}")
