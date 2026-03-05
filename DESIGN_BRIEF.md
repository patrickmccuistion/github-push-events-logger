# Design Brief: GitHub Push Events Logger

## Problem Understanding

We want to track GitHub activity to analyze repository usage and contributor behavior over time. This service ingests Push events, enriches them with actor and repo data, and stores them for querying.

Key constraints: no authenticated token (60 req/hr unauthenticated), must use `https://api.github.com/events`, must be resilient and observable.

## Architecture

Rails API-only app in Docker with PostgreSQL.

- **Ingest**: Poll `/events`, filter PushEvent, persist raw + structured. `INGEST_FIXTURE_PATH` supports deterministic fixture mode (no network).
- **Enrich**: Fetch actor and repo data from URLs in the payload; dedupe by ID before fetch.
- **Rate limit**: On 403/429, exit immediately. Backfill fills missing enrichment when limit resets.
- **Priority**: Persist events first, enrich after. If interrupted, events are saved; run backfill to complete.

## Enrichment Approach

Events are persisted first; enrichment runs afterward. For each PushEvent, the service fetches actor and repository data from `actor.url` and `repo.url` in the payload. The fetch is skipped if the actor or repo already exists in the DB (check by ID), which avoids repeated fetches when the same actor or repo appears in multiple events. Enriched data is stored in `actors` and `repositories`; `push_events` links to them via `actor_id` and `repo_id`. If enrichment is interrupted (e.g., rate limited), run `rails enrich:backfill` to fill in missing actors/repos from `raw_events`.

## Data Model

| Table | Purpose |
|-------|---------|
| raw_events | Event id (PK), payload (JSONB), created_at |
| push_events | event_id (unique), repo_id, actor_id, ref, head, before |
| actors | id, login, avatar_url, name, company, bio, followers, public_repos, account_created_at, raw_json |
| repositories | id, name, full_name, description, language, stargazers_count, forks_count, repo_created_at, pushed_at, raw_json |

## Rate Limits and Durability

- **Amplification**: 1 events fetch + up to (unique actors + unique repos) per poll. Dedupe by ID avoids repeated fetches.
- **ETag / X-Poll-Interval**: Honor If-None-Match on next poll (304 does not count against limit); honor X-Poll-Interval between polls.
- **403/429**: Exit immediately, log reset time. Run backfill when limit resets.
- **Idempotency**: Upsert on event_id; same event upserted multiple times yields same result. Prevents duplicates when API returns same events across polls.
- **Unbounded growth**: Optional `rails data:prune_old_raw_events DAYS=N` prunes old raw_events. Tradeoff: backfill cannot re-enrich from pruned events.

## Extensions

I implemented all four optional extensions to challenge myself. Summary and intentional omissions below.

**A. Rate Limiting and Fan-Out Control**
- Dedupe by ID; `RATE_LIMIT_DELAY` throttles between requests; `MAX_REQUESTS_PER_RUN` caps requests per run.
- On 403/429, ingest and backfill exit immediately and log reset time. Documented in README and this brief.

**B. Idempotency and Restart Safety**
- Upserts on RawEvent (by id), PushEvent (by event_id), Actors and Repositories (by id). Persist events first; enrichment re-runnable via backfill.
- Optional prune task limits growth. Per-event writes are atomic.
- Tradeoffs documented above.

**C. Object Storage**
- Avatars stored via Active Storage (Disk backend) during enrichment. One per actor; skip if already attached.
- `avatar_url` kept as fallback. Graceful failure on fetch errors.

**D. Testing Strategy**
- Unit tests for ingester (persist, rate limit, ETag, idempotency), enricher (dedupe, bot URLs, 429, avatar attach, rate limiter), backfiller (missing actors/repos, skip existing), prune task.
- Integration-style tests with WebMock exercise full flow from fetch to DB.
- Focus on critical paths and edge cases (bot usernames, malformed dates). No live-API e2e; tests run fast and deterministically.

## Tradeoffs and Assumptions

- **Single poll by default**: `ingest` runs once unless `CONTINUOUS=1`. Production would use cron or a long-running process.
- **No auth**: Per spec. With a token, could poll more frequently and enrich more aggressively.

## What I Intentionally Did Not Build

**Extension A:** Background or non-blocking processing (e.g., Redis/Sidekiq for async enrichment). Ingest and backfill are synchronous rake tasks. Rationale: cron-friendly, simpler to operate, no extra infrastructure.

**Extension C:** Raw events or avatars in cloud object storage (S3/GCS). Raw events stay in PostgreSQL; avatars use Active Storage Disk backend for local/Docker compatibility. Rationale: runnable from clean checkout without credentials; Active Storage can be switched later.

**Extension D:** Full end-to-end tests that run ingest inside Docker against the live API. Rationale: WebMock keeps tests fast and deterministic; e2e would require network and rate limit handling better validated manually.

**Out of scope:** Web UI or API endpoints for querying (data is in PostgreSQL). Webhook ingestion (spec requires public events API).
