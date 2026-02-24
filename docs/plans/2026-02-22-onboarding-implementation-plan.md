# Onboarding Flow Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current login-first flow with a 4-page onboarding carousel → sign-in → photo permission pipeline, with Keychain cleanup on reinstall and transparent privacy messaging.

**Architecture:** New `OnboardingCarouselView` (TabView with page style) wraps 4 pages including sign-in on page 4. `ContentView` gets a new state machine gating on `hasCompletedOnboarding` (UserDefaults). `AuthService.init()` detects fresh installs via `hasLaunchedBefore` UserDefaults flag and clears stale Keychain tokens.

**Tech Stack:** SwiftUI (iOS 17+), `TabView(.page)`, `UserDefaults`, Keychain (Security framework), existing `DesignTokens` + `AuroraBackground` design system.

**Design doc:** `docs/plans/2026-02-22-onboarding-redesign-design.md`

---

### Task 1: AuthService — Fresh Install Detection

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Services/AuthService.swift:29-31`

**Step 1: Add fresh-install detection to `init()`**

Replace the current `init()`:

```swift
// CURRENT (line 29-31):
init() {
    loadStoredTokens()
}
```

With:

```swift
init() {
    cleanupIfReinstall()
    loadStoredTokens()
}

/// Detect fresh install or reinstall by checking UserDefaults.
/// UserDefaults is cleared on app deletion, Keychain is not.
/// If UserDefaults flag is missing but Keychain has tokens → reinstall → clear tokens.
private func cleanupIfReinstall() {
    let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    if !hasLaunchedBefore {
        clearKeychain()
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
}
```

**Step 2: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Services/AuthService.swift
git commit -m "fix(auth): clear stale Keychain tokens on app reinstall"
```

---

### Task 2: OnboardingPageView — Reusable Page Template

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Views/Onboarding/OnboardingPageView.swift`

**Step 1: Create the directory and file**

```swift
import SwiftUI

/// Reusable onboarding page with icon, headline, body, and bullet points.
struct OnboardingPageView: View {
    let icon: String
    let headline: String
    let body: String
    let bullets: [(icon: String, text: String)]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(DesignTokens.gradient)

            VStack(spacing: 8) {
                Text(headline)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text(self.body)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(spacing: 12) {
                        Image(systemName: bullet.icon)
                            .foregroundStyle(DesignTokens.teal)
                            .frame(width: 24)
                        Text(bullet.text)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Onboarding/OnboardingPageView.swift
git commit -m "feat(onboarding): add reusable OnboardingPageView template"
```

---

### Task 3: OnboardingCarouselView — 4-Page Walkthrough with Sign-In

**Files:**
- Create: `MacPhotoTrips/MacPhotoTrips/Views/Onboarding/OnboardingCarouselView.swift`

**Step 1: Create the carousel view**

This is the main onboarding view. Pages 1-3 are informational, page 4 has the Sign In button. On successful sign-in, it sets `hasCompletedOnboarding` and the parent view transitions forward.

```swift
import SwiftUI

/// 4-page onboarding carousel: features → AI → privacy → sign-in.
struct OnboardingCarouselView: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    // Page 1: Travel Timeline
                    OnboardingPageView(
                        icon: "globe.europe.africa",
                        headline: "Your Travel Timeline",
                        body: "We read location data from your photos to auto-detect trips and build a beautiful travel timeline.",
                        bullets: [
                            ("map.fill", "Auto-detect trips from geotagged photos"),
                            ("mappin.and.ellipse", "Identify cities and countries visited"),
                            ("chart.bar.fill", "Year-by-year travel statistics"),
                        ]
                    )
                    .tag(0)

                    // Page 2: AI Stories
                    OnboardingPageView(
                        icon: "book.pages.fill",
                        headline: "AI-Powered Trip Stories",
                        body: "Get rich narratives about your journeys and ask questions about your travel history.",
                        bullets: [
                            ("text.book.closed.fill", "Generated stories for each trip"),
                            ("bubble.left.and.text.bubble.right.fill", "Chat with your travel history"),
                            ("globe.desk.fill", "Interactive map of everywhere you've been"),
                        ]
                    )
                    .tag(1)

                    // Page 3: Privacy
                    privacyPage
                        .tag(2)

                    // Page 4: Sign In
                    signInPage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Bottom navigation
                bottomBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Privacy Page (custom layout with checkmarks)

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 72))
                .foregroundStyle(DesignTokens.gradient)

            VStack(spacing: 8) {
                Text("Your Privacy Matters")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("We take your privacy seriously.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                PrivacyRow("We only read location data — never your photo or video content")
                PrivacyRow("Trip detection uses location metadata from your photos")
                PrivacyRow("AI features send only city names and dates via encrypted connection")
                PrivacyRow("No personal information is stored on our servers")
            }
            .padding(.horizontal, 32)

            Text("Your photos and media content are never accessed or uploaded.")
                .font(.caption)
                .foregroundStyle(DesignTokens.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Sign In Page

    private var signInPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 72))
                .foregroundStyle(DesignTokens.gradient)

            VStack(spacing: 8) {
                Text("Let's Get Started")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Sign in to unlock AI-powered stories and chat.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer()

            // Sign in with Apple button
            Button {
                Task {
                    await authVM.signIn()
                    if authVM.isAuthenticated {
                        hasCompletedOnboarding = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.title3)
                    Text("Sign in with Apple")
                        .font(.title3.weight(.medium))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 40)
            .disabled(authVM.isLoading)

            if authVM.isLoading {
                ProgressView()
                    .tint(DesignTokens.teal)
            }

            if let error = authVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text("By continuing, you agree to our Privacy Policy")
                .font(.caption)
                .foregroundStyle(DesignTokens.textTertiary)

            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if currentPage < 3 {
                Button("Skip") {
                    withAnimation { currentPage = 3 }
                }
                .foregroundStyle(DesignTokens.textSecondary)

                Spacer()

                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Next")
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignTokens.teal)
                }
            } else {
                Spacer()
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Privacy Row

private struct PrivacyRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Onboarding/OnboardingCarouselView.swift
git commit -m "feat(onboarding): add 4-page carousel with features, privacy, and sign-in"
```

---

### Task 4: ContentView — New State Machine

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/App/ContentView.swift:1-43`

**Step 1: Rewrite the ContentView root to gate on onboarding first**

Replace the current `ContentView` struct (lines 1-43) with:

```swift
import SwiftUI
import Photos

/// Root view: onboarding gate → auth gate → permission gate → processing → dashboard.
struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var pipeline = PipelineViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingCarouselView(
                    authVM: authVM,
                    hasCompletedOnboarding: $hasCompletedOnboarding
                )
            } else if !authVM.isAuthenticated {
                LoginView(authVM: authVM)
            } else {
                authenticatedContent
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        Group {
            switch pipeline.state {
            case .needsPermission:
                PermissionView(onRequest: pipeline.requestPermission)
            case .denied:
                PermissionDeniedView()
            case .processing:
                ProcessingView(viewModel: pipeline)
            case .ready:
                if let timeline = pipeline.timeline {
                    MainTabView(
                        timeline: timeline,
                        pipeline: pipeline,
                        authService: authVM.authService
                    )
                }
            case .error(let message):
                ErrorView(message: message, onRetry: pipeline.start)
            }
        }
        .task { pipeline.checkPermission() }
    }
}
```

Key change: `@AppStorage("hasCompletedOnboarding")` replaces the old simple `authVM.isAuthenticated` check as the first gate. `@AppStorage` reads/writes UserDefaults reactively.

The rest of the file (MainTabView, PermissionDeniedView, ErrorView) stays exactly the same.

**Step 2: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/App/ContentView.swift
git commit -m "feat(onboarding): rewrite ContentView state machine with onboarding gate"
```

---

### Task 5: PermissionView — Enhanced Privacy Messaging

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Pipeline/PermissionView.swift:50-51`

**Step 1: Replace the existing privacy line**

Replace the current single privacy line (line 50-51):

```swift
Text("Your photos never leave your device.")
    .font(.caption)
    .foregroundStyle(.tertiary)
```

With a more transparent two-line message:

```swift
VStack(spacing: 4) {
    Text("We only read the ")
        + Text("where").fontWeight(.semibold)
        + Text(" and ")
        + Text("when").fontWeight(.semibold)
        + Text(" of your photos — never the content.")
    Text("Your photos and media never leave your device.")
}
.font(.caption)
.multilineTextAlignment(.center)
.foregroundStyle(.tertiary)
.padding(.horizontal, 32)
```

**Step 2: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Pipeline/PermissionView.swift
git commit -m "feat(onboarding): enhance PermissionView privacy messaging"
```

---

### Task 6: LoginView — Simplify for Returning Users

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Auth/LoginView.swift`

**Step 1: Update the doc comment and tagline**

The `LoginView` is now only shown to returning users who have already completed onboarding but whose token has expired. The onboarding text is redundant here. Change:

Line 4: Change doc comment from `/// Sign in with Apple onboarding screen.` to `/// Sign-in screen for returning users (post-onboarding).`

Line 28: Change tagline from `"Your travel story, powered by AI"` to `"Welcome back"` — returning users don't need the pitch.

**Step 2: Build and verify**

Run: `cd MacPhotoTrips && xcodegen generate && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Auth/LoginView.swift
git commit -m "feat(onboarding): simplify LoginView for returning users"
```

---

### Task 7: Regenerate Xcode Project

**Files:**
- Modify: `MacPhotoTrips/project.yml` (no changes needed — `sources` already includes all of `MacPhotoTrips/` recursively)

**Step 1: Regenerate and verify new files are picked up**

Run: `cd MacPhotoTrips && xcodegen generate`

The `project.yml` uses `path: MacPhotoTrips` which recursively includes all `.swift` files. The new `Views/Onboarding/` directory will be picked up automatically. No yml changes needed.

**Step 2: Full build**

Run: `cd MacPhotoTrips && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit the regenerated project file**

```bash
git add MacPhotoTrips/MacPhotoTrips.xcodeproj/project.pbxproj
git commit -m "chore: regenerate Xcode project with onboarding views"
```

---

### Task 8: Manual Verification on Simulator

**Step 1: Clean simulator state to simulate fresh install**

Run: `xcrun simctl erase "iPhone 16"` (or delete and recreate the simulator). This clears both UserDefaults and Keychain for all apps on that simulator.

**Step 2: Build and run on simulator**

Run: `cd MacPhotoTrips && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build`

Then launch in simulator.

**Step 3: Verify the flow**

- [ ] App launches → 4-page onboarding carousel appears
- [ ] Page 1: travel timeline features with globe icon
- [ ] Page 2: AI stories features with book icon
- [ ] Page 3: privacy breakdown with green checkmarks
- [ ] Page 4: "Let's Get Started" with Sign In with Apple button
- [ ] Swipe navigation works, page dots update
- [ ] "Skip" button jumps to page 4, "Next" advances one page
- [ ] After sign-in → photo permission screen appears with enhanced privacy text
- [ ] After granting photo access → processing → dashboard
- [ ] Kill and relaunch app → goes straight to dashboard (skips onboarding and sign-in)
- [ ] Sign out (future) → shows simplified LoginView with "Welcome back"

**Step 4: Verify reinstall behavior**

- Delete the app from simulator
- Rebuild and launch
- [ ] Onboarding carousel appears again (Keychain was cleared by fresh-install detection)
- [ ] No auto-login from stale tokens

---

### Summary of Changes

| # | Task | Files | Type |
|---|------|-------|------|
| 1 | Fresh install detection | AuthService.swift | Modify |
| 2 | OnboardingPageView template | Views/Onboarding/OnboardingPageView.swift | Create |
| 3 | OnboardingCarouselView (4 pages) | Views/Onboarding/OnboardingCarouselView.swift | Create |
| 4 | ContentView state machine | App/ContentView.swift | Modify |
| 5 | PermissionView privacy text | Views/Pipeline/PermissionView.swift | Modify |
| 6 | LoginView simplification | Views/Auth/LoginView.swift | Modify |
| 7 | Regenerate Xcode project | project.pbxproj | Auto |
| 8 | Manual verification | — | Test |
