"""
trips.py — Detect trips from photo location data and build a timeline.

Groups photos into trips (time away from home base), handles multi-stop
trips, domestic vacations, and produces a structured timeline dict.
"""

import json
import math
import os
from collections import Counter
from datetime import timedelta
from typing import Any

import pandas as pd


# Distance threshold for "home zone" in km
HOME_RADIUS_KM = 30

# Gap threshold: if no geotagged photos for N days during travel, assume trip ended.
# Set to 7 because some photos lack GPS data in the DB, creating artificial gaps.
TRIP_GAP_DAYS = 7


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

    # Merge same-city stops within this trip
    stops = _merge_same_city_stops(stops)

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



def _merge_same_city_stops(stops):
    """
    Merge all stops in the same city within a trip, preserving order.

    Unlike adjacent-only merging, this handles cases like
    Muğla → Paris → Muğla by consolidating both Muğla stops.
    The merged stop uses the earliest arrival date and combined days.
    """
    if not stops:
        return stops

    # Track which city keys we've seen and their index in merged list
    seen = {}  # (city, country) → index in merged
    merged = []

    for s in stops:
        key = (s["city"], s["country"])
        if key in seen:
            # Merge into existing stop
            prev = merged[seen[key]]
            prev["districts"] = sorted(set(prev["districts"] + s["districts"]))
            prev["days"] += s["days"]
            prev["photo_count"] += s["photo_count"]
        else:
            seen[key] = len(merged)
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
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(timeline, f, indent=2, ensure_ascii=False, default=str)
    print(f"Timeline saved to: {output_path}")
