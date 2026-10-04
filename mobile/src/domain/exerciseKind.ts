/** What an exercise logs: weight/reps (default) or minutes/max heart rate. */
export type ExerciseKind = 'strength' | 'cardio';

/** Unknown/legacy values read as strength, matching the column default. */
export function exerciseKindFromRaw(raw: string | null | undefined): ExerciseKind {
  return raw === 'cardio' ? 'cardio' : 'strength';
}
