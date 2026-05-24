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
