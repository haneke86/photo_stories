# Production AWS Backend — Privacy-First Architecture

**Date**: 2026-02-22
**Status**: Approved

## Context

MacPhotoTrips is a working iOS app with 5 tabs (Trips, Stories, Map, Stats, Chat) that detects trips from the Photos library and generates AI-powered narratives via the Anthropic Claude API. Currently the API key is baked into the binary at build time — this blocks App Store distribution and multi-user use. We need a production backend that:

1. Secures the Anthropic API key server-side
2. Authenticates users via Sign in with Apple
3. Enforces usage caps (5 stories, 20 chat messages/month)
4. Keeps all user data on-device (privacy-first)

**AWS services**: Cognito, API Gateway (HTTP API), Lambda (Node.js), DynamoDB
**IaC**: AWS CDK (TypeScript)
**Region**: us-east-1
**Cost at launch**: ~$0/mo (free tier covers auth + compute + storage at small scale)

## Architecture

```
iOS App ──JWT──► API Gateway ──► Lambda ──► Anthropic API
                                  │
                           ┌──────┴──────┐
                           │  DynamoDB    │
                           │  (usage caps)│
                           └─────────────┘
                           ┌─────────────┐
                           │  Cognito     │
                           │  (Apple ID)  │
                           └─────────────┘
```

**On device** (unchanged): Photos, timeline.json, story cache, chat history, geocoding cache
**In cloud** (new): Auth tokens, LLM request relay, usage counters

## DynamoDB Schema

| Attribute | Type | Description |
|-----------|------|-------------|
| `userId` (PK) | String | Cognito sub (from Apple ID) |
| `storiesUsed` | Number | Stories generated this period |
| `chatsUsed` | Number | Chat messages this period |
| `periodStart` | String | ISO date of current billing period start |
| `createdAt` | String | Account creation date |

## API Endpoints

| Method | Path | Handler | Auth |
|--------|------|---------|------|
| POST | /api/v1/stories/generate | proxy.ts | Cognito JWT |
| POST | /api/v1/stories/single | proxy.ts | Cognito JWT |
| POST | /api/v1/chat | chat.ts (Function URL) | Manual JWT |
| GET | /api/v1/usage | usage.ts | Cognito JWT |

## Usage Limits

| Resource | Monthly Limit |
|----------|--------------|
| Stories | 5 |
| Chat messages | 20 |

Period resets on the 1st of each month.

## Implementation Phases

1. CDK Infrastructure Stack
2. Lambda Proxy Implementation
3. iOS Auth Integration (Sign in with Apple → Cognito)
4. iOS Backend Provider Swap (replace AnthropicDirectProvider)
5. Usage Tracking UI

## Privacy

- No photos leave the device
- No timeline data stored server-side
- Only LLM prompts/responses transit the backend
- Usage counters are the only persistent server-side data
- Apple ID is the only identity — no email/password
