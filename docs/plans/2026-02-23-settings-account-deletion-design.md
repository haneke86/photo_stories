# Settings Screen + Account Deletion — Design Document

**Date**: 2026-02-23
**Status**: Approved
**Branch**: feat/travel-timeline
**Depends on**: Onboarding redesign (done), AWS backend (deployed)

## Problem

The app has no settings screen. Apple requires account deletion UI for apps with sign-in (policy since 2022). There's also no way to sign out, clear caches, or see app version.

## Goals

- Settings tab with sign-out, account deletion, cache management, and app info
- Account deletion that complies with Apple's App Store requirements
- Soft-delete with 30-day cooldown to prevent quota-reset abuse
- Clean separation: server-side deletion is mandatory, local data wipe is optional

## Non-Goals

- Trips+Map tab merge (separate task, frees up tab space)
- Incremental photo refresh / pull-to-refresh on Trips tab (separate task)
- Subscription / IAP for usage quota
- Privacy Policy page content (just link to URL for now)

## Design

### Settings Screen Layout

Added as a new tab (gear icon) in MainTabView.

```
ACCOUNT
  Sign Out                    >
  Delete Account              >

DATA
  Clear Story Cache           >
  Clear Chat History          >

ABOUT
  Version              1.0 (1)
  Privacy Policy              >
```

Uses native `List` with `Form` style on dark background (matching app design).

### Sign Out Flow

1. User taps "Sign Out"
2. Confirmation alert: "Are you sure you want to sign out?"
3. On confirm: `AuthService.signOut()` → clears Keychain tokens → `isAuthenticated = false`
4. ContentView shows LoginView ("Welcome back")
5. Local data (timeline, stories, chat) stays intact

### Account Deletion Flow (Soft-Delete with 30-Day Cooldown)

#### User-Facing Flow

1. User taps "Delete Account"
2. Alert: "Delete Account? Your account will be scheduled for deletion. Server data will be permanently removed within 30 days."
3. Three buttons: **Also Delete Local Data** / **Keep Local Data** / **Cancel**
4. iOS calls `DELETE /api/v1/account` with Bearer token
5. On success:
   - Sign out (clear Keychain)
   - If "Also Delete Local Data": wipe timeline cache, story cache, chat history, reset `hasCompletedOnboarding` → app resets to onboarding
   - If "Keep Local Data": just sign out → app shows LoginView

#### Backend Flow (Lambda)

**Step 1 — `DELETE /api/v1/account` handler:**
1. Extract `userId` from Cognito JWT (API Gateway authorizer context)
2. Fetch Cognito user attributes to get Apple's stable `sub` identifier
3. Write soft-delete record to DynamoDB:
   ```json
   {
     "userId": "cognito-sub-abc123",
     "SK": "DELETION_REQUEST",
     "appleSubject": "apple-stable-sub-xyz",
     "requestedAt": "2026-02-23T10:00:00Z",
     "deleteAfter": "2026-03-25T10:00:00Z",
     "status": "pending"
   }
   ```
4. Disable Cognito user immediately (`AdminDisableUser`) — prevents sign-in
5. Return `200 { scheduled: true, deleteAfter: "2026-03-25T10:00:00Z" }`

**Step 2 — Scheduled cleanup (EventBridge rule, 1x daily):**
1. Scan DynamoDB for deletion requests where `deleteAfter < now` and `status = "pending"`
2. For each:
   - `AdminDeleteUser` from Cognito user pool
   - Delete all DynamoDB records for that userId (usage + deletion request)
   - Log completion
3. This is the actual permanent purge

**Step 3 — Re-signup protection:**
- When a user signs in, Lambda checks for pending deletion request matching the Apple `sub`
- If found within 30-day window: return error "Account deletion in progress. Please wait 30 days or contact support."
- This prevents quota-reset abuse (can't delete and immediately re-create to get fresh limits)

### Abuse Prevention Detail

The key insight: Apple Sign In provides a **stable `sub` claim** per app-developer relationship. Even if Cognito user is deleted and re-created, the Apple sub stays the same.

```
User signs in → Cognito sub: "abc" + Apple sub: "xyz" → uses 5/5 stories
User deletes account → Cognito user disabled, deletion scheduled
User tries re-signup → Apple sub "xyz" matches pending deletion → blocked for 30 days
After 30 days → actual deletion → user can re-signup with fresh account
```

30 days is enough to prevent casual abuse while being reasonable for legitimate re-signups.

### Cache Management

**Clear Story Cache:**
- Deletes all files in `Documents/story_cache/`
- Confirmation: "Clear all cached stories? They'll be regenerated when you view them."

**Clear Chat History:**
- Deletes `Documents/chat_history.json`
- Confirmation: "Clear chat history? This can't be undone."

### Components

#### iOS (New/Modified)

| File | Action | Description |
|------|--------|-------------|
| `Views/Settings/SettingsView.swift` | NEW | Settings tab with Form/List sections |
| `ViewModels/SettingsViewModel.swift` | NEW | Sign out, delete account, cache ops |
| `Services/BackendProvider.swift` | MODIFY | Add `deleteAccount()` method |
| `App/ContentView.swift` | MODIFY | Add Settings tab to MainTabView |

#### Backend (New/Modified)

| File | Action | Description |
|------|--------|-------------|
| `infra/lambda/account.ts` | NEW | DELETE handler: disable user, write deletion request |
| `infra/lambda/cleanup.ts` | NEW | Scheduled Lambda: purge expired deletions |
| `infra/lambda/shared/auth.ts` | MODIFY | Add helper to fetch Apple sub from Cognito user |
| `infra/lib/macphoto-stack.ts` | MODIFY | Add route, EventBridge rule, Cognito+DynamoDB permissions |

### DynamoDB Schema Addition

Reuse existing `macphoto-usage` table with a new sort key pattern:

| userId (PK) | SK | Attributes |
|---|---|---|
| `cognito-sub` | `USAGE` | stories_used, chats_used, month, ... (existing) |
| `cognito-sub` | `DELETION_REQUEST` | appleSubject, requestedAt, deleteAfter, status |

Also need a GSI on `appleSubject` to look up pending deletions during re-signup:

| GSI: `appleSubject-index` |
|---|
| PK: `appleSubject`, SK: `status` |

## Future Considerations

- **Trips+Map merge**: Separate task — merge into single tab with list/map toggle, freeing tab space
- **Incremental refresh**: Pull-to-refresh on Trips tab that only scans new photos since last scan date
- **Privacy Policy URL**: Need actual hosted privacy policy page before App Store submission
- **Usage quota display**: Show remaining stories/chats in Settings (Phase 5 of AWS deployment)
