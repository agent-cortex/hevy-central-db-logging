# Hevy Central DB Logging Skill

A cross-client Agent Skill for setting up an open-source Hevy App fitness logging pipeline from the Hevy API to a central PostgreSQL-compatible database.

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

## Install as an Agent Skill

Agent Skills expect a folder containing `SKILL.md`, and the folder name must match the `name` field: `hevy-central-db-logging`.

For VS Code / Copilot / generic Agent Skills clients:

```bash
mkdir -p .agents/skills
git clone https://github.com/agent-cortex/hevy-central-db-logging.git .agents/skills/hevy-central-db-logging
```

Then open the project and run `/skills` in agent mode to confirm `hevy-central-db-logging` appears.

## Install in Hermes

```bash
hermes skills install https://raw.githubusercontent.com/agent-cortex/hevy-central-db-logging/main/SKILL.md
```

Or copy the full folder manually:

```bash
mkdir -p ~/.hermes/skills/fitness/hevy-central-db-logging
cp -R SKILL.md references assets templates ~/.hermes/skills/fitness/hevy-central-db-logging/
```

## Use

Load the skill and ask:

```text
Set up Hevy App sync to my central Postgres DB.
```

For delegating to another agent, use:

```text
assets/agent-prompt.md
```

## Requirements

- Hevy Pro API access
- Hevy API key from the Hevy web app developer settings
- PostgreSQL-compatible database: local Postgres, Supabase, Neon, Railway, etc.
- Python stack recommended by the skill: `httpx`, `psycopg[binary]`, `python-dotenv`

## Security note

Fitness data is sensitive. Do not commit `.env`, database URLs, API keys, workout exports, raw personal logs, or generated JSONL data.

## Files

- `SKILL.md` — main skill, kept concise for progressive disclosure
- `references/hevy-openapi-endpoints.md` — endpoint reference extracted from Hevy Swagger docs
- `references/postgres-schema.sql` — schema and analytics view
- `references/hevy-sync-implementation.md` — starter sync script
- `references/verification-queries.sql` — SQL checks after setup
- `assets/agent-prompt.md` — copy/paste setup prompt for another agent
- `templates/agent-prompt.md` — same prompt retained for Hermes template compatibility

## License

MIT
