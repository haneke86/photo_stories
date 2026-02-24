# Onboarding Flow Redesign — Design Document

**Date**: 2026-02-22
**Status**: Approved
**Branch**: feat/travel-timeline

## Problem

The current app flow has three issues:

1. **No onboarding** — first-time users see a login screen with no explanation of what the app does, what features it offers, or how their privacy is protected.
2. **Wrong order** — after authentication, the app immediately checks photo permission and starts processing. Users don't understand _why_ before granting access.
3. **Keychain persistence** — iOS Keychain survives app deletion. After delete+reinstall, stale Cognito tokens auto-authenticate the user, skipping both login and onboarding entirely.

## Goals

- First-time users see a multi-page walkthrough explaining features and privacy before any sign-in or permission prompt.
- Returning users (who completed onboarding) skip the carousel and go to sign-in or dashboard.
- Reinstalling the app correctly resets state and shows onboarding again.
- Privacy messaging is fully transparent and accurate.

## Non-Goals

- Apple Intelligence / on-device LLM integration (deferred to iOS 26+ era).
- Changes to the processing pipeline, dashboard, or tab structure.
- Terms of Service / Privacy Policy legal documents.

## Design

### App Launch State Machine

```
App Launch
    │
    ├─ Check UserDefaults("hasLaunchedBefore")
    │   ├─ false (fresh install or reinstall)
    │   │     └─► Clear Keychain tokens
    │   │         └─► Check UserDefaults("hasCompletedOnboarding")
    │   │               └─ always false after reinstall
    │   │                     └─► Onboarding Carousel
    │   │
    │   └─ true (not a reinstall)
    │         └─► Check UserDefaults("hasCompletedOnboarding")
    │               ├─ false ──► Onboarding Carousel
    │               └─ true ──► Check Keychain tokens
    │                             ├─ valid ──► Check photo permission
    │                             │             ├─ authorized ──► Load cached timeline or process
    │                             │             └─ not granted ──► Photo Permission screen
    │                             └─ missing/expired ──► Sign In screen (no carousel)
    │
    After Onboarding Carousel completes:
        Set hasLaunchedBefore = true
        Set hasCompletedOnboarding = true
        ──► Photo Permission screen
        ──► Processing → Dashboard
```

### Two UserDefaults Flags

| Key | Purpose | Survives app deletion? |
|-----|---------|----------------------|
| `hasLaunchedBefore` | Detect reinstalls — if missing but Keychain has tokens, clear them | No (UserDefaults is deleted) |
| `hasCompletedOnboarding` | Skip carousel for returning users who already saw it | No (UserDefaults is deleted) |

Both are cleared on app deletion (unlike Keychain), which is exactly what we want — reinstalling always resets to onboarding.

### Onboarding Carousel — 4 Pages

Swipeable `TabView` with `.tabViewStyle(.page)` and page indicator dots.

**Page 1 — "Your Travel Timeline"**
- SF Symbol: `globe.europe.africa` (gradient)
- Headline: "Your Travel Timeline"
- Body: "We read location data from your photos to auto-detect trips and build a beautiful travel timeline."
- Bullets:
  - `map.fill` — "Auto-detect trips from geotagged photos"
  - `mappin.and.ellipse` — "Identify cities and countries visited"
  - `chart.bar.fill` — "Year-by-year travel statistics"

**Page 2 — "AI-Powered Stories"**
- SF Symbol: `book.pages.fill` (gradient)
- Headline: "AI-Powered Trip Stories"
- Body: "Get rich narratives about your journeys and ask questions about your travel history."
- Bullets:
  - `text.book.closed.fill` — "Generated stories for each trip"
  - `bubble.left.and.text.bubble.right.fill` — "Chat with your travel history"
  - `globe.desk.fill` — "Interactive map of everywhere you've been"

**Page 3 — "Your Privacy Matters"**
- SF Symbol: `shield.lefthalf.filled` (gradient)
- Headline: "Your Privacy Matters"
- Body: "We take your privacy seriously."
- Privacy checkmarks (green checkmark icon for each):
  - "We only read location data — never your photo or video content"
  - "Trip detection uses location metadata from your photos"
  - "AI features send only city names and dates via encrypted connection"
  - "No personal information is stored on our servers"
