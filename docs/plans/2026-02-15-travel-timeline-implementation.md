# Travel Timeline Dashboard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the photo-count dashboard with a trip-based travel story timeline, powered by a timeline.json intermediate artifact.

**Architecture:** extract.py (city normalization) → trips.py (new: trip detection + timeline JSON) → dashboard.py (rewritten: story-focused) → new HTML template. The pipeline runs: DataFrame → timeline dict → JSON file + HTML dashboard.

**Tech Stack:** Python 3, pandas, plotly, jinja2, reverse_geocoder, pycountry, math (haversine)

---

### Task 1: Add City Normalization to extract.py

**Files:**
- Modify: `extract.py:59-97` (_parse_reverse_location)
- Modify: `extract.py:186-218` (extract_photo_data records building)

**Context:** Currently `_parse_reverse_location` returns `(country, city, state)` where `city` is district-level (Beşiktaş, Hounslow). We need to also extract `subAdministrativeArea` and return a `district` field alongside a normalized `city` (metro-level).

**Step 1: Update `_parse_reverse_location` to return 5 fields**

Change return type to `(country, city, state, sub_admin, sub_locality)`. Extract `_subAdministrativeArea` and `_subLocality` as separate fields instead of using them as city fallbacks.

```python
def _parse_reverse_location(blob) -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str], Optional[str]]:
    # ... existing plist parsing ...
    for obj in objects:
        if isinstance(obj, dict) and "_country" in obj:
            country = _resolve_uid(objects, obj.get("_country"))
            city = _resolve_uid(objects, obj.get("_city"))
            state = _resolve_uid(objects, obj.get("_state"))
            sub_admin = _resolve_uid(objects, obj.get("_subAdministrativeArea"))
            sub_locality = _resolve_uid(objects, obj.get("_subLocality"))
            return country, city, state, sub_admin, sub_locality
    return None, None, None, None, None
```

**Step 2: Add `_normalize_city` function**

```python
def _normalize_city(country, city, state, sub_admin):
    """
    Normalize city to metro level.

    Apple's _city is district-level for big metros:
    - Turkey: _city=Beşiktaş, _state=Istanbul → use state
    - UK/Greece: _city=Hounslow, _subAdmin=London → use subAdmin
    - US/Italy/others: _city is already correct (New York, Florence)
    """
    if country == "Türkiye" and state:
        # Turkish _state = province/metro (Istanbul, Ankara, Muğla, İzmir)
        return state
    if country in ("United Kingdom", "Greece") and sub_admin:
        return sub_admin
    # Default: use city as-is, fall back to sub_admin, then state
    return city or sub_admin or state or "Unknown"
```

**Step 3: Update record building in `extract_photo_data`**

Each record now has both `city` (metro) and `district` (original Apple city):

```python
country, raw_city, state, sub_admin, sub_locality = _parse_reverse_location(rev_blob)
metro_city = _normalize_city(country, raw_city, state, sub_admin)
district = raw_city or sub_locality or sub_admin or ""

records.append({
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
})
```

**Step 4: Update `_fill_missing_geocoding` for new schema**

Add `district` field, use `admin1` as city (metro-level from reverse_geocoder):

```python
records[idx]["city"] = geo.get("admin1", "") or geo.get("name", "") or "Unknown"
records[idx]["district"] = geo.get("name", "") or ""
```

**Step 5: Run and verify**

```bash
source .venv/bin/activate
python -c "
from extract import extract_photo_data
df = extract_photo_data()
print(f'Cities: {df.city.nunique()}')
print(df[['city', 'district', 'country']].drop_duplicates().sort_values('country').to_string())
"
```

Expected: ~50-60 metro-level cities instead of ~164.

**Step 6: Commit**

```bash
git add extract.py
git commit -m "feat: add metro-level city normalization to extract"
```

---

### Task 2: Create trips.py — Trip Detection Engine

**Files:**
- Create: `trips.py`

**Context:** This is the core new module. Takes a DataFrame, detects home base, identifies trips, and produces a timeline dict that can be serialized to JSON.

**Step 1: Write home detection**

