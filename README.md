# Hevy Central DB Logging Skill

A Hermes Agent skill for setting up an open-source Hevy App fitness logging pipeline from the Hevy API to a central PostgreSQL-compatible database.

## What this skill covers

- Hevy API endpoint map from `https://api.hevyapp.com/docs/`
- `api-key` header auth
- Initial backfill via `GET /v1/workouts`
- Incremental sync via `GET /v1/workouts/events`
- Update/delete handling
- Normalized Postgres schema for workouts, exercises, sets, templates, body measurements, raw events, and sync state
- Optional webhook receiver pattern
- Cron/systemd/Hermes no-agent scheduling
- Verification SQL and agent completion contract

## Install in Hermes

```bash
hermes skills install https://raw.githubusercontent.com/agent-cortex/hevy-central-db-logging-skill/main/SKILL.md
```

Or copy this repo's `SKILL.md` directory into your Hermes skills folder:

```bash
mkdir -p ~/.hermes/skills/fitness/hevy-central-db-logging
cp -R SKILL.md references templates ~/.hermes/skills/fitness/hevy-central-db-logging/
```

## Use

Load the skill in Hermes:

```text
/skill hevy-central-db-logging
```

Then ask:

```text
Set up Hevy App sync to my central Postgres DB.
```

For delegating to another agent, use:

```text
templates/agent-prompt.md
```

## Requirements

- Hevy Pro API access
- Hevy API key from the Hevy web app developer settings
- PostgreSQL-compatible database: local Postgres, Supabase, Neon, Railway, etc.
- Python stack recommended by the skill: `httpx`, `psycopg[binary]`, `python-dotenv`

## Security note

Fitness data is sensitive. Do not commit `.env`, database URLs, API keys, workout exports, or raw personal logs.

## Files

- `SKILL.md` — main Hermes skill
- `references/hevy-openapi-endpoints.md` — endpoint reference extracted from Hevy Swagger docs
- `templates/agent-prompt.md` — copy/paste setup prompt for another agent

## License

MIT
