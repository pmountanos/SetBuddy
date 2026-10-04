/** Total work for one set. When `repsArePerSide` is true, reps are performed on each side (e.g. dumbbell), so volume doubles. */
export function setVolume(weight: number, reps: number, repsArePerSide = false): number {
  const base = Math.max(0, weight) * Math.max(0, reps);
  return repsArePerSide ? base * 2 : base;
}

export function totalVolume(sets: Iterable<{ weight: number; reps: number; repsArePerSide: boolean }>): number {
  let total = 0;
  for (const s of sets) total += setVolume(s.weight, s.reps, s.repsArePerSide);
  return total;
}
