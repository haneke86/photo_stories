# LLM Integration — Design Document

**Date:** 2026-02-17
**Status:** Implemented

## Overview

This document describes the integration of Claude (Anthropic API) into the MacPhoto travel timeline pipeline. Three LLM-powered features were added:

1. **Location enrichment** — Fix city names that static rules get wrong
2. **Trip narratives** — Generate stories and taglines for each trip and year
3. **Interactive chat** — CLI Q&A over the travel timeline

## Architecture

### Updated Pipeline

```
Photos.sqlite → extract.py → raw DataFrame
                                  ↓
                            llm_enrich.py (Claude: fix suspicious city names)
                                  ↓
                            enriched DataFrame
                                  ↓
                            trips.py → timeline.json
                                  ↓
                            llm_stories.py (Claude: narratives + taglines)
                                  ↓
                            enriched timeline.json → dashboard.py → HTML
                                                  → chat.py (CLI Q&A)
```

### New Modules

| Module | Purpose | Claude API Pattern |
|--------|---------|-------------------|
| `llm_client.py` | Shared client, caching, config | Client init, cache helpers |
| `llm_enrich.py` | Pre-trip data enrichment | `messages.parse()` + Pydantic |
| `llm_stories.py` | Post-trip narrative generation | `messages.parse()` + Pydantic |
| `chat.py` | CLI Q&A over timeline | `messages.stream()` multi-turn |
| `server.py` | Local HTTP server with chat widget | Flask + SSE streaming |

### Modified Modules

| Module | Changes |
|--------|---------|
| `main.py` | Added `--no-llm`, `--no-stories` flags; enrichment + stories steps |
| `dashboard.py` | Pass narrative/tagline through stamps; year narratives |
| `templates/dashboard.html` | Display taglines on stamps, narratives in details, year narratives, embedded chat widget |

## Key Design Decisions

### 1. Structured Output via Pydantic

We use `client.messages.parse(output_format=PydanticModel)` for both enrichment and stories. This ensures:
- Type-safe responses that match our expected schema
- Automatic validation — if Claude returns malformed data, Pydantic catches it
- Clear contract between prompt engineering and code consumption

### 2. File-Based Response Cache

Responses are cached in `.llm_cache/{task}/{sha256}.json`:
- **Key:** SHA256(input_data + prompt_version)
- **Invalidation:** Changing the prompt_version constant forces re-generation
- **Benefit:** Re-running the pipeline with unchanged data costs $0.00
- **Location:** `.llm_cache/` is gitignored

### 3. Graceful Degradation

The pipeline works perfectly without an API key:
- `--no-llm` flag: Skips all LLM features, uses static rules only
- Missing `ANTHROPIC_API_KEY`: Caught as `EnvironmentError`, pipeline continues
- LLM errors: Caught as generic `Exception`, pipeline continues with static data

### 4. Location Grouping for Enrichment

Instead of sending 5,000+ individual photos to Claude:
1. Group by (date, lat_rounded, lon_rounded) → ~300 groups
2. Filter to groups with suspicious city names → ~15-50 candidates
3. Send only candidates in batches of 100

This keeps costs under $0.10 for enrichment.

### 5. Streaming for Chat

Chat uses `client.messages.stream()` for real-time text output. History is trimmed to the last 10 messages when it exceeds 20 to avoid token limits while maintaining conversation coherence.

## Cost Estimates

| Feature | Input Tokens | Output Tokens | Cost (Sonnet) |
|---------|-------------|---------------|---------------|
| Enrichment | ~3-5K | ~2-4K | ~$0.03-0.05 |
| Narratives | ~15-20K | ~5-8K | ~$0.08-0.12 |
| Chat (10 turns) | ~20K | ~5K | ~$0.10-0.15 |
| **First run total** | **~40K** | **~15K** | **~$0.15-0.25** |
| **Cached re-run** | **0** | **0** | **$0.00** |

## Data Flow Details

### Enrichment Flow

```
DataFrame (5,000 photos)
  → _build_location_groups() → ~300 groups
  → _identify_enrichment_candidates() → ~15-50 suspicious groups
  → _call_claude_enrich() → EnrichmentResult (Pydantic)
  → _apply_corrections() → corrected DataFrame (confidence >= 0.5)
```

**Suspicious patterns detected:**
- Region names: "Home Counties", "South Aegean", "Central Macedonia"
- Admin divisions: "Ammochostos", "Famagusta"
- Generic labels containing "Region", "Province", "District"

### Narrative Flow

```
timeline.json
  → _build_compact_timeline() → stripped of coords/photo_counts
  → _call_claude_stories() → NarrativeResult (Pydantic)
  → _merge_narratives() → timeline with narrative/tagline fields
```

**Fields added:**
- `trip.narrative` — 1-3 sentence trip description
- `trip.tagline` — 5-8 word evocative summary
- `year.narrative` — 2-4 sentence year summary

### Chat Flow

```
timeline.json → system prompt context
user input → messages list → client.messages.stream()
  → streamed response → displayed in real-time
  → appended to messages for multi-turn context
```

### Embedded Chat Widget Flow

```
python server.py → Flask (localhost:5001)
  ├── GET /              → serves latest travel-story HTML (with chat widget)
  ├── GET /api/timeline  → returns timeline.json (for widget initialization)
  └── POST /api/chat     → proxies to Claude API, streams response as SSE

Dashboard HTML (chat widget JS):
  ├── On load: fetch('/api/timeline') → detect server, show welcome stats
  ├── On send: POST /api/chat with {message, history}
  └── Streaming: fetch ReadableStream reads SSE chunks, renders incrementally
```

The chat widget is embedded in `templates/dashboard.html` and works in two modes:
- **Server mode** (`http://localhost`): Full chat functionality with streaming Claude responses
- **Static mode** (`file://`): Widget shows "Run python server.py" hint, dashboard is fully functional otherwise

## CLI Usage

```bash
# Full pipeline with LLM
python main.py --no-open

# Without LLM features (static rules only)
python main.py --no-open --no-llm

# With enrichment but no narratives
python main.py --no-open --no-stories

# Interactive chat (CLI)
python chat.py
python chat.py --timeline output/2026-02-16-2002-timeline.json

# Dashboard with embedded chat (browser)
python server.py
python server.py --port 8080 --no-open
python server.py --timeline output/2026-02-16-2002-timeline.json
```
