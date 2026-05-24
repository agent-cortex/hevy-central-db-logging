# Hevy API Endpoint Reference

Source: `https://api.hevyapp.com/docs/` Swagger/OpenAPI as checked during skill creation.

## Auth

Every documented endpoint uses this required header:

```text
api-key: <uuid API key>
```

The key is available to Hevy Pro users from the Hevy web app developer settings.

## Endpoints

### User

- `GET /v1/user/info`
  - Summary: Get user info.
  - Responses: `200`, `404`.
  - Store: `hevy_users`.

### Workouts

- `GET /v1/workouts`
  - Summary: Get a paginated list of workouts.
  - Query params: `page` default `1`, `pageSize` default `5`; use `10` max-safe for sync.
  - Responses: `200`, `400`.
  - Store: `hevy_workouts`, `hevy_exercises`, `hevy_sets`.

- `POST /v1/workouts`
  - Summary: Create a new workout.
  - Body: `{ "workout": { ... } }` using `PostWorkoutsRequestBody`.
  - Responses: `201`, `400`.
  - Use only for explicit bidirectional sync.

- `GET /v1/workouts/count`
  - Summary: Get total number of workouts on the account.
  - Responses: `200`.
  - Use for backfill completeness checks.

- `GET /v1/workouts/events`
  - Summary: Retrieve paged workout update/delete events since a date.
  - Query params: `since` default `1970-01-01T00:00:00Z`, `page`, `pageSize`.
  - Responses: `200`, `500`.
  - Store updated workouts normally; store deleted events in `hevy_deleted_workouts` and mark `hevy_workouts.deleted_at`.
  - Operational rule: use `pageSize=10`; larger values have been observed to 400.

- `GET /v1/workouts/{workoutId}`
  - Summary: Get one workout's complete details.
  - Responses: `200`, `404`.
  - Use for repair/spot verification.

- `PUT /v1/workouts/{workoutId}`
  - Summary: Update an existing workout.
  - Body: same shape as `POST /v1/workouts`.
  - Responses: `200`, `400`.
  - Avoid unless explicit bidirectional sync is requested.

### Routines

- `GET /v1/routines`
  - Query params: `page`, `pageSize`.
  - Responses: `200`, `400`.

- `POST /v1/routines`
  - Body: `{ "routine": { ... } }` using `PostRoutinesRequestBody`.
  - Responses: `201`, `400`, `403`.

- `GET /v1/routines/{routineId}`
  - Responses: `200`, `400`.

- `PUT /v1/routines/{routineId}`
  - Body: `{ "routine": { ... } }` using `PutRoutinesRequestBody`.
  - Responses: `200`, `400`, `404`.

### Exercise templates

- `GET /v1/exercise_templates`
  - Summary: Get a paginated list of exercise templates available on the account.
  - Query params: `page`, `pageSize`.
  - Responses: `200`, `400`.

- `POST /v1/exercise_templates`
  - Summary: Create a custom exercise template.
  - Body: `{ "exercise": { ... } }` using `CreateCustomExerciseRequestBody`.
  - Responses: `200`, `400`, `403`.

- `GET /v1/exercise_templates/{exerciseTemplateId}`
  - Responses: `200`, `404`.

- `GET /v1/exercise_history/{exerciseTemplateId}`
  - Query params: optional `start_date`, `end_date` as date-time.
  - Responses: `200`, `400`.
  - Use for targeted repair/history checks, not as the main sync source.

### Routine folders

- `GET /v1/routine_folders`
  - Query params: `page`, `pageSize`.
  - Responses: `200`, `400`.

- `POST /v1/routine_folders`
  - Body: `{ "routine_folder": { ... } }`.
  - Responses: `201`, `400`.

- `GET /v1/routine_folders/{folderId}`
  - Responses: `200`, `404`.

### Body measurements

- `GET /v1/body_measurements`
  - Query params: `page`, `pageSize` default `10`.
  - Responses: `200`, `400`, `404`.

- `POST /v1/body_measurements`
  - Body: `BodyMeasurement`; `date` is required.
  - Responses: `200`, `400`, `409`.
  - `409` means an entry already exists for that date.

- `GET /v1/body_measurements/{date}`
  - Path date format: `YYYY-MM-DD`.
  - Responses: `200`, `404`.

- `PUT /v1/body_measurements/{date}`
  - Body: `PutBodyMeasurement`.
  - Responses: `200`, `400`, `404`.
  - Warning: all fields are overwritten; omitted fields become null.

## Main response object fields

### Workout

- `id`, `title`, `routine_id`, `description`
- `start_time`, `end_time`, `updated_at`, `created_at`
- `exercises[]`

### Exercise

- `index`, `title`, `notes`
- `exercise_template_id`
- `supersets_id`/`superset_id`
- `sets[]`

### Set

- `index`
- `type`: `normal`, `warmup`, `dropset`, `failure`
- `weight_kg`, `reps`
- `distance_meters`, `duration_seconds`
- `rpe`
- `custom_metric`

### Event

- Updated event: `{ "type": "updated", "workout": Workout }`
- Deleted event: `{ "type": "deleted", "id": "...", "deleted_at": "..." }`

## Recommended sync priority

1. `GET /v1/user/info`
2. `GET /v1/workouts` for initial backfill
3. `GET /v1/workouts/events` for incremental sync
4. `GET /v1/exercise_templates` for metadata
5. `GET /v1/body_measurements` for body metrics
6. Optional: routines/folders/history
7. Avoid POST/PUT unless explicitly building two-way sync
