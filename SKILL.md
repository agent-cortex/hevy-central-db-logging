---
name: hevy-central-db-logging
description: Use when setting up an open-source Hevy App fitness logging pipeline from Hevy API to a central PostgreSQL-compatible database, including endpoint coverage, schema design, sync scripts, idempotency, webhook/polling fallback, and verification.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [fitness, hevy, api, postgres, workout-logging, sync, cron, webhooks]
    related_skills: [fitness-live-session-logging, fitness-postgres-sync-hardening]
---

# Hevy Central DB Logging

## Overview

Use this skill to set up a production-grade logging flow from the Hevy App API into a central database. The target architecture is:

```text
Hevy App / Hevy API
  -> incremental sync using /v1/workouts/events
  -> fetch full workout records when needed
  -> normalize workouts/exercises/sets/templates/body measurements
  -> upsert into PostgreSQL/Supabase/Neon/local Postgres
  -> optional webhook receiver or scheduled poller
  -> analytics/review layer reads only from the central DB
```

Default choice: **PostgreSQL-compatible DB**. SQLite is okay for local experiments, but a central DB should be Postgres so multiple agents, dashboards, and cron jobs can share one source of truth.

Hevy API docs: `https://api.hevyapp.com/docs/`

Linked files:
- `references/hevy-openapi-endpoints.md` — full endpoint reference extracted from the Swagger docs.
- `templates/agent-prompt.md` — copy/paste prompt for sending this setup task to another agent.

Important API reality:
- Hevy public API is experimental.
- It currently requires Hevy Pro.
- Auth is an `api-key` HTTP header, not Bearer auth.
- Never print the API key in chat or logs.
- Treat webhooks as optional if the user's Hevy developer settings support them; the portable baseline is polling `/v1/workouts/events`.

## When to Use

Use this when the user wants:
- Hevy workouts synced into a database.
- A portable open-source fitness logging stack.
- A central DB schema for workouts, exercises, sets, templates, body measurements, and sync state.
- Incremental sync that handles workout updates and deletes.
- Cron/systemd/GitHub Actions/serverless polling.
- Webhook receiver plus polling fallback.
- Analytics dashboards or fitness-agent summaries backed by DB rows, not screenshots or scraped pages.

Do not use this for:
- One-off manual workout parsing from chat text; use live workout logging instead.
- Nutrition logging; Hevy does not provide food diary endpoints here.
- Apple Health direct sync; that needs HealthKit/export tooling.

## Hevy API Endpoint Map

Base URL:

```text
https://api.hevyapp.com
```

Auth header for every endpoint:

```text
api-key: <HEVY_API_KEY>
```

### Core workout sync endpoints

These are the most important endpoints for a central logging stack:

- `GET /v1/user/info`
  - Purpose: verify credentials and store user identity.
  - Response shape: `data.id`, `data.name`, `data.url`.

- `GET /v1/workouts?page=1&pageSize=10`
  - Purpose: initial backfill or recent-window sync.
  - Params: `page`, `pageSize`.
  - Use when bootstrapping or recovering.

- `GET /v1/workouts/count`
  - Purpose: count remote workout total; useful for backfill completeness checks.

- `GET /v1/workouts/events?since=<ISO>&page=1&pageSize=10`
  - Purpose: incremental sync of updated/deleted workouts since timestamp.
  - Events are newest-to-oldest.
  - Events are either `updated` with full `workout`, or `deleted` with `id` and `deleted_at`.
  - Known practical cap: use `pageSize=10`; larger values may 400.
  - This is the default poller endpoint.

- `GET /v1/workouts/{workoutId}`
  - Purpose: fetch canonical full workout by ID.
  - Use after an event if the event payload is incomplete or for spot repair.

- `POST /v1/workouts`
  - Purpose: create workouts in Hevy from your system.
  - Usually **not needed** for logging Hevy -> DB.

