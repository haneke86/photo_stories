# Explore Tab + Incremental Refresh — Design Document

**Date**: 2026-02-23
**Status**: Approved
**Branch**: feat/travel-timeline
**Depends on**: Settings screen (uncommitted), 5-tab restructure (done)

## Problem

The app has 6 tabs (Trips, Stories, Map, Stats, Chat, Settings) — too many for comfortable thumb navigation. The Trips and Map tabs show the same underlying data (trips/stops) in different layouts. Meanwhile, the only way to refresh the photo library is a full pipeline re-run that nukes all caches.

## Goals

- Merge Trips + Map into a single "Explore" tab with a list/map toggle
- Reduce from 6 tabs to 5 with renames (Explore, Stories, Insights, Chat, Settings)
- Add incremental photo refresh via pull-to-refresh on Explore (delta scan, not full re-run)
- Add pull-to-refresh on Stories to generate new stories (old ones pushed down)

## Non-Goals

- Changing the Settings tab (stays as-is from the settings design)
- Modifying the map or trip list UIs themselves (reused as-is)
- Background auto-refresh or PHPhotoLibraryChangeObserver (future)
- Subscription / IAP changes

## Design

### Feature 1: Explore Tab (Trips + Map Merge)

Single tab with a toolbar toggle button switching between full trip list and full-screen map.

#### List Mode (default)

Reuses `TripsTabView` body as-is:
- Scrollable trip rows grouped by year
- Tap row → `TripDetailView` sheet
- Share button in toolbar trailing
- Map toggle icon (`map`) in toolbar trailing, left of share

#### Map Mode

Reuses `MapTabView` body as-is:
- Full-screen satellite map with tappable stop annotations
- Floating stats pill (stops count, countries count)
- Tap dot → `TripDetailView` sheet
- List toggle icon (`list.bullet`) in toolbar to switch back

#### Toggle Behavior

- `@State private var showMap = false`
- Animated transition: `.transition(.opacity)` with `.animation(.easeInOut(duration: 0.25))`
- Navigation title: "Explore" in both modes

### Feature 2: Pull-to-Refresh on Explore (Incremental Photo Refresh)

`.refreshable` on the trip list that only scans photos added since the last pipeline run.

#### Data Flow

```
User pulls down on trip list
  → ExploreTabView .refreshable
  → PipelineViewModel.incrementalRefresh()
  → PhotoLibraryService.fetchGeotaggedPhotos(since: lastFetchDate)
  → Only new photos returned (PHFetchOptions predicate)
  → Geocode new photos (cache hits for known coords)
  → Merge with existing photoRecords
  → TimelineBuilder.build(from: mergedRecords)
  → If changed: pipeline.timeline = newTimeline
  → MainTabView .onReceive → dashboardVM.updateTimeline()
  → UI refreshes, existing narratives preserved
```

#### Key Details

- `lastFetchDate` persisted to UserDefaults (key: `lastPhotoFetchDate`)
- Set to `Date()` at the start of each pipeline run (both `start()` and `incrementalRefresh()`)
- If no new photos found, refresh completes silently (no error)
- Existing `refresh()` (full nuke) stays as fallback, accessible from Settings or long-press
- Narratives: unchanged trips keep their stories; trips with new stops/cities lose cached narrative (can regenerate)

### Feature 3: Pull-to-Refresh on Stories

`.refreshable` on the Stories feed that generates new story cards and prepends them above existing ones.

#### Behavior

1. Pull-down on `StoryFeedView` feed state (`.partial` or `.ready`)
2. Calls `feedVM.regenerate(timeline:)`
3. Generates new batch of story cards from current timeline
4. New cards prepended above existing cards in the feed
5. Old cards stay — user scrolls down to see previous generations
6. Idle state also gets `.refreshable` for consistency

### Feature 4: Tab Bar Changes

| Position | Old Name | New Name | Icon | Change |
|----------|----------|----------|------|--------|
| 1 | Trips + Map (2 tabs) | **Explore** | `globe.europe.africa` | Merged |
| 2 | Stories | **Stories** | `book.pages` | Unchanged |
| 3 | Stats | **Insights** | `chart.bar.xaxis` | Renamed |
| 4 | Chat | **Chat** | `bubble.left.and.text.bubble.right` | Unchanged |
| 5 | Settings | **Settings** | `gearshape` | Unchanged |

## Components

### iOS (New/Modified)

| File | Action | Description |
|------|--------|-------------|
| `Views/Explore/ExploreTabView.swift` | NEW | Wrapper with list/map toggle, pull-to-refresh |
| `App/ContentView.swift` | MODIFY | Replace Trips+Map tabs with Explore, rename Stats→Insights |
| `ViewModels/PipelineViewModel.swift` | MODIFY | Add `lastFetchDate`, `incrementalRefresh()` |
| `Services/PhotoLibraryService.swift` | MODIFY | Add `fetchGeotaggedPhotos(since:)` |
| `Views/Stories/StoryFeedView.swift` | MODIFY | Add `.refreshable` on feed + idle states |
| `ViewModels/StoryFeedViewModel.swift` | MODIFY | Add `regenerate(timeline:)` method |

### Files Kept (reused inside ExploreTabView)

| File | Status |
|------|--------|
| `Views/Trips/TripsTabView.swift` | Reused as list mode content |
| `Views/Trips/TripRowView.swift` | Unchanged |
| `Views/Map/MapTabView.swift` | Reused as map mode content |
| `Views/Map/InteractiveTripMapView.swift` | Unchanged |

## Future Considerations

- `PHPhotoLibraryChangeObserver` for automatic detection of new photos (no pull needed)
- Map clustering for users with many trips in the same region
- Search/filter on the Explore trip list
- "Year in Review" feature on the Insights tab