- Footer (tertiary text): "Your photos and media content are never accessed or uploaded."

**Page 4 — "Get Started"**
- SF Symbol: `person.crop.circle.badge.checkmark` (gradient)
- Headline: "Let's Get Started"
- Body: "Sign in to unlock AI-powered stories and chat."
- CTA: Sign in with Apple button (same style as current LoginView)
- Below button: "By continuing, you agree to our Privacy Policy"

### Photo Permission Screen (Enhanced)

After sign-in succeeds, show the existing `PermissionView` with enhanced messaging:

- Keep existing feature bullets
- Add privacy line: "We only read the **where** and **when** of your photos — never the content itself."
- Keep "Allow Photo Access" button

### Returning User Flow (No Carousel)

Users who have `hasCompletedOnboarding = true` but are not authenticated (e.g., token expired, signed out) see a simplified sign-in screen — the current `LoginView` without the onboarding carousel. This avoids re-showing onboarding to users who already know the app.

### ContentView State Machine (New)

```swift
ContentView
├─ !hasCompletedOnboarding → OnboardingCarouselView(authVM:)
│   (carousel includes sign-in on page 4)
│   (on successful sign-in: set flags, move to permission)
├─ !isAuthenticated → LoginView(authVM:)
│   (simplified, for returning users only)
├─ pipeline.needsPermission → PermissionView
├─ pipeline.denied → PermissionDeniedView
├─ pipeline.processing → ProcessingView
├─ pipeline.ready → MainTabView
└─ pipeline.error → ErrorView
```

### Fresh Install Detection (AuthService)

```swift
// In AuthService.init():
let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
if !hasLaunchedBefore {
    clearKeychain()     // Wipe stale tokens from previous install
    isAuthenticated = false
    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
}
```

This runs once per install. On reinstall, `UserDefaults` is empty so `hasLaunchedBefore` is false, Keychain gets cleared, and the user sees onboarding.

## Components

| File | Action | Description |
|------|--------|-------------|
| `Views/Onboarding/OnboardingCarouselView.swift` | NEW | 4-page TabView with page dots, sign-in on page 4 |
| `Views/Onboarding/OnboardingPageView.swift` | NEW | Reusable page template (icon, headline, body, bullets) |
| `App/ContentView.swift` | MODIFY | New state machine: onboarding → auth → permission → pipeline |
| `Services/AuthService.swift` | MODIFY | Add fresh-install detection (clear Keychain if `hasLaunchedBefore` missing) |
| `Views/Pipeline/PermissionView.swift` | MODIFY | Add privacy messaging line |
| `Views/Auth/LoginView.swift` | MODIFY | Simplify for returning users (remove onboarding text, keep sign-in) |
| `project.yml` | MODIFY | Add new files to xcodegen sources |

## Privacy Messaging Summary

The messaging across the app follows this hierarchy:

1. **Onboarding page 3**: Full privacy breakdown with 4 checkmark points
2. **Permission screen**: "We only read the where and when — never the content"
3. **Login screen footer**: "Your photos and data stay on your device" (existing)

The key claims:
- We read **location metadata only** (latitude, longitude, date) — never photo/video content
- Trip detection uses this location metadata
- AI features (stories, chat) send **city names and travel dates** via encrypted connection
- No personal information is stored on servers
- Photos never leave the device

All claims are accurate for the current architecture and remain accurate if LLM-enhanced trip detection is added later (it would send the same metadata type).

## Future Considerations

- **Apple Foundation Models** (iOS 26+): When available, could enable on-device story generation for basic summaries, reducing API calls. Would require iOS 26 minimum target and A17 Pro+ hardware. Not blocking for this design.
- **Usage tracking UI**: Phase 5 of AWS deployment (not started). Could show remaining story/chat quota in settings.
- **Sign out + re-onboard**: Currently no settings screen with sign-out. Future work.