- `PUT /v1/workouts/{workoutId}`
  - Purpose: update Hevy workout.
  - Usually avoid unless the user explicitly wants bidirectional sync.

### Routine/template endpoints

Use these to preserve richer metadata and build better dashboards:

- `GET /v1/routines?page=1&pageSize=10`
- `GET /v1/routines/{routineId}`
- `POST /v1/routines`
- `PUT /v1/routines/{routineId}`
- `GET /v1/routine_folders?page=1&pageSize=10`
- `GET /v1/routine_folders/{folderId}`
- `POST /v1/routine_folders`
- `GET /v1/exercise_templates?page=1&pageSize=10`
- `GET /v1/exercise_templates/{exerciseTemplateId}`
- `POST /v1/exercise_templates`
- `GET /v1/exercise_history/{exerciseTemplateId}?start_date=<ISO>&end_date=<ISO>`

Recommended use:
- Sync exercise templates daily/weekly, not every workout.
- Store `exercise_template_id` on every exercise row.
- Use exercise history only for focused analytics or repair; normal analytics can be computed from your own `hevy_sets` table.

### Body measurement endpoints

Useful for bodyweight/body composition tracking:

- `GET /v1/body_measurements?page=1&pageSize=10`
- `POST /v1/body_measurements`
- `GET /v1/body_measurements/{date}` where date is `YYYY-MM-DD`
- `PUT /v1/body_measurements/{date}`

Fields include:
- `date`
- `weight_kg`
- `lean_mass_kg`
- `fat_percent`
- `neck_cm`, `shoulder_cm`, `chest_cm`
- `left_bicep_cm`, `right_bicep_cm`
- `left_forearm_cm`, `right_forearm_cm`
- `abdomen`, `waist`, `hips`
- `left_thigh`, `right_thigh`
- `left_calf`, `right_calf`

## Data Model

Use a normalized DB model. Do not store one giant JSON blob as the only source of truth. Keep raw JSON for audit, but compute analytics from relational rows.

### Required tables

- `hevy_users`
- `hevy_workouts`
- `hevy_exercises`
- `hevy_sets`
- `hevy_deleted_workouts`
- `hevy_sync_state`
- `hevy_raw_events`

### Recommended tables

- `hevy_exercise_templates`
- `hevy_routines`
- `hevy_routine_folders`
- `hevy_body_measurements`

## PostgreSQL Schema

Run this in the target database.

