/** Orders workout templates by name: Push 1, Pull 1, Legs 1, Push 2, Pull 2, Legs 2, then others alphabetically. */
const CANONICAL = ['Push 1', 'Pull 1', 'Legs 1', 'Push 2', 'Pull 2', 'Legs 2'];

const normalized = (name: string) => name.trim().replace(/ /g, '').toLowerCase();

/** Lower rank sorts earlier. Known cycle names first; everything else after. */
function rank(name: string): number {
  const norm = normalized(name);
  const exact = CANONICAL.findIndex((ref) => norm === normalized(ref));
  if (exact >= 0) return exact;
  const loose = CANONICAL.findIndex(
    (ref) => norm.startsWith(normalized(ref)) || name.toLowerCase().includes(ref.toLowerCase()),
  );
  return loose >= 0 ? loose : 1000;
}

export function compareWorkoutNames(a: string, b: string): number {
  return rank(a) - rank(b) || a.localeCompare(b, undefined, { sensitivity: 'base' });
}

/**
 * Display/picker order: `sortOrder` (spreadsheet cycle position, or append order in-app) first, falling back to
 * the naming heuristic on ties (e.g. every workout still at the default 0 from before the column existed).
 */
export function compareWorkouts(a: { name: string; sortOrder: number }, b: { name: string; sortOrder: number }): number {
  return a.sortOrder - b.sortOrder || compareWorkoutNames(a.name, b.name);
}
