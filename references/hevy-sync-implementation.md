# Hevy Sync Python Implementation

Use this as the starting point for `hevy_sync.py`. It implements:

- `--init-user`
- `--backfill`
- `--events`
- `--max-pages`
- `--json`

Dependencies:

```bash
pip install httpx psycopg[binary] python-dotenv
```

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
