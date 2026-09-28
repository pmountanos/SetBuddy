package net.mountanos.setbuddy.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.uuid.Uuid

class VolumeCalculatorTests {
    @Test
    fun totalsSets() {
        val total = VolumeCalculator.totalVolume(
            listOf(VolumeCalculator.Set(100.0, 5, false), VolumeCalculator.Set(50.0, 10, false))
        )
        assertEquals(100.0 * 5 + 50.0 * 10, total)
    }

    @Test
    fun negativeWeightTreatedAsZero() {
        assertEquals(0.0, VolumeCalculator.setVolume(weight = -50.0, reps = 10))
    }

    @Test
    fun zeroReps() {
        assertEquals(0.0, VolumeCalculator.setVolume(weight = 200.0, reps = 0))
    }

    @Test
    fun perSideDoublesWork() {
        assertEquals(500.0, VolumeCalculator.setVolume(weight = 50.0, reps = 10, repsArePerSide = false))
        assertEquals(1_000.0, VolumeCalculator.setVolume(weight = 50.0, reps = 10, repsArePerSide = true))
    }
}

class TodayScheduleResolverTests {
    @Test
    fun dayNotScheduledWhenEmpty() {
        val schedule = ProgramCalendarSchedule()
        val status = TodayScheduleResolver.status(
            today = CalendarDate(2025, 1, 18),
            schedule = schedule,
            workoutNames = emptyMap(),
        )
        assertEquals(TodayScheduleStatus.DayNotScheduled, status)
    }

    @Test
    fun workoutAndRest() {
        val workoutId = Uuid.random()
        val today = CalendarDate(2025, 1, 18)
        val schedule = ProgramCalendarSchedule()
        schedule.set(ScheduledDayKind.Workout(workoutId), today)

        val s1 = TodayScheduleResolver.status(today, schedule, mapOf(workoutId to "Push"))
        assertEquals(TodayScheduleStatus.WorkoutDay(workoutId, "Push"), s1)

        schedule.set(ScheduledDayKind.Rest, today)
        val s2 = TodayScheduleResolver.status(today, schedule, emptyMap())
        assertEquals(TodayScheduleStatus.RestDay, s2)
    }
}

class WorkoutTemplateDisplaySortTests {
    @Test
    fun ordersPushPullLegsCycle() {
        val names = listOf("Legs 2", "Push 1", "Pull 2", "Pull 1", "Push 2", "Legs 1", "ZZ Other")
        val sorted = names.sortedWith(WorkoutTemplateDisplaySort.comparator)
        assertEquals(listOf("Push 1", "Pull 1", "Legs 1", "Push 2", "Pull 2", "Legs 2", "ZZ Other"), sorted)
    }
}

class StringSimilarityTests {
    @Test
    fun identicalStringsScoreOne() {
        assertEquals(1.0, StringSimilarity.ratio("bench press", "bench press"))
    }

    @Test
    fun completelyDifferentStringsScoreLow() {
        assertTrue(StringSimilarity.ratio("bench press", "squat") < 0.3)
    }

    @Test
    fun closeTypoScoresAboveFuzzyThreshold() {
        // Missing one letter out of 12 ("Bench Press" -> "Bench Pres").
        assertTrue(StringSimilarity.ratio("bench press", "bench pres") >= ExerciseCarryoverMatcher.FUZZY_THRESHOLD)
    }
}

class ExerciseCarryoverMatcherTests {
    @Test
    fun autoMatchesExactNamesCaseInsensitively() {
        val old = listOf(ExerciseCarryoverMatcher.ExistingExercise(Uuid.random(), "Bench Press"))
        val cycle = listOf(
            ImportedCycleDay("Push 1", false, listOf(ImportedCycleExercise("  bench press  ")))
        )
        val result = ExerciseCarryoverMatcher.match(old, cycle)
        val ref = ImportExerciseRef("Push 1", "  bench press  ")
        assertEquals(old[0].id, result.autoCarryover[ref])
        assertTrue(result.suggestions.isEmpty())
    }

    @Test
    fun suggestsCloseNonExactMatches() {
        val old = listOf(ExerciseCarryoverMatcher.ExistingExercise(Uuid.random(), "Bench Press"))
        val cycle = listOf(
            ImportedCycleDay("Push 1", false, listOf(ImportedCycleExercise("Bench Pres")))
        )
        val result = ExerciseCarryoverMatcher.match(old, cycle)
        assertTrue(result.autoCarryover.isEmpty())
        assertEquals(1, result.suggestions.size)
        assertEquals(old[0].id, result.suggestions.first().oldExerciseId)
        assertEquals("Bench Press", result.suggestions.first().oldExerciseName)
        assertEquals("Bench Pres", result.suggestions.first().newExercise.exerciseName)
    }

    @Test
    fun ignoresUnrelatedNames() {
        val old = listOf(ExerciseCarryoverMatcher.ExistingExercise(Uuid.random(), "Bench Press"))
        val cycle = listOf(
            ImportedCycleDay("Legs 1", false, listOf(ImportedCycleExercise("Back Squat")))
        )
        val result = ExerciseCarryoverMatcher.match(old, cycle)
        assertTrue(result.autoCarryover.isEmpty())
        assertTrue(result.suggestions.isEmpty())
    }

    @Test
    fun greedilyAssignsBestPairsWithoutDoubleClaiming() {
        val benchId = Uuid.random()
        val machineId = Uuid.random()
        val old = listOf(
            ExerciseCarryoverMatcher.ExistingExercise(benchId, "Bench Press"),
            ExerciseCarryoverMatcher.ExistingExercise(machineId, "Bench Press Machine"),
        )
        val cycle = listOf(
            ImportedCycleDay(
                "Push 1", false, listOf(
                    ImportedCycleExercise("Bench Pres"),
                    ImportedCycleExercise("Bench Press Machin"),
                )
            )
        )
        val result = ExerciseCarryoverMatcher.match(old, cycle)
        assertEquals(2, result.suggestions.size)
        val byNewName = result.suggestions.associate { it.newExercise.exerciseName to it.oldExerciseId }
        assertEquals(benchId, byNewName["Bench Pres"])
        assertEquals(machineId, byNewName["Bench Press Machin"])
    }
}