```sql
CREATE SCHEMA IF NOT EXISTS fitness;

CREATE TABLE IF NOT EXISTS fitness.hevy_users (
  hevy_user_id TEXT PRIMARY KEY,
  name TEXT,
  profile_url TEXT,
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fitness.hevy_workouts (
  workout_id TEXT PRIMARY KEY,
  title TEXT,
  routine_id TEXT,
  description TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS fitness.hevy_exercises (
  id BIGSERIAL PRIMARY KEY,
  workout_id TEXT NOT NULL REFERENCES fitness.hevy_workouts(workout_id) ON DELETE CASCADE,
  exercise_index INTEGER NOT NULL,
  title TEXT NOT NULL,
  notes TEXT,
  exercise_template_id TEXT,
  superset_id INTEGER,
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workout_id, exercise_index)
);

CREATE TABLE IF NOT EXISTS fitness.hevy_sets (
  id BIGSERIAL PRIMARY KEY,
  workout_id TEXT NOT NULL REFERENCES fitness.hevy_workouts(workout_id) ON DELETE CASCADE,
  exercise_index INTEGER NOT NULL,
  set_index INTEGER NOT NULL,
  set_type TEXT,
  weight_kg NUMERIC(10, 3),
  reps NUMERIC(10, 3),
  distance_meters NUMERIC(12, 3),
  duration_seconds NUMERIC(12, 3),
  rpe NUMERIC(4, 1),
  custom_metric NUMERIC(12, 3),
  estimated_volume_kg NUMERIC(14, 3) GENERATED ALWAYS AS (
    CASE
      WHEN weight_kg IS NOT NULL AND reps IS NOT NULL THEN weight_kg * reps
      ELSE 0
    END
  ) STORED,
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workout_id, exercise_index, set_index)
);

CREATE TABLE IF NOT EXISTS fitness.hevy_deleted_workouts (
  workout_id TEXT PRIMARY KEY,
  deleted_at TIMESTAMPTZ,
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fitness.hevy_sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fitness.hevy_raw_events (
  id BIGSERIAL PRIMARY KEY,
  event_type TEXT,
  workout_id TEXT,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw_json JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS fitness.hevy_exercise_templates (
  exercise_template_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  type TEXT,
  primary_muscle_group TEXT,
  secondary_muscle_groups TEXT[],
  is_custom BOOLEAN,
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fitness.hevy_body_measurements (
  measurement_date DATE PRIMARY KEY,
  weight_kg NUMERIC(10, 3),
  lean_mass_kg NUMERIC(10, 3),
  fat_percent NUMERIC(6, 3),
  neck_cm NUMERIC(10, 3),
  shoulder_cm NUMERIC(10, 3),
  chest_cm NUMERIC(10, 3),
  left_bicep_cm NUMERIC(10, 3),
  right_bicep_cm NUMERIC(10, 3),
  left_forearm_cm NUMERIC(10, 3),
  right_forearm_cm NUMERIC(10, 3),
  abdomen NUMERIC(10, 3),
  waist NUMERIC(10, 3),
  hips NUMERIC(10, 3),
  left_thigh NUMERIC(10, 3),
  right_thigh NUMERIC(10, 3),
  left_calf NUMERIC(10, 3),
  right_calf NUMERIC(10, 3),
  raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hevy_workouts_start_time ON fitness.hevy_workouts(start_time DESC);
CREATE INDEX IF NOT EXISTS idx_hevy_workouts_updated_at ON fitness.hevy_workouts(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_hevy_exercises_template ON fitness.hevy_exercises(exercise_template_id);
CREATE INDEX IF NOT EXISTS idx_hevy_sets_workout_exercise ON fitness.hevy_sets(workout_id, exercise_index);
CREATE INDEX IF NOT EXISTS idx_hevy_raw_events_received ON fitness.hevy_raw_events(received_at DESC);
```

### Optional volume convention layer

If the user logs dumbbell weights per hand, do **not** bake that into raw Hevy tables. Keep raw Hevy values intact and create a view for analytics-specific volume.

```sql
CREATE OR REPLACE VIEW fitness.hevy_set_analytics AS
SELECT
  s.*,
  e.title AS exercise_title,
  w.start_time,
  CASE
    WHEN e.title ILIKE '%dumbbell%' OR e.title ILIKE '%db%' THEN COALESCE(s.weight_kg, 0) * COALESCE(s.reps, 0) * 2
    ELSE COALESCE(s.weight_kg, 0) * COALESCE(s.reps, 0)
  END AS convention_volume_kg
FROM fitness.hevy_sets s
JOIN fitness.hevy_exercises e
  ON e.workout_id = s.workout_id AND e.exercise_index = s.exercise_index
JOIN fitness.hevy_workouts w
  ON w.workout_id = s.workout_id
WHERE w.deleted_at IS NULL;
```

## Environment Variables

Use env vars or a secret manager. Never hardcode secrets.

```bash
export HEVY_API_KEY='...'
export DATABASE_URL='postgresql://user:password@host:5432/dbname'
export HEVY_SYNC_SINCE_DEFAULT='1970-01-01T00:00:00Z'
```

For open-source repos, ship `.env.example` only:

```text
HEVY_API_KEY=
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/fitness_logs
HEVY_SYNC_SINCE_DEFAULT=1970-01-01T00:00:00Z
```

## Python Sync Implementation

Recommended dependencies:

