# iOS LLM Integration: Chat + Storylines

**Date:** 2026-02-19
**Status:** Approved
**Scope:** Add LLM-powered narratives and chat to the iOS app

## Overview

Two LLM features for the iOS app, both using the Anthropic Claude API directly:

1. **Storylines** — auto-generated trip narratives + taglines, displayed inline on the dashboard
2. **Chat** — multi-turn Q&A over travel timeline data, in a dedicated tab

Both features use aggressive caching to minimize API costs. The service layer is protocol-based so swapping from direct API calls to a backend proxy (for commercial distribution) is a one-file change.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| LLM provider | Anthropic (Claude) | Same as Python side, consistency |
| Swift HTTP client | Raw URLSession + SSE | No dependencies, ~200 LOC, full control |
| API key (now) | Build-time env var + XOR obfuscation | Personal use, simple |
| API key (later) | Backend proxy with subscription auth | Required for commercial distribution |
| Chat UI | Separate tab in TabView | Clean separation from dashboard |
| Story caching | SHA256 file cache | Zero API calls on re-launch if data unchanged |
| Chat history | JSON file persistence | Survives app restart |

## Architecture

### Service Layer (Proxy-Ready)

```
Protocol:  LLMProvider
              ├── generateNarratives(timeline) async throws → NarrativeResult
              ├── streamChat(messages, systemPrompt) → AsyncThrowingStream<String, Error>
              └── isAvailable: Bool

Implementations:
  ├── AnthropicDirectProvider   ← builds now (raw URLSession to api.anthropic.com)
  └── BackendProxyProvider      ← builds later (same protocol, hits your server)
```

### Caching

**Story cache (StoryCacheStore):**
- Key: SHA256(compact_timeline_json + prompt_version)
- Value: NarrativeResult JSON (trip narratives + year narratives)
- Location: Documents/story_cache/
- Invalidation: automatic when timeline data changes (different hash)

**Chat history (ChatHistoryStore):**
- Array of ChatMessage (role + content + timestamp)
- Location: Documents/chat_history.json
- Trimmed to last 50 messages

### API Key Configuration

Build-time: `ANTHROPIC_API_KEY` env var → Xcode build setting → Info.plist → XOR-decoded at runtime.

Later: Replace AnthropicDirectProvider with BackendProxyProvider. Add RevenueCat for subscription verification. Backend holds the key.

## Feature 1: Storylines

### Generation Flow

1. Pipeline completes → timeline exists in PipelineViewModel
2. StoryService.generateIfNeeded(timeline) called
3. Compute SHA256 of compact timeline (strips coordinates/photo counts)
4. Check StoryCacheStore for cached result
5. Cache hit → return cached NarrativeResult instantly
6. Cache miss → call Claude via LLMProvider.generateNarratives()
7. Cache the result, return NarrativeResult
8. Merge narratives into DashboardViewModel display data

### Claude Prompt (port of llm_stories.py)

System prompt: Travel storyteller, second person, warm but concise.
Input: Compact timeline JSON (trips with stops/dates/cities, years with stats).
Output: Structured JSON via response parsing:
- Per trip: narrative (1-3 sentences) + tagline (5-8 words)
- Per year: narrative (2-4 sentences)

### UI Integration

**TripCardView:**
- Tagline shown under city name in DesignTokens.textTertiary
- Narrative shown in expanded section above stops list
- Shimmer placeholder while generating

**YearSectionView:**
- Year narrative under the year header + trip count

**Graceful degradation:** Dashboard works immediately. Narratives appear when ready (or from cache). If API key missing or call fails, cards show without narratives — no error state.

## Feature 2: Chat

### Chat Tab

```
┌─────────────────────────┐
│  Travel Chat        ⟳   │  header + clear button
├─────────────────────────┤
│                         │
│  Welcome message +      │  empty state with suggested prompts
│  suggested questions    │
│                         │
│  User bubble (right)    │  teal-tinted glass
│  Assistant bubble (left)│  glass card, streaming tokens
│                         │
├─────────────────────────┤
│ [Message input     ] ➤  │  text field + send button
└─────────────────────────┘
```

### System Prompt (port of chat.py)

Includes: home base, date range, summary stats, full timeline JSON.
Rules: answer from data, be conversational, use specific dates/cities, reference narratives if they exist.

### Streaming

URLSession with `AsyncBytes` parsing SSE events from Anthropic's streaming API.
Tokens rendered word-by-word into the assistant message bubble.

### Suggested Prompts (empty state)

- "What was my longest trip?"
- "Which countries did I visit in 2024?"
- "Compare my summer trips"

### Chat History

- Persisted to Documents/chat_history.json via ChatHistoryStore
- Loaded on app launch
- Conversation context sent to Claude: last 20 messages
- Storage trimmed to last 50 messages
- Clear button resets history

## New Files

| File | Purpose |
|------|---------|
| `Services/LLMProvider.swift` | Protocol + provider factory |
| `Services/AnthropicDirectProvider.swift` | URLSession + SSE streaming |
| `Services/StoryService.swift` | Narrative generation + cache orchestration |
| `Persistence/StoryCacheStore.swift` | SHA256-keyed file cache for narratives |
| `Persistence/ChatHistoryStore.swift` | Persist chat messages to disk |
| `Config/APIKeyConfig.swift` | XOR-decode build-time API key |
| `ViewModels/ChatViewModel.swift` | Chat state, streaming, message management |
| `Views/Chat/ChatView.swift` | Main chat tab |
| `Views/Chat/MessageBubbleView.swift` | User/assistant message bubbles |

## Modified Files

| File | Change |
|------|--------|
| `Models/Timeline.swift` | Add optional narrative/tagline to Trip, narrative to YearSummary |
| `Views/Dashboard/TripCardView.swift` | Show tagline + narrative |
| `Views/Dashboard/YearSectionView.swift` | Show year narrative |
| `App/ContentView.swift` | Wrap in TabView (Dashboard + Chat) |
| `ViewModels/PipelineViewModel.swift` | Trigger story generation after pipeline |
| `ViewModels/DashboardViewModel.swift` | Expose narrative data |
| `project.yml` | Add ANTHROPIC_API_KEY build setting |

## Future: Commercial Distribution

When ready to distribute with subscriptions:
1. Build a backend proxy (Supabase Edge Functions or Cloudflare Workers)
2. Add RevenueCat for App Store subscription management
3. Create BackendProxyProvider implementing LLMProvider protocol
4. Swap the provider in the factory — all UI code unchanged
5. Remove API key from app bundle entirely
