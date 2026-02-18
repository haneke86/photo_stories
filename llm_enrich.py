"""
llm_enrich.py — Use Claude to fix city names that static rules get wrong.

Aggregates photos into (date, lat_rounded, lon_rounded) groups, identifies
groups with suspicious city names (regions, airports, obscure admin names),
and asks Claude to resolve them to metro-level city names using GPS coords.

Works as a pre-trip-detection enrichment step on the raw DataFrame.
"""

import math

from pydantic import BaseModel

from llm_client import (
    get_client,
    compute_cache_key,
    load_cached,
    save_cached,
    DEFAULT_MODEL,
)

PROMPT_VERSION = "enrich-v2"

# Names that signal the city wasn't properly resolved to metro level.
# These are regions, admin areas, airport zones, and generic labels.
SUSPICIOUS_PATTERNS = {
    # UK/European regions
    "Home Counties", "South East", "South West", "East Midlands",
    "West Midlands", "North West", "North East", "East of England",
    # Greek admin regions
    "South Aegean", "North Aegean", "Central Macedonia",
    "Eastern Macedonia and Thrace", "Western Greece", "Peloponnese",
    "Attica", "Ionian Islands", "Crete", "Thessaly", "Epirus",
    "Western Macedonia", "Central Greece",
    # Cyprus admin
    "Ammochostos", "Famagusta",
    # Turkish regions that leaked through
    "Marmara", "Aegean", "Mediterranean", "Black Sea",
    "Central Anatolia", "Eastern Anatolia", "Southeastern Anatolia",
    # Generic
    "Unknown", "Airport",
}

# Also flag city names that look like admin codes or are too short
MIN_CITY_NAME_LENGTH = 2


class EnrichedLocation(BaseModel):
    group_id: str
    city: str
    country: str
    confidence: float


class EnrichmentResult(BaseModel):
    corrections: list[EnrichedLocation]


def enrich_dataframe(df):
    """
    Main entry point: enrich a photo DataFrame with Claude-corrected city names.

    Returns the DataFrame with corrected city/country values where Claude
    had high confidence (>= 0.5).
    """
    groups = _build_location_groups(df)
    candidates = _identify_enrichment_candidates(groups)

    if not candidates:
        print("No locations need enrichment.")
        return df

    # Check cache
    cache_input = [
        {"id": c["id"], "lat": c["lat"], "lon": c["lon"],
         "city": c["city"], "country": c["country"]}
        for c in candidates
    ]
    cache_key = compute_cache_key(cache_input, PROMPT_VERSION)
    cached = load_cached(cache_key, "enrich")

    if cached is not None:
        result = EnrichmentResult(**cached)
        print(f"Using cached enrichment ({len(result.corrections)} corrections)")
    else:
        result = _call_claude_enrich(candidates)
        save_cached(cache_key, "enrich", result.model_dump())
        print(f"Enriched {len(result.corrections)} locations via Claude")

    return _apply_corrections(df, result, groups)


def _build_location_groups(df):
    """
    Aggregate photos into (date, lat_rounded, lon_rounded) groups.

    Rounds coordinates to ~1km precision (2 decimal places) to group
    nearby photos on the same day together.
    """
    df = df.copy()
    df["date_only"] = df["date"].dt.date
    df["lat_r"] = df["latitude"].round(2)
    df["lon_r"] = df["longitude"].round(2)

    groups = []
    for (date_only, lat_r, lon_r), chunk in df.groupby(["date_only", "lat_r", "lon_r"]):
        group_id = f"{date_only}_{lat_r}_{lon_r}"
        groups.append({
            "id": group_id,
            "date": str(date_only),
            "lat": float(lat_r),
            "lon": float(lon_r),
            "city": chunk["city"].mode().iloc[0] if not chunk["city"].mode().empty else "Unknown",
            "country": chunk["country"].mode().iloc[0] if not chunk["country"].mode().empty else "Unknown",
            "photo_count": len(chunk),
            "indices": chunk.index.tolist(),
        })

    return groups


def _identify_enrichment_candidates(groups):
    """Filter to groups with missing or suspicious city names."""
    candidates = []
    for g in groups:
        city = g["city"]
        if (
            not city
            or city in SUSPICIOUS_PATTERNS
            or len(city) < MIN_CITY_NAME_LENGTH
            or _looks_like_region(city)
        ):
            candidates.append(g)

    return candidates


def _looks_like_region(city):
    """Heuristic: names with 'Region', 'Province', 'District' are suspect."""
    lowered = city.lower()
    return any(w in lowered for w in ("region", "province", " district", "prefecture"))


SYSTEM_PROMPT = """You are a geographic data specialist. Your task is to correct city names for geotagged photos.

RULES:
- GPS coordinates are ALWAYS correct. Use them to determine the actual metro-level city.
- For Turkish locations: provinces (il) ARE the metro cities (Istanbul, Ankara, İzmir, Antalya, Muğla, etc.)
- For Greek islands: use the island name (Rhodes, Mykonos, Santorini, Crete/Heraklion, Corfu, etc.)
- For UK locations: use the nearest major city (London, Manchester, Birmingham, Edinburgh, etc.)
- For Cyprus: use the actual city (Famagusta, Nicosia, Larnaca, Limassol, Paphos, etc.)
- Airport locations → use the nearest city
- Admin region names → resolve to the actual metro city
- Use internationally recognized English names (Istanbul not İstanbul in the country field, but İstanbul is fine for city)
- Keep country names consistent with the input data

For each location, provide your corrected city name and a confidence score (0.0 to 1.0):
- 1.0 = GPS clearly in a well-known metro area
- 0.7-0.9 = confident based on coordinates + context
- 0.3-0.6 = reasonable guess but ambiguous (rural area, border zone)
- < 0.3 = too uncertain to correct

Only include locations where you have a correction. Skip any that are already correct."""


def _call_claude_enrich(candidates):
    """Send enrichment candidates to Claude in batches of 100."""
    client = get_client()
    all_corrections = []

    for i in range(0, len(candidates), 100):
        batch = candidates[i:i + 100]
        locations_text = "\n".join(
            f"- ID: {c['id']} | GPS: ({c['lat']}, {c['lon']}) | "
            f"Current city: \"{c['city']}\" | Country: \"{c['country']}\""
            for c in batch
        )

        user_msg = (
            f"Here are {len(batch)} photo location groups that may have incorrect city names. "
            f"Please correct any that need fixing:\n\n{locations_text}"
        )

        response = client.messages.parse(
            model=DEFAULT_MODEL,
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_msg}],
            output_format=EnrichmentResult,
        )

        all_corrections.extend(response.parsed_output.corrections)

    return EnrichmentResult(corrections=all_corrections)


def _apply_corrections(df, result, groups):
    """Write Claude's corrections back to the DataFrame."""
    # Build group_id → indices mapping
    group_index_map = {g["id"]: g["indices"] for g in groups}

    applied = 0
    for correction in result.corrections:
        if correction.confidence < 0.5:
            continue
        indices = group_index_map.get(correction.group_id, [])
        if indices:
            df.loc[indices, "city"] = correction.city
            df.loc[indices, "country"] = correction.country
            applied += 1

    if applied:
        print(f"  Applied {applied} city corrections (confidence >= 0.5)")

    return df