```bash
python -m venv .venv
. .venv/bin/activate
pip install httpx psycopg[binary] python-dotenv
```

Minimal `hevy_sync.py`:

```python
#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime, timezone

import httpx
import psycopg
from psycopg.types.json import Jsonb
from dotenv import load_dotenv

load_dotenv()

BASE_URL = "https://api.hevyapp.com"
API_KEY = os.environ["HEVY_API_KEY"]
DATABASE_URL = os.environ["DATABASE_URL"]
DEFAULT_SINCE = os.getenv("HEVY_SYNC_SINCE_DEFAULT", "1970-01-01T00:00:00Z")
PAGE_SIZE = 10


def iso_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_ts(value):
    if not value:
        return None
    return value


class HevyClient:
    def __init__(self):
        self.client = httpx.Client(
            base_url=BASE_URL,
            headers={"api-key": API_KEY, "accept": "application/json"},
            timeout=30,
        )

    def get(self, path, **params):
        r = self.client.get(path, params={k: v for k, v in params.items() if v is not None})
        r.raise_for_status()
        return r.json()

    def user_info(self):
        return self.get("/v1/user/info")

    def workouts(self, page=1, page_size=PAGE_SIZE):
        return self.get("/v1/workouts", page=page, pageSize=page_size)

    def workout(self, workout_id):
        return self.get(f"/v1/workouts/{workout_id}")

    def workout_events(self, since, page=1, page_size=PAGE_SIZE):
        return self.get("/v1/workouts/events", since=since, page=page, pageSize=page_size)

    def exercise_templates(self, page=1, page_size=PAGE_SIZE):
        return self.get("/v1/exercise_templates", page=page, pageSize=page_size)

    def body_measurements(self, page=1, page_size=10):
        return self.get("/v1/body_measurements", page=page, pageSize=page_size)


def get_sync_state(conn, key, default):
    row = conn.execute("SELECT value FROM fitness.hevy_sync_state WHERE key = %s", (key,)).fetchone()
    return row[0] if row else default


def set_sync_state(conn, key, value):
    conn.execute(
        """
        INSERT INTO fitness.hevy_sync_state(key, value, updated_at)
        VALUES (%s, %s, now())
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()
        """,
        (key, value),
    )


def upsert_user(conn, payload):
    user = payload.get("data", payload)
    conn.execute(
        """
        INSERT INTO fitness.hevy_users(hevy_user_id, name, profile_url, raw_json, updated_at)
        VALUES (%s, %s, %s, %s, now())
        ON CONFLICT (hevy_user_id) DO UPDATE SET
          name = EXCLUDED.name,
          profile_url = EXCLUDED.profile_url,
          raw_json = EXCLUDED.raw_json,
          updated_at = now()
        """,
        (user.get("id"), user.get("name"), user.get("url"), Jsonb(payload)),
    )


def upsert_workout(conn, workout):
    workout_id = workout["id"]
    conn.execute(
        """
        INSERT INTO fitness.hevy_workouts(
          workout_id, title, routine_id, description, start_time, end_time,
          created_at, updated_at, synced_at, deleted_at, raw_json
        ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,now(),NULL,%s)
        ON CONFLICT (workout_id) DO UPDATE SET
          title = EXCLUDED.title,
          routine_id = EXCLUDED.routine_id,
          description = EXCLUDED.description,
          start_time = EXCLUDED.start_time,
          end_time = EXCLUDED.end_time,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          synced_at = now(),
          deleted_at = NULL,
          raw_json = EXCLUDED.raw_json
        """,
        (
            workout_id,
            workout.get("title"),
            workout.get("routine_id"),
            workout.get("description"),
            parse_ts(workout.get("start_time")),
            parse_ts(workout.get("end_time")),
            parse_ts(workout.get("created_at")),
            parse_ts(workout.get("updated_at")),
            Jsonb(workout),
        ),
    )

    # Replace child rows on each workout update. This is simpler and safer than partial merging.
    conn.execute("DELETE FROM fitness.hevy_sets WHERE workout_id = %s", (workout_id,))
    conn.execute("DELETE FROM fitness.hevy_exercises WHERE workout_id = %s", (workout_id,))

    for ex_pos, exercise in enumerate(workout.get("exercises") or []):
        exercise_index = int(exercise.get("index", ex_pos))
        conn.execute(
            """
            INSERT INTO fitness.hevy_exercises(
              workout_id, exercise_index, title, notes, exercise_template_id, superset_id, raw_json
            ) VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (workout_id, exercise_index) DO UPDATE SET
              title = EXCLUDED.title,
              notes = EXCLUDED.notes,
              exercise_template_id = EXCLUDED.exercise_template_id,
              superset_id = EXCLUDED.superset_id,
              raw_json = EXCLUDED.raw_json
            """,
            (
                workout_id,
                exercise_index,
                exercise.get("title") or "Unknown Exercise",
                exercise.get("notes"),
                exercise.get("exercise_template_id"),
                exercise.get("supersets_id") if "supersets_id" in exercise else exercise.get("superset_id"),
                Jsonb(exercise),
            ),
        )

        for set_pos, set_row in enumerate(exercise.get("sets") or []):
            set_index = int(set_row.get("index", set_pos))
            conn.execute(
                """
                INSERT INTO fitness.hevy_sets(
                  workout_id, exercise_index, set_index, set_type, weight_kg, reps,
                  distance_meters, duration_seconds, rpe, custom_metric, raw_json
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (workout_id, exercise_index, set_index) DO UPDATE SET
                  set_type = EXCLUDED.set_type,
                  weight_kg = EXCLUDED.weight_kg,
                  reps = EXCLUDED.reps,
                  distance_meters = EXCLUDED.distance_meters,
                  duration_seconds = EXCLUDED.duration_seconds,
                  rpe = EXCLUDED.rpe,
                  custom_metric = EXCLUDED.custom_metric,
                  raw_json = EXCLUDED.raw_json
                """,
                (
                    workout_id,
                    exercise_index,
                    set_index,
                    set_row.get("type"),
                    set_row.get("weight_kg"),
                    set_row.get("reps"),
                    set_row.get("distance_meters"),
                    set_row.get("duration_seconds"),
                    set_row.get("rpe"),
                    set_row.get("custom_metric"),
                    Jsonb(set_row),
                ),
            )


def mark_deleted(conn, event):
    workout_id = event["id"]
    deleted_at = event.get("deleted_at")
    conn.execute(
        """
        INSERT INTO fitness.hevy_deleted_workouts(workout_id, deleted_at, raw_json, synced_at)
        VALUES (%s, %s, %s, now())
        ON CONFLICT (workout_id) DO UPDATE SET
          deleted_at = EXCLUDED.deleted_at,
          raw_json = EXCLUDED.raw_json,
          synced_at = now()
        """,
        (workout_id, parse_ts(deleted_at), Jsonb(event)),
    )
    conn.execute("UPDATE fitness.hevy_workouts SET deleted_at = %s, synced_at = now() WHERE workout_id = %s", (parse_ts(deleted_at), workout_id))


def log_raw_event(conn, event_type, workout_id, payload):
    conn.execute(
        "INSERT INTO fitness.hevy_raw_events(event_type, workout_id, raw_json) VALUES (%s, %s, %s)",
        (event_type, workout_id, Jsonb(payload)),
    )


def sync_user(client, conn):
    payload = client.user_info()
    upsert_user(conn, payload)
    return 1


def sync_all_workouts(client, conn, max_pages=None):
    synced = 0
    page = 1
    while True:
        payload = client.workouts(page=page, page_size=PAGE_SIZE)
        workouts = payload.get("workouts") or payload.get("data") or []
        if not workouts:
            break
        for workout in workouts:
            upsert_workout(conn, workout)
            synced += 1
        page_count = payload.get("page_count") or payload.get("pageCount")
        if max_pages and page >= max_pages:
            break
        if page_count and page >= int(page_count):
            break
        page += 1
    return synced


def sync_events(client, conn):
    since = get_sync_state(conn, "workouts_events_since", DEFAULT_SINCE)
    new_since = iso_now()
    page = 1
    updated = deleted = 0

    while True:
        payload = client.workout_events(since=since, page=page, page_size=PAGE_SIZE)
        events = payload.get("events") or []
        if not events:
            break

        for event in events:
            event_type = event.get("type")
            if event_type == "deleted":
                log_raw_event(conn, "deleted", event.get("id"), event)
                mark_deleted(conn, event)
                deleted += 1
            elif event_type == "updated":
                workout = event.get("workout")
                if workout:
                    log_raw_event(conn, "updated", workout.get("id"), event)
                    upsert_workout(conn, workout)
                    updated += 1

        page_count = payload.get("page_count") or payload.get("pageCount")
        if page_count and page >= int(page_count):
            break
        page += 1

    set_sync_state(conn, "workouts_events_since", new_since)
    return {"updated": updated, "deleted": deleted, "since": since, "next_since": new_since}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--init-user", action="store_true")
    parser.add_argument("--backfill", action="store_true")
    parser.add_argument("--events", action="store_true")
    parser.add_argument("--max-pages", type=int)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    client = HevyClient()
    out = {}
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.transaction():
            if args.init_user:
                out["user_synced"] = sync_user(client, conn)
            if args.backfill:
                out["workouts_synced"] = sync_all_workouts(client, conn, max_pages=args.max_pages)
            if args.events:
                out["events"] = sync_events(client, conn)

    if args.json:
        print(json.dumps(out, indent=2, sort_keys=True))
    else:
        print(out)


if __name__ == "__main__":
    main()
```

