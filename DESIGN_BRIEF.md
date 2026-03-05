# Design Brief: GitHub Push Events Logger

## Problem Understanding

StrongMind wants visibility into GitHub activity so they can analyze repository usage and contributor behavior over time. This service ingests GitHub Push events, enriches them with related data, and stores them durably for future querying.

Key constraints:
- No authenticated token (60 req/hr unauthenticated)
- Must use `https://api.github.com/events`
- Must be resilient and observable

## Proposed Architecture

- **Rails API-only** app in Docker with PostgreSQL
- **Ingest**: Poll `/events`, filter PushEvent, persist raw + structured
- **Enrich**: Fetch actor and repo data from URLs in the event payload; dedupe by ID before fetch
- **Rate limit**: On 403/429, exit immediately (no wait). Backfill job fills in missing enrichment when limit resets.
- **Priority**: Push events first. Persist all events, then enrich. If rate limited during enrichment, exit; events are already saved.

## Data Model

| Table | Purpose |
|-------|---------|
| raw_events | Event id (PK), payload (JSONB), created_at |
| push_events | event_id (unique), repo_id, actor_id, ref, head, before |
| actors | id, login, avatar_url, name, company, bio, followers, public_repos, account_created_at, raw_json |
| repositories | id, name, full_name, description, language, stargazers_count, forks_count, repo_created_at, pushed_at, raw_json |

## Rate Limits and Durability

- **ETag**: Send If-None-Match on next poll; 304 response does not count against rate limit
- **X-Poll-Interval**: Honor header (typically 60s) between polls
- **403/429**: Exit immediately. Log reset time. Run backfill when limit resets.
- **Enrichment**: Fetch from actor.url and repo.url; dedupe by ID; exit on rate limit
- **Backfill**: `rails enrich:backfill` finds missing actors/repos from raw_events, fetches them, exits on rate limit
- **Idempotency**: Upsert on event_id; restart-safe

## Tradeoffs and Assumptions

- **Fetch-based enrichment**: Actor and repo data fetched from URLs in payload. Dedupe by ID avoids repeated fetches for same actor/repo. Wait-and-retry on 403/429 demonstrates rate limit handling (Extension A).
- **Single poll by default**: `ingest` runs once unless CONTINUOUS=1. Production would use cron or a long-running process.
- **No auth**: Per spec. With a token, I could poll more frequently and enrich more aggressively.

## What I Intentionally Did Not Build

- Web UI or API endpoints for querying (data is in PostgreSQL)
- Object storage for avatars (Extension C)
- Redis/Sidekiq for async enrichment (backfill is a synchronous rake task; cron-friendly)
- Webhook ingestion (spec requires public events API)
