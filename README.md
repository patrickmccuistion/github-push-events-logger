# GitHub Push Events Logger

An internal service that ingests GitHub Push events from the public API, enriches them with actor and repository data, and stores them in PostgreSQL for analysis.

## Prerequisites

- Docker Desktop for Mac
- Git

## Start the System

```bash
docker compose up --build
```

This starts the Rails app and PostgreSQL. The app runs at http://localhost:3000.

To run in the background:

```bash
docker compose up --build -d
```

## Run Ingestion

```bash
docker compose run --rm ingest
```

This fetches events from `https://api.github.com/events`, filters for PushEvent only, persists raw and structured data, then enriches by fetching actor/repo data from URLs in the payload. **Events are persisted first**; enrichment runs after. When rate limited (403/429), ingest exits immediately. Run backfill when the limit resets.

For continuous polling (respects X-Poll-Interval and ETag):

```bash
docker compose run --rm -e CONTINUOUS=1 ingest
```

**Rate limiting and fan-out control:** Amplification is 1 events fetch plus up to (unique actors + unique repos) per poll. Unauthenticated limit is 60 req/hr. On 403/429, ingest exits immediately; run backfill when the limit resets. Optional env vars:
- `RATE_LIMIT_DELAY=2` – seconds to sleep between enrichment requests (reduces chance of hitting limit)
- `MAX_REQUESTS_PER_RUN=50` – stop before hitting 60; run again later to complete

## Backfill Enrichment

If ingest exits due to rate limit before enriching all events, run the backfill job when the limit resets. It finds unenriched records and fetches them. Backfill also exits on rate limit:

```bash
docker compose run --rm backfill
```

Run after ingest, or on a schedule (e.g. cron) to gradually complete enrichment.

## Optional: Prune Old Raw Events

To limit database growth, prune `raw_events` older than N days. **Warning:** Backfill cannot re-enrich from pruned events.

```bash
docker compose run --rm -e DAYS=90 app bin/rails data:prune_old_raw_events
```

## Run Tests

```bash
docker compose run --rm test
```

## How to Verify It's Working

1. **Start the system**: `docker compose up --build -d`
2. **Run ingestion**: `docker compose run --rm ingest`
3. **Check logs**: `docker compose logs -f` shows:
   - `[ingest] Fetched N events, M PushEvents`
   - `[ingest] Persisted PushEvent <id>`
   - `[enrich] Fetched actor/repo <id>` (when new actors/repos are fetched)
   - `[enrich] Rate limited (403/429). Exiting...` (when limit hit; ingest exits, run backfill later)
4. **Query the database**:
   ```bash
   # Push events
   docker compose exec db psql -U postgres -d github_push_events_development -c "SELECT event_id, repo_id, ref, head, before FROM push_events LIMIT 5;"

   # Actors (enriched: name, company, bio, followers, public_repos)
   docker compose exec db psql -U postgres -d github_push_events_development -c "SELECT id, login, name, company, followers FROM actors ORDER BY followers DESC NULLS LAST LIMIT 5;"

   # Repositories (enriched: description, language, stargazers_count, forks_count)
   docker compose exec db psql -U postgres -d github_push_events_development -c "SELECT id, full_name, language, stargazers_count, forks_count FROM repositories ORDER BY stargazers_count DESC NULLS LAST LIMIT 5;"

   # Actor avatars (stored in Active Storage, Disk backend)
   docker compose exec app bin/rails runner "puts Actor.find(1).avatar.attached?"
   ```
5. **Expected timing**: Events can have 30s to 6h latency per GitHub docs. You may see 0 PushEvents on first run if the public feed has none at that moment. Run again or wait for activity.

## Teardown

```bash
docker compose down -v
```

The `-v` flag removes the PostgreSQL volume. No local Ruby or PostgreSQL installation is required; everything runs in Docker.