## Setup Flow for an Agent

When the user asks to set this up, do this exact sequence.

### 1. Check prerequisites

```bash
python --version
psql --version || true
```

If using local Postgres:

```bash
createdb fitness_logs || true
psql "$DATABASE_URL" -f schema.sql
```

If using Supabase/Neon/Railway:
- Ask for or locate a `DATABASE_URL` secret.
- Do not print it.
- Run schema through `psql "$DATABASE_URL" -f schema.sql`.

### 2. Store secrets safely

Use whichever secret store exists in the user's environment:

```bash
# pass example
pass insert hevy/api-key
pass insert fitness/database-url
```

Then load without echoing:

```bash
export HEVY_API_KEY="$(pass show hevy/api-key | tr -d '\n')"
export DATABASE_URL="$(pass show fitness/database-url | head -n1)"
```

### 3. Smoke test Hevy auth

```bash
curl -fsS https://api.hevyapp.com/v1/user/info \
  -H "api-key: $HEVY_API_KEY" \
  -H 'accept: application/json'
```

Expected: JSON with `data.id`, `data.name`, `data.url`.

Do not paste the response if it includes private profile info unless the user explicitly asks.

### 4. Initialize DB and sync user

```bash
python hevy_sync.py --init-user --json
```

### 5. Initial backfill

