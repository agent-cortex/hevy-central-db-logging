SELECT count(*) AS workouts FROM fitness.hevy_workouts WHERE deleted_at IS NULL;
SELECT count(*) AS exercises FROM fitness.hevy_exercises;
SELECT count(*) AS sets FROM fitness.hevy_sets;
SELECT max(start_time) AS latest_workout FROM fitness.hevy_workouts WHERE deleted_at IS NULL;

SELECT
  exercise_title,
  count(DISTINCT workout_id) AS sessions,
  count(*) AS sets,
  sum(convention_volume_kg) AS volume_kg
FROM fitness.hevy_set_analytics
GROUP BY exercise_title
ORDER BY volume_kg DESC
LIMIT 20;

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

SELECT * FROM fitness.hevy_sync_state ORDER BY updated_at DESC;
SELECT event_type, count(*) FROM fitness.hevy_raw_events GROUP BY event_type;
