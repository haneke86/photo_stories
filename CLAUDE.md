# MacPhoto — Project Instructions

## Roadmap
1. **V1 (done)**: Python macOS app — trip detection + travel timeline dashboard (HTML)
2. **V1.5 (done)**: OpenAI-powered Q&A chat over timeline.json
3. **V2 (in progress)**: iOS app — PhotoKit API + SwiftUI, same timeline.json format and trip detection logic
4. **Deferred**: Google Takeout extractor (manual ZIP+JSON parse)

## Architecture

### Python (macOS)
- Pipeline: `extract.py` → `trips.py` → `timeline.json` → `dashboard.py` → HTML
- Extractors package: `extractors/base.py` (Protocol), `extractors/apple_photos.py`, `extractors/normalize.py`
- `extract.py` is a thin backward-compatible wrapper over `extractors.apple_photos.ApplePhotosExtractor`
- `timeline.json` is the platform-agnostic core artifact

### iOS (SwiftUI + PhotoKit)
- Project: `MacPhotoTrips/` — Xcode project generated via `xcodegen` from `project.yml`
- Target: iOS 17+
- Pipeline: PhotoLibraryService → GeocodingService → TripDetector → TimelineBuilder → DashboardView
- Geocoding: CLGeocoder with 0.01° coordinate clustering + 1.3s rate limiting + SwiftData cache
- Algorithm ports: Haversine, HomeDetector, TripDetector, TimelineBuilder, CityNormalizer
- LLM: AnthropicDirectProvider (URLSession + SSE), StoryService with SHA256 file cache, ChatViewModel with history persistence
- API key: build-time env var (`export ANTHROPIC_API_KEY=... && xcodegen generate`)

## Conventions
- Output files: `output/YYYY-MM-DD-HHMM-<name>.html`
- Design doc: `docs/plans/2026-02-15-travel-timeline-design.md`
- iOS test photos: `MacPhotoTrips/test_photos/` (28 geotagged JPEGs, push with `xcrun simctl addmedia booted *.jpg`)
- Regenerate Xcode project: `cd MacPhotoTrips && xcodegen generate`