```bash
python hevy_sync.py --backfill --json
```

For huge accounts, use page limits first:

```bash
python hevy_sync.py --backfill --max-pages 2 --json
```

### 6. Incremental sync

```bash
python hevy_sync.py --events --json
```

Run twice. The second run should normally show zero changed events unless the remote account changed.

### 7. Schedule the sync

Pick one:

#### Cron

```cron
*/30 * * * * cd /path/to/hevy-stack && . .venv/bin/activate && python hevy_sync.py --events --json >> logs/hevy-sync.log 2>&1
```

#### systemd user timer

`~/.config/systemd/user/hevy-sync.service`:

```ini
[Unit]
Description=Hevy API incremental sync

[Service]
Type=oneshot
WorkingDirectory=%h/hevy-stack
EnvironmentFile=%h/hevy-stack/.env
ExecStart=%h/hevy-stack/.venv/bin/python %h/hevy-stack/hevy_sync.py --events --json
```

`~/.config/systemd/user/hevy-sync.timer`:

```ini
[Unit]
Description=Run Hevy API sync every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now hevy-sync.timer
systemctl --user list-timers | grep hevy-sync
```

#### Hermes no-agent cron

Use this when the environment already runs Hermes and the desired output is either silent success or a concise alert.

- Script path must live under `~/.hermes/scripts/`.
- Empty stdout means silent.
- Non-empty stdout is delivered.

