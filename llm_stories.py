"""
llm_stories.py — Generate narrative descriptions for trips and years via Claude.

Takes a complete timeline dict (from trips.py), sends it to Claude, and
returns the same dict with 'narrative' and 'tagline' fields added to each
trip and 'narrative' to each year summary.
"""

import json

from pydantic import BaseModel

from llm_client import (
    get_client,
    compute_cache_key,
    load_cached,
    save_cached,
    NARRATIVE_MODEL,
)

PROMPT_VERSION = "stories-v2"


class TripNarrative(BaseModel):
    trip_id: str
    narrative: str
    tagline: str


class YearNarrative(BaseModel):
    year: int
    narrative: str


class NarrativeResult(BaseModel):
    trip_narratives: list[TripNarrative]
    year_narratives: list[YearNarrative]


SYSTEM_PROMPT = """You are a travel storyteller writing brief, evocative descriptions of someone's trips.

STYLE RULES:
- Write in second person ("You spent...", "You explored...")
- Be warm but concise — no fluff or filler
- Reference specific cities, seasons, and durations
- Taglines should be 5-8 words, evocative and poetic (e.g. "Island-hopping through the Aegean blue")
- Trip narratives: 1-3 sentences capturing the essence of the trip
- Year narratives: 2-4 sentences summarizing the year's travel pattern
- Use seasonal language when relevant (summer, winter, spring adventures)
- For multi-city trips, mention the journey between places
- For repeat destinations, acknowledge the return ("Back in Muğla...")
- Keep the tone personal and reflective, like a travel journal

IMPORTANT:
- You MUST provide a narrative and tagline for EVERY trip in the input
- You MUST provide a narrative for EVERY year in the input
- The trip_id must match exactly the 'id' field from the input trips
- The year must match exactly the 'year' field from the input years"""


def generate_narratives(timeline):
    """
    Main entry point: add narratives to a timeline dict.

    Returns the timeline dict with narrative/tagline fields added to
    trips and years.
    """
    # Build a compact version of the timeline for the prompt
    compact = _build_compact_timeline(timeline)

    cache_key = compute_cache_key(compact, PROMPT_VERSION)
    cached = load_cached(cache_key, "stories")

    if cached is not None:
        result = NarrativeResult(**cached)
        print(f"Using cached narratives ({len(result.trip_narratives)} trips, "
              f"{len(result.year_narratives)} years)")
    else:
        result = _call_claude_stories(compact)
        save_cached(cache_key, "stories", result.model_dump())
        print(f"Generated narratives for {len(result.trip_narratives)} trips, "
              f"{len(result.year_narratives)} years")

    return _merge_narratives(timeline, result)


def _build_compact_timeline(timeline):
    """
    Build a compact representation of the timeline for the Claude prompt.

    Strips coordinates and photo counts to save tokens while keeping
    all the information Claude needs for storytelling.
    """
    compact_trips = []
    for trip in timeline["trips"]:
        compact_trips.append({
            "id": trip["id"],
            "departure_date": trip["departure_date"],
            "return_date": trip["return_date"],
            "duration_days": trip["duration_days"],
            "countries": trip["countries"],
            "cities": trip["cities"],
            "stops": [
                {
                    "city": s["city"],
                    "country": s["country"],
                    "days": s["days"],
                    "arrival_date": s["arrival_date"],
                }
                for s in trip["stops"]
            ],
        })

    compact_years = []
    for year in timeline["years"]:
        compact_years.append({
            "year": year["year"],
            "trips_count": year["trips_count"],
            "countries": year["countries"],
            "new_countries": year["new_countries"],
            "days_abroad": year["days_abroad"],
            "longest_trip": year["longest_trip"],
        })

    return {
        "home_base": {
            "city": timeline["home_base"]["city"],
            "country": timeline["home_base"]["country"],
        },
        "trips": compact_trips,
        "years": compact_years,
    }


def _call_claude_stories(compact_timeline):
    """Send the timeline to Claude and get narratives back."""
    client = get_client()

    user_msg = (
        "Here is a complete travel timeline. Please write a narrative and tagline "
        "for each trip, and a narrative for each year.\n\n"
        f"```json\n{json.dumps(compact_timeline, indent=2, ensure_ascii=False)}\n```"
    )

    response = client.messages.parse(
        model=NARRATIVE_MODEL,
        max_tokens=8192,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_msg}],
        output_format=NarrativeResult,
    )

    return response.parsed_output


def _merge_narratives(timeline, result):
    """Merge narrative results back into the timeline dict."""
    # Build lookup maps
    trip_narr = {n.trip_id: n for n in result.trip_narratives}
    year_narr = {n.year: n for n in result.year_narratives}

    for trip in timeline["trips"]:
        narr = trip_narr.get(trip["id"])
        if narr:
            trip["narrative"] = narr.narrative
            trip["tagline"] = narr.tagline
        else:
            trip["narrative"] = ""
            trip["tagline"] = ""

    for year in timeline["years"]:
        narr = year_narr.get(year["year"])
        if narr:
            year["narrative"] = narr.narrative
        else:
            year["narrative"] = ""

    return timeline
