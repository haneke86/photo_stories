# Auth Flow Bugfix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three interrelated auth bugs that prevent real authentication on device — DEBUG bypass, missing URL scheme, and no sign-in path from Stories tab.

**Architecture:** Remove the `#if DEBUG` auth bypass, register `macphoto://` URL scheme in Info.plist + project.yml so ASWebAuthenticationSession callbacks work, and add a sign-in action on the Stories idle state so users who skipped onboarding sign-in have a path to authenticate.

**Tech Stack:** SwiftUI, ASWebAuthenticationSession, Cognito OAuth2, xcodegen

---

### Task 1: Remove #if DEBUG auth bypass from AuthViewModel

The `#if DEBUG` block makes `isAuthenticated` always return `true` in debug builds, which means the app skips login entirely but no Cognito token is obtained — causing all backend calls to fail.

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/ViewModels/AuthViewModel.swift:23-27`

**Step 1: Remove the DEBUG bypass**

Replace lines 23-27 with the original single property:

```swift
    var isAuthenticated: Bool { authService.isAuthenticated }
```

This removes the `#if DEBUG` / `#else` / `#endif` wrapper entirely.

**Step 2: Verify the file compiles**

Run: `cd MacPhotoTrips && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/ViewModels/AuthViewModel.swift
git commit -m "fix(auth): remove #if DEBUG bypass that prevented real authentication"
```

---

### Task 2: Register `macphoto://` URL scheme in Info.plist and project.yml

`AuthService` uses `macphoto://auth/callback` as the OAuth redirect URI, and Cognito has it registered (`infra/lib/macphoto-stack.ts:68`), but **iOS doesn't know the app handles this scheme**. Without `CFBundleURLTypes` in Info.plist, `ASWebAuthenticationSession` cannot receive the callback.

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Info.plist`
- Modify: `MacPhotoTrips/project.yml`

**Step 1: Add CFBundleURLTypes to Info.plist**

Add the following before the closing `</dict>` tag in Info.plist:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>macphoto</string>
			</array>
			<key>CFBundleURLName</key>
			<string>com.macphoto.trips</string>
		</dict>
	</array>
```

**Step 2: Add URL scheme to project.yml**

Add `urlSchemes` under the `MacPhotoTrips` target settings so `xcodegen generate` produces the correct pbxproj if regenerated:

```yaml
targets:
  MacPhotoTrips:
    type: application
    platform: iOS
    sources:
      - path: MacPhotoTrips
        excludes:
          - Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macphoto.trips
        INFOPLIST_FILE: MacPhotoTrips/Info.plist
    entitlements:
      path: MacPhotoTrips/MacPhotoTrips.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.personal-information.photos-library: true
        com.apple.developer.applesignin:
          - Default
```

Note: xcodegen handles URL schemes via the Info.plist directly (since we use a manual Info.plist via `INFOPLIST_FILE`), so no additional project.yml change is needed for the URL scheme itself. The manual Info.plist is the source of truth.

**Step 3: Verify build**

Run: `cd MacPhotoTrips && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Info.plist
git commit -m "fix(auth): register macphoto:// URL scheme for OAuth callback"
```

---

### Task 3: Add sign-in action on Stories idle state

When `BackendProvider.isAvailable` is `false`, the Stories tab shows "Sign in to generate AI-powered stories" but there's no button to actually sign in. The "Generate Stories" button is disabled. Users are stuck.

**Files:**
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Stories/StoryFeedView.swift:55-61`
- Modify: `MacPhotoTrips/MacPhotoTrips/Views/Stories/StoryFeedView.swift` (init / struct)

**Step 1: Pass authVM to StoryFeedView**

Add `authVM` as a parameter to `StoryFeedView`:

```swift
struct StoryFeedView: View {
    @ObservedObject var feedVM: StoryFeedViewModel
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var authVM: AuthViewModel
```

**Step 2: Replace the static "Sign in" text with a button**

Replace lines 55-61 (the `if !feedVM.isAvailable` block) with a sign-in button:

```swift
                if !feedVM.isAvailable {
                    Button {
                        Task { await authVM.signIn() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.body)
                            Text("Sign in to generate stories")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(DesignTokens.teal.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DesignTokens.teal.opacity(0.5), lineWidth: 1))
                    }
                    .disabled(authVM.isLoading)
                }
```

**Step 3: Update the call site in ContentView's MainTabView**

In `ContentView.swift`, update the `StoryFeedView` init to pass `authVM`:

```swift
            StoryFeedView(feedVM: feedVM, dashboardVM: dashboardVM, authVM: authVM)
```

**Step 4: Verify build**

Run: `cd MacPhotoTrips && xcodebuild -scheme MacPhotoTrips -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add MacPhotoTrips/MacPhotoTrips/Views/Stories/StoryFeedView.swift MacPhotoTrips/MacPhotoTrips/App/ContentView.swift
git commit -m "fix(stories): add sign-in button when backend is unavailable"
```

---

### Task 4: Verify full auth flow on device

**Manual test checklist:**

1. Delete app from device (clears UserDefaults, Keychain cleanup kicks in on reinstall)
2. Build and run on device
3. Verify onboarding carousel appears
4. Navigate to Page 4, tap "Sign in with Apple"
5. Verify Cognito hosted UI opens, Apple sign-in sheet appears
6. Complete sign-in
7. Verify callback returns to app (`[Auth] Callback received:` in console)
8. Verify app transitions to pipeline/dashboard
9. Go to Stories tab → verify "Generate Stories" button is enabled (not showing sign-in prompt)
10. Go to Settings tab → verify "Sign Out" works and returns to LoginView
11. Tap "Sign in with Apple" on LoginView → verify re-authentication works

**Console logs to watch for:**
- `[Auth] Opening auth session: https://macphoto-auth...`
- `[Auth] Callback received: macphoto://auth/callback?code=...`
- No `[Auth] Sign-in error:` messages

If auth fails, check:
- Xcode console for `[Auth]` prefixed logs
- Cognito hosted UI error page (usually `error=` in callback URL)
- Ensure device has internet access and Apple ID signed in