```python
"""
trips.py — Detect trips from photo location data and build a timeline.

Groups photos into trips (time away from home base), handles multi-stop
trips, domestic vacations, and produces a structured timeline dict.
"""

import json
import math
from collections import Counter
from datetime import timedelta
from typing import Any

import pandas as pd


# Distance threshold for "home zone" in km
HOME_RADIUS_KM = 30

# Gap threshold: if no photos for N days during travel, assume trip ended
TRIP_GAP_DAYS = 5


def _haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance between two points in km."""
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlon / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


def detect_home_base(df):
    """
    Auto-detect home base as the city where the user has the most photo-days.

    Returns dict with city, country, center lat/lon.
    """
    df_copy = df.copy()
    df_copy["date_only"] = df_copy["date"].dt.date

    # Count unique days per city (not photo count — avoids bias from tourist bursts)
    city_days = (df_copy.groupby(["city", "country"])["date_only"]
                 .nunique()
                 .reset_index(name="days"))
    top = city_days.sort_values("days", ascending=False).iloc[0]

    home_photos = df[(df["city"] == top["city"]) & (df["country"] == top["country"])]

    return {
        "city": top["city"],
        "country": top["country"],
        "center": {
            "lat": round(float(home_photos["latitude"].median()), 4),
            "lon": round(float(home_photos["longitude"].median()), 4),
        },
        "radius_km": HOME_RADIUS_KM,
    }


def _is_home(lat, lon, home_base):
    """Check if coordinates are within the home zone."""
    dist = _haversine_km(
        lat, lon,
        home_base["center"]["lat"], home_base["center"]["lon"],
    )
    return dist <= home_base["radius_km"]


def detect_trips(df, home_base):
    """
    Detect trips from chronologically sorted photo data.

    A trip is a contiguous stretch of days with photos outside the home zone.
    Multi-stop trips (multiple countries/cities without returning home) are
    grouped as one trip with multiple stops.

    Returns list of trip dicts.
    """
    df = df.sort_values("date").copy()
    df["date_only"] = df["date"].dt.date
    df["at_home"] = df.apply(
        lambda r: _is_home(r["latitude"], r["longitude"], home_base), axis=1
    )

    trips = []
    current_trip_photos = []

    for _, row in df.iterrows():
        if row["at_home"]:
            # If we have accumulated trip photos, finalize the trip
            if current_trip_photos:
                trip = _build_trip(current_trip_photos)
                if trip:
                    trips.append(trip)
                current_trip_photos = []
        else:
            # Check for gap — if too long since last photo, split trip
            if current_trip_photos:
                last_date = current_trip_photos[-1]["date_only"]
                gap = (row["date_only"] - last_date).days
                if gap > TRIP_GAP_DAYS:
                    trip = _build_trip(current_trip_photos)
                    if trip:
                        trips.append(trip)
                    current_trip_photos = []
            current_trip_photos.append(row.to_dict())

    # Don't forget last trip if it didn't end with home
    if current_trip_photos:
        trip = _build_trip(current_trip_photos)
        if trip:
            trips.append(trip)

    return trips


def _build_trip(photos):
    """Build a trip dict from a list of photo records."""
    if not photos:
        return None

    departure = min(p["date_only"] for p in photos)
    return_date = max(p["date_only"] for p in photos)
    duration = (return_date - departure).days + 1

    # Build stops: group consecutive photos by (city, country)
    stops = []
    current_stop = None

    for p in sorted(photos, key=lambda x: x["date_only"]):
        key = (p["city"], p["country"])
        if current_stop is None or current_stop["_key"] != key:
            if current_stop:
                stops.append(_finalize_stop(current_stop))
            current_stop = {
                "_key": key,
                "city": p["city"],
                "country": p["country"],
                "districts": set(),
                "dates": set(),
                "lats": [],
                "lons": [],
                "photo_count": 0,
            }
        current_stop["districts"].add(p.get("district", ""))
        current_stop["dates"].add(p["date_only"])
        current_stop["lats"].append(p["latitude"])
        current_stop["lons"].append(p["longitude"])
        current_stop["photo_count"] += 1

    if current_stop:
        stops.append(_finalize_stop(current_stop))

    # Merge consecutive stops in the same city (e.g., left and came back same trip)
    stops = _merge_adjacent_stops(stops)

    # Trip-level summary
    all_countries = list(dict.fromkeys(s["country"] for s in stops))
    all_cities = list(dict.fromkeys(s["city"] for s in stops))

    # Generate readable trip ID
    primary = all_cities[0] if len(all_cities) == 1 else all_countries[0]
    trip_id = f"{departure.isoformat()}-{primary.lower().replace(' ', '-')}"

    return {
        "id": trip_id,
        "departure_date": departure.isoformat(),
        "return_date": return_date.isoformat(),
        "duration_days": duration,
        "photo_count": len(photos),
        "countries": all_countries,
        "cities": all_cities,
        "stops": stops,
    }


def _finalize_stop(stop):
    """Convert a working stop dict to its final form."""
    districts = sorted(d for d in stop["districts"] if d)
    dates = sorted(stop["dates"])
    return {
        "city": stop["city"],
        "country": stop["country"],
        "districts": districts,
        "arrival_date": dates[0].isoformat(),
        "days": (dates[-1] - dates[0]).days + 1,
        "photo_count": stop["photo_count"],
        "coordinates": {
            "lat": round(sum(stop["lats"]) / len(stop["lats"]), 4),
            "lon": round(sum(stop["lons"]) / len(stop["lons"]), 4),
        },
    }


def _merge_adjacent_stops(stops):
    """Merge consecutive stops in the same city."""
    if not stops:
        return stops
    merged = [stops[0]]
    for s in stops[1:]:
        prev = merged[-1]
        if s["city"] == prev["city"] and s["country"] == prev["country"]:
            # Merge into previous
            prev["districts"] = sorted(set(prev["districts"] + s["districts"]))
            prev["days"] += s["days"]
            prev["photo_count"] += s["photo_count"]
        else:
            merged.append(s)
    return merged


def build_year_summaries(trips, all_countries_ever):
    """
    Build per-year summary dicts.

    Tracks new countries (first time visited in any year).
    """
    seen_countries = set()
    years = {}

    for trip in sorted(trips, key=lambda t: t["departure_date"]):
        year = int(trip["departure_date"][:4])
        if year not in years:
            years[year] = {
                "year": year,
                "trips_count": 0,
                "countries": [],
                "new_countries": [],
                "days_abroad": 0,
                "longest_trip": None,
                "trips": [],
            }

        y = years[year]
        y["trips_count"] += 1
        y["days_abroad"] += trip["duration_days"]
        y["trips"].append(trip["id"])

        for c in trip["countries"]:
            if c not in y["countries"]:
                y["countries"].append(c)
            if c not in seen_countries:
                y["new_countries"].append(c)
                seen_countries.add(c)

        if (y["longest_trip"] is None
                or trip["duration_days"] > y["longest_trip"]["days"]):
            dest = trip["cities"][0] if len(trip["cities"]) == 1 else "Multi-city"
            y["longest_trip"] = {
                "destination": dest,
                "days": trip["duration_days"],
            }

    return [years[y] for y in sorted(years)]


def build_timeline(df):
    """
    Main entry point: build the complete timeline dict from a photo DataFrame.

    Returns a dict ready for JSON serialization.
    """
    home = detect_home_base(df)
    print(f"Home base detected: {home['city']}, {home['country']}")

    trips = detect_trips(df, home)
    print(f"Detected {len(trips)} trips")

    all_countries = sorted(df["country"].unique().tolist())
    year_summaries = build_year_summaries(trips, all_countries)

    # All-time stats
    total_days = sum(t["duration_days"] for t in trips)
    trip_countries = set()
    trip_cities = set()
    for t in trips:
        trip_countries.update(t["countries"])
        trip_cities.update(t["cities"])

    timeline = {
        "home_base": home,
        "date_range": {
            "from": df["date"].min().strftime("%Y-%m-%d"),
            "to": df["date"].max().strftime("%Y-%m-%d"),
        },
        "summary": {
            "total_trips": len(trips),
            "countries_visited": len(trip_countries),
            "cities_visited": len(trip_cities),
            "total_days_traveling": total_days,
        },
        "years": year_summaries,
        "trips": trips,
    }

    return timeline


def save_timeline_json(timeline, output_path):
    """Save timeline dict to a JSON file."""
    import os
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(timeline, f, indent=2, ensure_ascii=False, default=str)
    print(f"Timeline saved to: {output_path}")
```

