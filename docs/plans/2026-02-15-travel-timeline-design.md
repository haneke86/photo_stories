# MacPhoto Travel Timeline — Design

## Vision

Transform the photo-count dashboard into a **travel story generator**. The app auto-detects trips from photo GPS data and presents them as a personal travel timeline. V1 is a structured card-based dashboard. V2 adds an LLM-powered Q&A layer (OpenAI) that can answer "Where was I on June 15?", "How many days in Dalyan?", etc.

## Architecture

### Pipeline

```
Photos.sqlite → extract.py → DataFrame (with metro-level city normalization)
                                  ↓
                            trips.py → timeline.json
                                  ↓
                          dashboard.py → HTML dashboard (V1)
                                  ↓
                            chat.py → OpenAI Q&A (V2)
```

### Core Artifact: timeline.json

The timeline JSON is the single source of truth. The dashboard renders it, the LLM reads it.

```json
{
  "generated_at": "2026-02-15T01:55:00Z",
  "home_base": {
    "city": "Istanbul",
    "country": "Türkiye",
    "center": { "lat": 41.01, "lon": 29.01 },
    "radius_km": 30
  },
  "date_range": { "from": "2020-02-17", "to": "2025-09-14" },
  "summary": {
    "total_trips": 34,
    "countries_visited": 21,
    "cities_visited": 55,
    "total_days_traveling": 187
  },
  "years": [
    {
      "year": 2024,
      "trips_count": 8,
      "countries": ["Malta", "Germany", "Switzerland", "Liechtenstein"],
      "new_countries": ["Germany", "Liechtenstein"],
      "days_abroad": 45,
      "longest_trip": { "destination": "Europe", "days": 18 },
      "busiest_month": "July"
    }
  ],
  "trips": [
    {
      "id": "2025-06-malta",
      "departure_date": "2025-06-13",
      "return_date": "2025-06-18",
      "duration_days": 5,
      "photo_count": 47,
      "stops": [
        {
          "city": "St Julian's",
          "country": "Malta",
          "districts": ["St Julian's", "Valletta", "Sliema"],
          "arrival_date": "2025-06-13",
          "days": 5,
          "coordinates": { "lat": 35.91, "lon": 14.49 }
        }
      ]
    },
    {
      "id": "2024-03-europe",
      "departure_date": "2024-03-08",
      "return_date": "2024-03-15",
      "duration_days": 7,
      "photo_count": 120,
      "stops": [
        { "city": "Bern", "country": "Switzerland", "days": 2 },
        { "city": "Vaduz", "country": "Liechtenstein", "days": 1 },
        { "city": "Zürich", "country": "Switzerland", "days": 2 }
      ]
    }
  ]
}
```

### Data Extraction: City Normalization

Apple's `_city` field returns district/municipality names (Beşiktaş, Hounslow, Tower Hamlets). We extract both levels from the postalAddress:

- `district` = Apple's `_city` field (sub-city level)
- `city` = metro-level, normalized:
  - Turkey: use `_state` (Istanbul, Ankara, Muğla, İzmir)
  - UK/Greece: use `_subAdministrativeArea` (London, Lesbos)
  - US/Italy/others: use `_city` as-is (already correct: New York, Florence)
- Fallback: offline `reverse_geocoder` for photos with no Apple geocoding

This collapses ~164 district-level entries into ~50-60 real cities.

### Trip Detection (trips.py)

1. **Home zone**: auto-detect the city with the most photos. Define as a coordinate circle (center + 30km radius).
2. **Sort photos chronologically**.
3. **Trip boundaries**: a trip starts when photos appear outside the home zone. It ends when photos return to the home zone (or a gap > N days suggests return home without photos).
4. **Multi-stop grouping**: consecutive days abroad without returning home = one trip with multiple stops. Country/city changes within a trip become separate stops.
5. **Domestic trips**: time in Turkey but outside Istanbul zone (Bodrum, Dalaman coast, Ankara) counts as trips.
6. **Edge cases**:
   - Same-day border bouncing (Greece/Turkey ferries): treat as one stop if < 1 day in each
   - Photo gaps during trips: if abroad gap < 5 days, assume still on same trip
   - NaN cities: assign based on coordinates

### Dashboard (V1): Story-Focused

**Replaces** the current photo-count dashboard. New sections:

- **Header**: "Your Travel Story — 21 countries since 2020"
- **Year selector**: tabs or cards for each year
- **Per-year view**:
  - Summary card: "In 2024, you took 8 trips across 12 countries. You spent 45 days traveling. New countries: Germany, Liechtenstein."
  - Trip cards in chronological order: destination, dates, duration, cities/stops, photo count
- **Map**: trips shown as routes/clusters (not individual photo dots), colored by year
- **All-time stats**: total trips, countries, longest trip, most-visited country, favorite month for travel

**Dropped** from current dashboard: photo-count bar charts, "Top Countries by Photo Count", "Top Cities by Photo Count".

### LLM Q&A (V2 — Future)

- Small Python HTTP server (Flask or similar)
- Chat input in the dashboard HTML
- System prompt = full `timeline.json` content
- OpenAI API (GPT-4o) for answers
- Example queries: "When did I visit Malta?", "How many days in Dalyan?", "Where was I on June 15 2024?", "What was my longest trip in 2023?"

## Phasing

### V1 (This implementation)
- City normalization in extract.py
- Trip detection engine (trips.py)
- Timeline JSON generation
- New story-focused HTML dashboard

### V2 (Future)
- OpenAI-powered chat interface
- Natural language narrative generation per trip/year
- Query answering from timeline.json context

## Data Quality Strategy

Ship V1, inspect timeline.json output, fix iteratively:
- NaN city names
- Border-bounce micro-trips
- Domestic trip classification accuracy
- City normalization edge cases
