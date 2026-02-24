# Explore Tab + Incremental Refresh — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Merge Trips+Map into a single Explore tab with list/map toggle, add pull-to-refresh for incremental photo scanning, and add pull-to-refresh on Stories for regeneration.

**Architecture:** ExploreTabView wraps existing TripsTabView and MapTabView with a `@State showMap` toggle. PipelineViewModel gains `incrementalRefresh()` that delta-scans PhotoKit. StoryFeedViewModel gains `regenerate()` that prepends new cards.

**Tech Stack:** SwiftUI, PhotoKit (PHFetchOptions date predicate), existing DashboardViewModel/PipelineViewModel

**Design doc:** `docs/plans/2026-02-23-explore-tab-incremental-refresh-design.md`

---

### Task 1: Create ExploreTabView with list/map toggle

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Views/Explore/ExploreTabView.swift`

**Step 1: Create the ExploreTabView**

```swift
import SwiftUI

/// Combined Trips + Map tab with toolbar toggle between list and map modes.
struct ExploreTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var pipeline: PipelineViewModel
    @State private var showMap = false
    @State private var selectedTrip: Trip?
    @State private var showShareSheet = false

    var body: some View {
        Group {
            if showMap {
                mapMode
            } else {
                listMode
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showMap)
        .navigationTitle("Explore")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showMap.toggle()
                    } label: {
                        Image(systemName: showMap ? "list.bullet" : "map")
                    }

                    if !showMap {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip, viewModel: viewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = TimelineStore.shareURL() {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - List Mode

    private var listMode: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Trips")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("\(viewModel.totalTrips) trips, \(viewModel.countriesCount) countries")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 24)

                // Trip rows by year
                ForEach(viewModel.yearGroups) { group in
                    HStack(spacing: 8) {
                        Text(verbatim: "\(group.year)")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("\(group.trips.count) trips")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textTertiary)

                        VStack { Divider().overlay(DesignTokens.glassBorder) }
                    }
                    .padding(.vertical, 8)

                    VStack(spacing: 8) {
                        ForEach(group.trips) { trip in
                            Button {
                                selectedTrip = trip
                            } label: {
                                TripRowView(trip: trip, viewModel: viewModel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable {
            await pipeline.incrementalRefresh()
        }
    }

    // MARK: - Map Mode

    private var mapMode: some View {
        ZStack(alignment: .top) {
            InteractiveTripMapView(
                annotations: viewModel.allStopAnnotations
            ) { annotation in
                if let trip = viewModel.trip(byId: annotation.tripId) {
                    selectedTrip = trip
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // Floating stats pill
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.teal)

                Text("\(viewModel.allStopAnnotations.count) stops")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)

                Text("·")
                    .foregroundStyle(DesignTokens.textTertiary)

                Text("\(viewModel.countriesCount) countries")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.3))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DesignTokens.glassBorder, lineWidth: 1))
            .padding(.top, 8)
        }
    }
}
```

**Step 2: Verify the file compiles in context**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -project MacPhotoTrips.xcodeproj -scheme MacPhotoTrips -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: Build may fail because `incrementalRefresh()` doesn't exist yet on PipelineViewModel. That's fine — we'll add it in Task 3. The view structure is correct.

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Explore/ExploreTabView.swift
git commit -m "feat(explore): add ExploreTabView with list/map toggle"
```

---

### Task 2: Wire ExploreTabView into MainTabView, rename tabs

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/App/ContentView.swift:51-127`

**Step 1: Replace Trips + Map tabs with Explore, rename Stats → Insights**

In `ContentView.swift`, replace the MainTabView `body` (lines 74-126) with:

```swift
    var body: some View {
        TabView {
            NavigationStack {
                ExploreTabView(viewModel: dashboardVM, pipeline: pipeline)
            }
            .tabItem {
                Label("Explore", systemImage: "globe.europe.africa")
            }

            StoryFeedView(feedVM: feedVM, dashboardVM: dashboardVM)
                .tabItem {
                    Label("Stories", systemImage: "book.pages")
                }

            NavigationStack {
                StatsTabView(viewModel: dashboardVM)
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                ChatView(viewModel: chatVM)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
            }

            NavigationStack {
                SettingsView(authVM: authVM, settingsVM: settingsVM)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(DesignTokens.teal)
        .onReceive(pipeline.$timeline) { newTimeline in
            guard let newTimeline else { return }
            let oldTrips = dashboardVM.timeline.trips
            let newTrips = newTimeline.trips
            let changed = oldTrips.count != newTrips.count
                || oldTrips.map(\.id) != newTrips.map(\.id)
                || oldTrips.map(\.cities) != newTrips.map(\.cities)
            guard changed else { return }
            dashboardVM.updateTimeline(newTimeline)
        }
    }
```

Also update the doc comment on line 51 from "6 tabs" to "5 tabs: Explore, Stories, Insights, Chat, Settings."

**Step 2: Update project.yml and regenerate**

Add `Views/Explore/` to sources if not already picked up by glob. Regenerate:

Run: `cd MacPhotoTrips && xcodegen generate`

**Step 3: Build to verify**

Run: `cd MacPhotoTrips && xcodebuild -project MacPhotoTrips.xcodeproj -scheme MacPhotoTrips -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: May fail on `incrementalRefresh()` — that's Task 3. Tab wiring itself should be correct.

**Step 4: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/App/ContentView.swift MacPhotoTrips/project.yml
git commit -m "feat(explore): wire ExploreTabView, merge Trips+Map, rename tabs"
```

---

### Task 3: Add incremental photo refresh to PhotoLibraryService

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Services/PhotoLibraryService.swift:20-58`

**Step 1: Add `fetchGeotaggedPhotos(since:)` method**

Add this method after the existing `fetchGeotaggedPhotos(yearsBack:)` (after line 58):

```swift
    /// Fetch only geotagged photos created after the given date.
    /// Returns an empty array if no new photos exist.
    func fetchGeotaggedPhotos(since date: Date) -> [PhotoRecord] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var records: [PhotoRecord] = []
        records.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            guard let location = asset.location,
                  let date = asset.creationDate else { return }

            let coord = location.coordinate
            guard coord.latitude != -180.0, coord.longitude != -180.0 else { return }

            let record = PhotoRecord(
                id: asset.localIdentifier,
                latitude: coord.latitude,
                longitude: coord.longitude,
                date: date,
                filename: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "photo_\(asset.localIdentifier)",
                country: "",
                city: "",
                district: "",
                state: ""
            )
            records.append(record)
        }

        return records
    }
```

**Step 2: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Services/PhotoLibraryService.swift
git commit -m "feat(photos): add fetchGeotaggedPhotos(since:) for delta scanning"
```

---

### Task 4: Add `incrementalRefresh()` to PipelineViewModel

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/ViewModels/PipelineViewModel.swift`

**Step 1: Add `lastFetchDate` property and persistence**

Add after line 37 (`private var photoRecords: [PhotoRecord] = []`):

```swift
    /// Timestamp of the last successful photo fetch, for incremental refresh.
    private static let lastFetchDateKey = "lastPhotoFetchDate"

    private var lastFetchDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastFetchDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastFetchDateKey) }
    }
```

**Step 2: Store fetch timestamp in `start()`**

In the `start()` method, add `self.lastFetchDate = Date()` right before `// Step 1: Fetch photos` (after line 83 `Task {`):

```swift
        Task {
            do {
                let fetchStart = Date()

                // Step 1: Fetch photos
                currentStep = .fetching
                ...
```

And after the timeline is saved and state is `.ready` (after line 134 `timeline = result`), add:

```swift
                self.lastFetchDate = fetchStart
```

**Step 3: Add `incrementalRefresh()` method**

Add after the `refresh()` method (after line 184):

```swift
    /// Scan only photos added since the last fetch and merge into existing timeline.
    /// Called by pull-to-refresh on the Explore tab.
    func incrementalRefresh() async {
        guard let since = lastFetchDate else {
            // No previous fetch date — fall back to full refresh
            start()
            return
        }

        let fetchStart = Date()
        let newRecords = await photoService.fetchGeotaggedPhotos(since: since)

        guard !newRecords.isEmpty else {
            // No new photos — nothing to do
            return
        }

        // Initialize cache if needed
        if cache == nil, let container = try? ModelContainer(for: CachedGeocode.self) {
            cache = PhotoCacheStore(modelContainer: container)
        }

        // Geocode new photos only
        let geocoded = await geocodingService.geocodePhotos(
            newRecords, cache: cache,
            resolution: GeocodingService.fineResolution
        ) { _, _ in }

        let usableNew = geocoded.filter { $0.city != "Unknown" && !$0.city.isEmpty }
        guard !usableNew.isEmpty else {
            self.lastFetchDate = fetchStart
            return
        }

        // Merge with existing records
        let existingIds = Set(photoRecords.map(\.id))
        let deduped = usableNew.filter { !existingIds.contains($0.id) }
        photoRecords.append(contentsOf: deduped)

        // Re-geocode all existing records too (cache will serve them instantly)
        let allGeocoded = await geocodingService.geocodePhotos(
            photoRecords, cache: cache,
            resolution: GeocodingService.fineResolution
        ) { _, _ in }

        let allUsable = allGeocoded.filter { $0.city != "Unknown" && !$0.city.isEmpty }
        guard !allUsable.isEmpty else { return }

        // Rebuild timeline
        let result = TimelineBuilder.build(from: allUsable)
        try? TimelineStore.save(result)

        timeline = result
        self.lastFetchDate = fetchStart
    }
```

**Step 4: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -project MacPhotoTrips.xcodeproj -scheme MacPhotoTrips -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (all references now resolved)

**Step 5: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/ViewModels/PipelineViewModel.swift
git commit -m "feat(pipeline): add incrementalRefresh with delta photo scanning"
```

---

### Task 5: Add pull-to-refresh on Stories feed

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/ViewModels/StoryFeedViewModel.swift:63-103`
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Stories/StoryFeedView.swift:140-155`

**Step 1: Add `regenerate()` to StoryFeedViewModel**

Add after the `generate()` method (after line 103):

```swift
    /// Generate new stories and prepend them above existing cards.
    /// Called by pull-to-refresh on the Stories tab.
    func regenerate(timeline: Timeline) async {
        guard !isGenerating, !isAtStoryLimit else { return }

        isGenerating = true

        let activeProvider: LLMProvider? = self.provider ?? AnthropicDirectProvider()
        guard let provider = activeProvider, provider.isAvailable else {
            isGenerating = false
            return
        }

        state = .partial
        generationProgress = "Crafting new stories..."

        let generator = StoryGenerator(provider: provider, catalog: catalog)
        self.generator = generator

        let existingIds = Set(cards.map(\.id))
        var newCards: [StoryCard] = []

        await generator.start(timeline: timeline) { [weak self] card in
            guard let self else { return }
            if !existingIds.contains(card.id) && !newCards.contains(where: { $0.id == card.id }) {
                newCards.append(card)
                // Prepend new cards above existing
                self.cards = self.sortCards(newCards) + self.cards.filter { !newCards.contains(where: { n in n.id == $0.id }) }
            }
        }

        state = .ready
        isGenerating = false
        generationProgress = ""
        await refreshUsage()
    }
```

**Step 2: Add `.refreshable` to StoryFeedView feed state**

In `StoryFeedView.swift`, modify the `feedState` computed property (lines 140-155). Add `.refreshable` to the ScrollView:

```swift
    private var feedState: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(feedVM.cards) { card in
                    FullScreenStoryCard(card: card)
                        .containerRelativeFrame(.vertical)
                }

                endCard
                    .containerRelativeFrame(.vertical)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .refreshable {
            await feedVM.regenerate(timeline: dashboardVM.timeline)
        }
    }
```

Also add `.refreshable` to the `idleState` view. Wrap the existing ZStack content at the end (around line 95, just before closing brace of `idleState`):

Add `.refreshable` modifier to the outermost ZStack of idleState:

```swift
    private var idleState: some View {
        ZStack {
            // ... existing content unchanged ...
        }
        .refreshable {
            await feedVM.regenerate(timeline: dashboardVM.timeline)
        }
    }
```

**Step 3: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -project MacPhotoTrips.xcodeproj -scheme MacPhotoTrips -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/ViewModels/StoryFeedViewModel.swift MacPhotoTrips/MacPhotoTrips/Views/Stories/StoryFeedView.swift
git commit -m "feat(stories): add pull-to-refresh for story regeneration"
```

---

### Task 6: Final build + cleanup

**Step 1: Full build verification**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -project MacPhotoTrips.xcodeproj -scheme MacPhotoTrips -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 2: Verify tab count is 5**

Grep for `.tabItem` in ContentView.swift and confirm exactly 5 occurrences:

Run: `grep -c '.tabItem' MacPhotoTrips/MacPhotoTrips/App/ContentView.swift`

Expected: `5`

**Step 3: Verify no orphan references to old tab names**

Run: `grep -rn '"Trips"' MacPhotoTrips/MacPhotoTrips/App/ContentView.swift`
Expected: no matches (replaced with "Explore")

Run: `grep -rn '"Stats"' MacPhotoTrips/MacPhotoTrips/App/ContentView.swift`
Expected: no matches (replaced with "Insights")

Run: `grep -rn '"Map"' MacPhotoTrips/MacPhotoTrips/App/ContentView.swift`
Expected: no matches (Map tab removed)

**Step 4: Commit plan alongside code**

```bash
git add docs/plans/2026-02-23-explore-tab-incremental-refresh-plan.md
git commit -m "docs: add explore tab implementation plan"
```
