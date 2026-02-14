# MacPhoto — Project Instructions

## Roadmap
1. **V1 (current)**: Python macOS app — trip detection + travel timeline dashboard (HTML)
2. **V1.5**: OpenAI-powered Q&A chat over timeline.json
3. **V2**: iOS app version — PhotoKit API + SwiftUI, same timeline.json format and trip detection logic

## Architecture
- Pipeline: `extract.py` → `trips.py` → `timeline.json` → `dashboard.py` → HTML
- `timeline.json` is the platform-agnostic core artifact — must stay clean and well-documented
- Design doc: `docs/plans/2026-02-15-travel-timeline-design.md`

## Conventions
- Output files: `output/YYYY-MM-DD-HHMM-<name>.html`
- Keep iOS portability in mind: trip detection logic should be algorithm-clear (easy to rewrite in Swift)
