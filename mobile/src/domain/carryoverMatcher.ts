import type { ExerciseKind } from './exerciseKind';
import { similarityRatio } from './stringSimilarity';

/**
 * Identifies one exercise in a freshly parsed workbook, before it's persisted — used as the key for carrying an
 * existing exercise's id (and therefore its logged history) onto the matching new one.
 */
export interface ImportExerciseRef {
  workoutSheetName: string;
  exerciseName: string;
}

/** Map key for an {@link ImportExerciseRef} (objects can't key a `Map` by value). */
export const refKey = (ref: ImportExerciseRef): string => `${ref.workoutSheetName}\u0000${ref.exerciseName}`;

/** One exercise entry as it appears in a freshly parsed workbook day. */
export interface ImportedCycleExercise {
  name: string;
  note?: string | null;
  repsArePerSide?: boolean;
  kind?: ExerciseKind;
}

/** One day of a freshly parsed workbook cycle. */
export interface ImportedCycleDay {
  sheetName: string;
  isRestDay: boolean;
  exercises: ImportedCycleExercise[];
}

export interface ExistingExercise {
  id: string;
  name: string;
}

/** A close-but-not-exact name match, offered to the user to confirm before it's applied. */
export interface CarryoverSuggestion {
  newExercise: ImportExerciseRef;
  oldExerciseId: string;
  oldExerciseName: string;
}

export interface CarryoverMatch {
  /** Exact (case/whitespace-insensitive) name matches — applied without asking. Keyed by {@link refKey}. */
  autoCarryover: Map<string, string>;
  /** Close matches (>= {@link FUZZY_THRESHOLD}, < 1.0) — shown to the user, in workbook order, to confirm or reject. */
  suggestions: CarryoverSuggestion[];
}

/** Below this similarity, two names are treated as unrelated exercises. */
export const FUZZY_THRESHOLD = 0.75;

const normalized = (s: string) => s.trim().toLowerCase();

/**
 * Matches exercises from a program about to be replaced against a newly parsed workbook, by name, so a re-import
 * doesn't sever the "reference weight" trail shown while logging (reference lookups key off exercise id, which is
 * otherwise regenerated fresh on every import).
 *
 * @param existing Exercises from the program about to be replaced (pass empty if there is none).
 * @param newCycle The freshly parsed workbook.
 */
export function matchCarryover(existing: ExistingExercise[], newCycle: ImportedCycleDay[]): CarryoverMatch {
  const newRefs: ImportExerciseRef[] = newCycle
    .filter((day) => !day.isRestDay)
    .flatMap((day) => day.exercises.map((ex) => ({ workoutSheetName: day.sheetName, exerciseName: ex.name })));

  const remainingOld = [...existing];
  const autoCarryover = new Map<string, string>();

  // Pass 1: exact matches, greedy in workbook order — each old exercise can be claimed at most once.
  const unmatchedNew: ImportExerciseRef[] = [];
  for (const ref of newRefs) {
    const index = remainingOld.findIndex((old) => normalized(old.name) === normalized(ref.exerciseName));
    if (index >= 0) {
      autoCarryover.set(refKey(ref), remainingOld[index].id);
      remainingOld.splice(index, 1);
    } else {
      unmatchedNew.push(ref);
    }
  }

  // Pass 2: close matches — score every remaining pair, then greedily assign highest-similarity pairs first
  // so one old exercise isn't suggested for two different new ones.
  const candidates: { newIndex: number; oldIndex: number; score: number }[] = [];
  unmatchedNew.forEach((ref, newIndex) => {
    remainingOld.forEach((old, oldIndex) => {
      const score = similarityRatio(normalized(ref.exerciseName), normalized(old.name));
      if (score >= FUZZY_THRESHOLD) candidates.push({ newIndex, oldIndex, score });
    });
  });
  candidates.sort((a, b) => b.score - a.score);

  const claimedOld = new Set<number>();
  const claimedNew = new Set<number>();
  const suggestions: CarryoverSuggestion[] = [];
  for (const candidate of candidates) {
    if (claimedOld.has(candidate.oldIndex) || claimedNew.has(candidate.newIndex)) continue;
    claimedOld.add(candidate.oldIndex);
    claimedNew.add(candidate.newIndex);
    const old = remainingOld[candidate.oldIndex];
    suggestions.push({ newExercise: unmatchedNew[candidate.newIndex], oldExerciseId: old.id, oldExerciseName: old.name });
  }

  // Present in workbook order rather than by-score. A workbook can repeat the same exercise name on one sheet
  // (e.g. a copy-paste duplicate); keep the first occurrence's position.
  const order = new Map<string, number>();
  newRefs.forEach((ref, i) => {
    if (!order.has(refKey(ref))) order.set(refKey(ref), i);
  });
  suggestions.sort((a, b) => (order.get(refKey(a.newExercise)) ?? 0) - (order.get(refKey(b.newExercise)) ?? 0));

  return { autoCarryover, suggestions };
}