**Step 2: Run and inspect the timeline**

```bash
source .venv/bin/activate
python -c "
from extract import extract_photo_data
from trips import build_timeline, save_timeline_json
df = extract_photo_data()
timeline = build_timeline(df)
save_timeline_json(timeline, 'output/timeline.json')
print(f'Trips: {timeline[\"summary\"][\"total_trips\"]}')
print(f'Countries: {timeline[\"summary\"][\"countries_visited\"]}')
for y in timeline['years']:
    print(f'  {y[\"year\"]}: {y[\"trips_count\"]} trips, {y[\"days_abroad\"]}d abroad')
for t in timeline['trips'][:5]:
    cities = ', '.join(t['cities'])
    print(f'  {t[\"departure_date\"]} - {t[\"return_date\"]}: {cities} ({t[\"duration_days\"]}d)')
"
```

Expected: Recognizable trips with real city names and reasonable durations.

**Step 3: Inspect `output/timeline.json` manually, note any issues**

Open the file, scan for:
- Trips that are obviously wrong (too long, wrong city)
- Home-base photos misclassified as trips
- Missing trips you know happened

**Step 4: Commit**

```bash
git add trips.py
git commit -m "feat: add trip detection engine with timeline JSON generation"
```

---

### Task 3: Rewrite dashboard.py — Story-Focused Dashboard

