# Agent Prompt: Set Up Hevy -> Central DB Fitness Logging

Copy/paste this prompt into an agent that has file, terminal, and web tools.

```text
Set up a complete Hevy App fitness logging pipeline into a central PostgreSQL-compatible DB.

Requirements:
- Use Hevy API docs at https://api.hevyapp.com/docs/ as source of truth.
- Use `api-key` header auth for Hevy.
- Never print or commit secrets.
- Target DB is Postgres-compatible via `DATABASE_URL`.
- Create normalized tables for workouts, exercises, sets, deleted workouts, raw events, sync state, users, exercise templates, and body measurements.
- Preserve raw JSON in `jsonb` columns.
- Implement initial backfill via `GET /v1/workouts`.
- Implement incremental sync via `GET /v1/workouts/events?since=...`.
- Use pageSize=10.
- Handle updated and deleted workout events idempotently.
- On workout update, replace child exercise/set rows for that workout inside one transaction.
- Keep raw Hevy values untouched; put dumbbell/bodyweight volume conventions in an analytics view, not the raw tables.
- Add a CLI script with `--init-user`, `--backfill`, `--events`, and `--json`.
- Add `.env.example`, README setup instructions, and a scheduler option (cron/systemd/Hermes no-agent cron).
- Verify by running user-info, schema migration, limited backfill, full/partial backfill, events sync twice, and SQL counts.

Final response format:
Done/Blocked.
- Files changed
- DB migration status
- Hevy auth status
- Backfill count
- Incremental sync result
- Scheduler status
- Verification queries passed/failed
Do not dump logs unless asked.
```
