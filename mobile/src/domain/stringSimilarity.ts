/**
 * Levenshtein-distance-based similarity in `[0, 1]` (1 = identical, 0 = nothing in common). Two empty strings
 * are treated as identical.
 */
export function similarityRatio(a: string, b: string): number {
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1;
  return 1 - levenshteinDistance(a, b) / maxLen;
}

function levenshteinDistance(a: string, b: string): number {
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  let previousRow = Array.from({ length: b.length + 1 }, (_, i) => i);
  let currentRow = new Array<number>(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    currentRow[0] = i;
    for (let j = 1; j <= b.length; j++) {
      currentRow[j] =
        a[i - 1] === b[j - 1] ? previousRow[j - 1] : 1 + Math.min(previousRow[j - 1], previousRow[j], currentRow[j - 1]);
    }
    [previousRow, currentRow] = [currentRow, previousRow];
  }
  return previousRow[b.length];
}