**Files:**
- Rewrite: `dashboard.py` (complete rewrite)
- Rewrite: `templates/dashboard.html` (new template)

**Context:** Replace photo-count charts with trip-based story views. The dashboard now receives a `timeline` dict (not raw DataFrame). Keep the Plotly map but change it to show trip routes.

**Step 1: Rewrite `dashboard.py`**

New functions:
- `_build_trip_map(timeline)` — Map with trip cluster markers (one per trip, not per photo)
- `_build_year_cards(timeline)` — Data for per-year summary cards
- `_build_trip_cards(timeline)` — Data for individual trip cards
- `_compute_story_stats(timeline)` — Header stats (trips, countries, days abroad, longest trip)
- `generate_dashboard(timeline, df, output_path)` — Main entry, renders template

The map should show one marker per trip stop (averaged coordinates), sized by duration, colored by year. Trip cards show: destination, dates, duration, stops list, photo count.

**Step 2: Rewrite `templates/dashboard.html`**

New layout:
- Header: "Your Travel Story — N countries since YYYY"
- Stats row: Total Trips | Countries | Days Traveling | Longest Trip
- Map section: trip clusters
- Year sections: collapsible, each year has summary + trip cards
- Trip cards: destination name, dates, duration badge, stop list, photo count

Style: Keep the existing dark theme (#1a1a2e, #4ecdc4 accents). Use CSS grid for trip cards.

**Step 3: Run full pipeline and verify**

```bash
source .venv/bin/activate
python main.py
```

Dashboard should open in browser with the new story-focused layout.

**Step 4: Commit**

```bash
git add dashboard.py templates/dashboard.html
git commit -m "feat: rewrite dashboard with trip-based story layout"
```

---

### Task 4: Update main.py — Wire Up New Pipeline

**Files:**
- Modify: `main.py`

**Step 1: Update imports and pipeline**

```python
from extract import extract_photo_data
from trips import build_timeline, save_timeline_json
from dashboard import generate_dashboard
```

New flow in `main()`:
1. Extract photo data (existing)
2. Build timeline: `timeline = build_timeline(df)`
3. Save timeline JSON: `save_timeline_json(timeline, json_path)`
4. Generate dashboard: `generate_dashboard(timeline, df, html_path)`
5. Open in browser (existing)

Output paths:
- `output/YYYY-MM-DD-HHMM-timeline.json`
- `output/YYYY-MM-DD-HHMM-travel-story.html`

Print summary should now show trips-focused info:
```
Home base: Istanbul, Türkiye
Detected 34 trips across 21 countries
Generating travel story...
```

**Step 2: Run end-to-end**

```bash
source .venv/bin/activate
python main.py
```

Verify: timeline.json saved, HTML dashboard opens, shows trip cards.

**Step 3: Commit**

```bash
git add main.py
git commit -m "feat: wire up trip detection pipeline in main.py"
```

---

### Task 5: Polish and Data Quality Pass

**Files:**
- Possibly modify: `trips.py` (tune thresholds)
- Possibly modify: `extract.py` (fix edge cases)

**Step 1: Review timeline.json output**

Open `output/*-timeline.json` and check:
- Are all known trips detected?
- Are domestic Turkey vacations (Bodrum, Dalaman) showing as trips?
- Are same-day border crossings (Greece/Turkey) handled OK?
- Are trip durations reasonable?

**Step 2: Fix any obvious issues found**

Tune `HOME_RADIUS_KM` or `TRIP_GAP_DAYS` if needed. Fix city normalization edge cases.

**Step 3: Run final end-to-end and open dashboard in browser**

```bash
source .venv/bin/activate
python main.py
```

**Step 4: Commit**

```bash
git add -A
git commit -m "fix: tune trip detection and data quality"
```

---

## Execution Notes

- Tasks 1-2 are independent of Task 3 (extract/trips vs dashboard), but Task 4 depends on all three
- Task 3 (dashboard rewrite) is the largest — the HTML template will be substantial
- Task 5 is iterative — may require multiple passes based on what timeline.json reveals
- No tests prescribed for V1 (ship and iterate). Tests come when trip detection logic stabilizes.