A good checker wraps `hevy_sync.py --events --json`, prints nothing for zero changes, and prints a one-line summary for new workouts or a concise failure alert.

## Optional Webhook Receiver

If Hevy developer settings allow webhooks, add a receiver. Do **not** depend only on webhooks; keep the `/v1/workouts/events` poller as fallback.

Receiver behavior:
1. Accept POST `/hevy/webhook`.
2. Verify a shared secret header controlled by you, e.g. `Authorization: Bearer <WEBHOOK_TOKEN>`.
3. Append raw payload to JSONL for audit.
4. Trigger `python hevy_sync.py --events --json` asynchronously.
5. Return `202` quickly.

Webhook pitfall: do not trust the webhook payload as canonical. Use it as a trigger, then call `/v1/workouts/events` or fetch the workout by ID.

## Verification Queries

Run after setup.

```sql
SELECT count(*) AS workouts FROM fitness.hevy_workouts WHERE deleted_at IS NULL;
SELECT count(*) AS exercises FROM fitness.hevy_exercises;
SELECT count(*) AS sets FROM fitness.hevy_sets;
SELECT max(start_time) AS latest_workout FROM fitness.hevy_workouts WHERE deleted_at IS NULL;
```

Top exercises by convention volume:

```sql
SELECT
  exercise_title,
  count(DISTINCT workout_id) AS sessions,
  count(*) AS sets,
  sum(convention_volume_kg) AS volume_kg
FROM fitness.hevy_set_analytics
GROUP BY exercise_title
ORDER BY volume_kg DESC
LIMIT 20;
```

Recent workout summary:

```sql
SELECT
  w.start_time::date AS day,
  w.title,
  count(DISTINCT e.id) AS exercises,
  count(s.id) AS sets,
  sum(COALESCE(s.weight_kg, 0) * COALESCE(s.reps, 0)) AS raw_volume_kg
FROM fitness.hevy_workouts w
LEFT JOIN fitness.hevy_exercises e ON e.workout_id = w.workout_id
LEFT JOIN fitness.hevy_sets s ON s.workout_id = e.workout_id AND s.exercise_index = e.exercise_index
WHERE w.deleted_at IS NULL
GROUP BY w.workout_id, w.start_time, w.title
ORDER BY w.start_time DESC
LIMIT 10;
```

Sync state:

```sql
SELECT * FROM fitness.hevy_sync_state ORDER BY updated_at DESC;
SELECT event_type, count(*) FROM fitness.hevy_raw_events GROUP BY event_type;
```

## Data Rules

- Raw Hevy data is sacred: preserve `raw_json` on workouts, exercises, sets, templates, measurements, and events.
- Analytics conventions belong in SQL views or derived tables.
- Deletes must not physically remove workouts by default; set `deleted_at` and preserve a deleted event row.
- Workout updates should replace child exercise/set rows for that workout to avoid stale sets.
- Use `exercise_template_id` as the stable exercise identity when available; title can change.
- Store both `start_time` and `updated_at`; use `start_time` for training timeline, `updated_at` for sync/debugging.
- Treat `distance_meters`, `duration_seconds`, and `custom_metric` as first-class fields; not every exercise is weight × reps.
- `rpe` may be null or one of Hevy's allowed values such as `6`, `7`, `7.5`, `8`, `8.5`, `9`, `9.5`, `10`.

