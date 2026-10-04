package net.mountanos.setbuddy.android

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import net.mountanos.setbuddy.android.importxlsx.ProgramXlsxImporter
import net.mountanos.setbuddy.android.importxlsx.ProgramXlsxParser
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseCarryoverMatcher
import net.mountanos.setbuddy.domain.ExerciseKind
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Same real workbook the iOS tests use (`Set BuddyTests/Fixtures/Set Buddy-4.xlsx`) — mirrors their expectations. */
class SetBuddy4FixtureImportTests {
    private val fixture = File("../Set BuddyTests/Fixtures/Set Buddy-4.xlsx")

    private fun freshDatabase(): SetBuddyDatabase {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        driver.execute(null, "PRAGMA foreign_keys=ON;", 0)
        SetBuddyDatabase.Schema.create(driver)
        return SetBuddyDatabase(driver)
    }

    @Test
    fun parsesCardioSectionsAndWholeCardioDays() {
        val cycle = ProgramXlsxParser.parse(fixture)

        // "Push 1": 8 strength exercises, then a trailing "Cardio" set.
        val push1 = cycle.first { it.sheetName == "Push 1" }
        assertFalse(push1.isRestDay)
        assertEquals(9, push1.exercises.size)
        assertTrue(push1.exercises.dropLast(1).all { it.kind == ExerciseKind.Strength })
        assertEquals(ExerciseKind.Cardio, push1.exercises.last().kind)
        assertEquals("Cardio", push1.exercises.last().name)

        // "Cardio 1": a whole cardio day — not a rest day despite having no strength rows.
        val cardio1 = cycle.first { it.sheetName == "Cardio 1" }
        assertFalse(cardio1.isRestDay)
        assertEquals(listOf("Cardio"), cardio1.exercises.map { it.name })
        assertEquals(ExerciseKind.Cardio, cardio1.exercises.single().kind)

        // "Rest 1": genuinely empty, still a rest day.
        assertTrue(cycle.first { it.sheetName == "Rest 1" }.isRestDay)
    }

    @Test
    fun strengthRowsStopAtTheCardioSectionHeader() {
        val cells = mapOf(
            "A1" to "Excercise_Name", "B1" to "Per side", "C1" to "Notes",
            "A2" to "Bench Press", "B2" to "x",
            "A3" to "Barbell Row",
            "B4" to "Minutes", "C4" to "Peak HR",
            "A5" to "Cardio",
        )
        assertEquals(4, ProgramXlsxParser.cardioSectionHeaderRow(cells))
        val exercises = ProgramXlsxParser.exercisesFromSheet(cells)
        assertEquals(listOf("Bench Press", "Barbell Row", "Cardio"), exercises.map { it.name })
        assertEquals(
            listOf(ExerciseKind.Strength, ExerciseKind.Strength, ExerciseKind.Cardio),
            exercises.map { it.kind },
        )
        assertTrue(exercises.first().repsArePerSide)
    }

    @Test
    fun importKeepsSpreadsheetCycleOrderAndGivesCardioOneSet() {
        val db = freshDatabase()
        ProgramXlsxImporter(db).importReplacingStore(
            cycle = ProgramXlsxParser.parse(fixture),
            programName = "Cardio Import",
            startDate = CalendarDate(2026, 1, 1),
            horizonDays = 12,
        )

        val outline = ProgramOutlineRepository(db).activeProgramOutline()!!
        assertEquals(
            listOf(
                "Push 1", "Cardio 1", "Pull 1", "Cardio 2", "Legs 1",
                "Push 2", "Cardio 3", "Pull 2", "Cardio 4", "Legs 2",
            ),
            outline.workouts.map { it.name },
        )

        val push1 = outline.workouts.first { it.name == "Push 1" }.exercises
        assertTrue(push1.dropLast(1).all { it.kind == ExerciseKind.Strength && it.setCount == 4 })
        assertEquals(ExerciseKind.Cardio, push1.last().kind)
        assertEquals(1, push1.last().setCount)

        val cardio1 = outline.workouts.first { it.name == "Cardio 1" }.exercises
        assertTrue(cardio1.all { it.kind == ExerciseKind.Cardio && it.setCount == 1 })
    }

    /**
     * The workbook lists one exercise twice on a sheet. Re-importing over a program that already has it carries
     * the old id onto both rows — which must not fail the import (or leave the store with no program).
     */
    @Test
    fun reimportingOverItselfWithCarryoverSucceedsDespiteARepeatedExerciseName() {
        val db = freshDatabase()
        val importer = ProgramXlsxImporter(db)
        val programs = ProgramRepository(db)
        val cycle = ProgramXlsxParser.parse(fixture)
        val start = CalendarDate(2026, 1, 1)
        importer.importReplacingStore(cycle, "First", start)
        val exerciseCount = ProgramOutlineRepository(db).activeProgramOutline()!!.workouts.sumOf { it.exercises.size }

        val match = ExerciseCarryoverMatcher.match(programs.existingExercisesForCarryover(), cycle)
        assertTrue(match.autoCarryover.isNotEmpty())
        importer.importReplacingStore(cycle, "Second", start, exerciseCarryover = match.autoCarryover)

        val outline = ProgramOutlineRepository(db).activeProgramOutline()!!
        assertEquals("Second", outline.programName)
        assertEquals(exerciseCount, outline.workouts.sumOf { it.exercises.size })
    }
}