## Open-Source Repo Layout

Recommended structure:

```text
hevy-fitness-stack/
  README.md
  .env.example
  pyproject.toml
  sql/
    001_schema.sql
  src/hevy_fitness/
    __init__.py
    client.py
    db.py
    sync.py
    webhook.py
  scripts/
    hevy_sync.py
    verify_sync.py
  systemd/
    hevy-sync.service
    hevy-sync.timer
  docker-compose.yml
  tests/
    test_normalize.py
    test_upsert.py
```

README must include:
- Hevy Pro/API key requirement.
- `api-key` header auth.
- How to run schema migration.
- How to backfill.
- How to run incremental events sync.
- How to schedule sync.
- Privacy note: fitness data is sensitive.

## Docker Compose Baseline

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: fitness_logs
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  hevy-sync:
    build: .
    env_file: .env
    depends_on:
      - postgres
    command: ["python", "hevy_sync.py", "--events", "--json"]

volumes:
  postgres_data:
```

Do not ship real secrets in `.env`.

## Common Pitfalls

1. **Using Bearer auth for Hevy.** The docs use `api-key` header. Bearer auth is for your own webhook receiver, not Hevy API.

2. **Making webhooks mandatory.** The portable sync path is `/v1/workouts/events`. Webhooks are only a trigger optimization.

3. **Ignoring deletes.** If a user deletes or edits a workout in Hevy, your DB must reflect it. Store deleted events and mark `hevy_workouts.deleted_at`.

4. **Double-counting updates.** Do not append child sets on workout update. Delete and replace child rows for that workout inside one transaction.

5. **Destroying raw fidelity with custom volume rules.** Keep Hevy's raw `weight_kg` untouched. Put dumbbell-per-hand or bodyweight conventions in analytics views.

6. **Too-large page sizes.** Use `pageSize=10`, especially for `/v1/workouts/events`.

7. **No sync cursor.** Always store the last event cursor/timestamp in `hevy_sync_state`. Without this, pollers either miss changes or refetch forever.

8. **Advancing cursor before commit.** Only update `workouts_events_since` in the same DB transaction after event processing succeeds.

9. **No second-run idempotency test.** After setup, run incremental sync twice. The second run should be quiet/zero-change.

10. **Leaking API keys.** Never echo env files, curl commands with expanded variables, or logs containing headers.

## Verification Checklist

- [ ] `GET /v1/user/info` succeeds with `api-key` header.
- [ ] Schema exists under `fitness` schema.
- [ ] Initial backfill inserts workouts, exercises, and sets.
- [ ] `/v1/workouts/count` roughly matches non-deleted workout count after full backfill.
- [ ] `/v1/workouts/events` sync runs without 400; page size is 10.
- [ ] Running event sync twice is idempotent.
- [ ] Deleted workout events mark rows deleted instead of silently disappearing.
- [ ] Raw JSON is stored for audit.
- [ ] Analytics view returns top exercises without mutating raw Hevy values.
- [ ] Scheduler/timer is enabled and has a recent successful run.
- [ ] Secrets are in env/secret manager and absent from git/logs/chat.

## Agent Response Contract

When reporting setup completion to the user, keep it short:

```text
Done.
- DB: connected
- Hevy auth: OK
- Backfill: <n> workouts / <n> sets
- Incremental sync: OK, second run zero-change
- Scheduler: <cron/systemd/Hermes>, next run <time>
- Files: <paths>
```

If something fails, report the failing layer only:

```text
Blocked: Hevy auth failed with HTTP 401/403.
Likely fix: regenerate Hevy API key from Hevy web app developer settings and update HEVY_API_KEY.
```

No backend log dumps unless asked.
