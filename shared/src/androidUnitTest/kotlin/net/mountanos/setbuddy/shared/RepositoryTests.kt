package net.mountanos.setbuddy.shared

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseKind
import net.mountanos.setbuddy.shared.data.HistoryRepository
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import net.mountanos.setbuddy.shared.data.SchedulePickerValue
import net.mountanos.setbuddy.shared.data.WorkoutSessionRepository
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.uuid.Uuid

private fun inMemoryDriver(): SqlDriver =
    JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { it.execute(null, "PRAGMA foreign_keys=ON;", 0) }

private fun freshDatabase(): SetBuddyDatabase {
    val driver = inMemoryDriver()
    SetBuddyDatabase.Schema.create(driver)
    return SetBuddyDatabase(driver)
}

class SchemaMigrationTests {
    /** The schema as shipped in versionCode 2 (before cardio / workout sortOrder). */
    private val v1Schema = listOf(
        "CREATE TABLE Program (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, createdAtRowOrder INTEGER NOT NULL)",
        "CREATE TABLE Workout (id TEXT NOT NULL PRIMARY KEY, programId TEXT NOT NULL, name TEXT NOT NULL, " +
            "FOREIGN KEY (programId) REFERENCES Program(id) ON DELETE CASCADE)",
        "CREATE TABLE ScheduleEntry (id TEXT NOT NULL PRIMARY KEY, programId TEXT NOT NULL, year INTEGER NOT NULL, " +
            "month INTEGER NOT NULL, day INTEGER NOT NULL, isRestDay INTEGER NOT NULL, workoutId TEXT, " +
            "FOREIGN KEY (programId) REFERENCES Program(id) ON DELETE CASCADE)",
        "CREATE UNIQUE INDEX ScheduleEntry_program_date ON ScheduleEntry(programId, year, month, day)",
        "CREATE TABLE Exercise (id TEXT NOT NULL PRIMARY KEY, workoutId TEXT NOT NULL, name TEXT NOT NULL, " +
            "sortOrder INTEGER NOT NULL, setCount INTEGER NOT NULL, note TEXT, repsArePerSide INTEGER NOT NULL DEFAULT 0, " +
            "FOREIGN KEY (workoutId) REFERENCES Workout(id) ON DELETE CASCADE)",
        "CREATE TABLE WorkoutSession (id TEXT NOT NULL PRIMARY KEY, workoutTemplateId TEXT NOT NULL, " +
            "scheduleYear INTEGER NOT NULL, scheduleMonth INTEGER NOT NULL, scheduleDay INTEGER NOT NULL, " +
            "isComplete INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL, completedAt INTEGER, " +
            "workoutTitleSnapshot TEXT, sessionNote TEXT)",
        "CREATE TABLE LoggedSet (id TEXT NOT NULL PRIMARY KEY, sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL, " +
            "setIndex INTEGER NOT NULL, weight REAL NOT NULL DEFAULT 0, reps INTEGER NOT NULL DEFAULT 0, " +
            "seededFromCarryover INTEGER NOT NULL DEFAULT 0, userEditedValues INTEGER NOT NULL DEFAULT 0, " +
            "repsArePerSide INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (sessionId) REFERENCES WorkoutSession(id) ON DELETE CASCADE)",
        "CREATE UNIQUE INDEX LoggedSet_session_exercise_index ON LoggedSet(sessionId, exerciseId, setIndex)",
    )

    @Test
    fun existingInstallUpgradesWithItsDataIntact() {
        val driver = inMemoryDriver()
        v1Schema.forEach { driver.execute(null, it, 0) }
        val programId = Uuid.random().toString()
        val workoutId = Uuid.random().toString()
        val exerciseId = Uuid.random().toString()
        val sessionId = Uuid.random().toString()
        listOf(
            "INSERT INTO Program VALUES ('$programId', 'Old program', 1)",
            "INSERT INTO Workout VALUES ('$workoutId', '$programId', 'Push 1')",
            "INSERT INTO Exercise VALUES ('$exerciseId', '$workoutId', 'Bench Press', 0, 4, NULL, 0)",
            "INSERT INTO WorkoutSession VALUES ('$sessionId', '$workoutId', 2026, 9, 16, 1, 1, 2, 'Push 1', NULL)",
            "INSERT INTO LoggedSet VALUES ('${Uuid.random()}', '$sessionId', '$exerciseId', 0, 100.0, 5, 0, 1, 0)",
        ).forEach { driver.execute(null, it, 0) }

        assertEquals(2, SetBuddyDatabase.Schema.version)
        SetBuddyDatabase.Schema.migrate(driver, 1, SetBuddyDatabase.Schema.version)
        val db = SetBuddyDatabase(driver)

        val exercise = ProgramOutlineRepository(db).activeProgramOutline()!!.workouts.single().exercises.single()
        assertEquals("Bench Press", exercise.name)
        assertEquals(ExerciseKind.Strength, exercise.kind)

        val line = HistoryRepository(db).sessionDetail(Uuid.parse(sessionId))!!.exerciseGroups.single().sets.single()
        assertEquals(ExerciseKind.Strength, line.kind)
        assertEquals(500.0, line.volume)
        assertEquals(0.0, line.cardioMinutes)

        // New-column writes work on the migrated tables.
        ProgramRepository(db).setExerciseKind(Uuid.parse(exerciseId), ExerciseKind.Cardio)
        ProgramRepository(db).addWorkout("Cardio 1")
    }
}

class ScheduleCascadeTests {
    private val db = freshDatabase()
    private val programs = ProgramRepository(db)
    private val start = CalendarDate(2026, 1, 1)
    private val rest = SchedulePickerValue.Rest
    private lateinit var a: SchedulePickerValue
    private lateinit var b: SchedulePickerValue
    private lateinit var c: SchedulePickerValue

    private fun setUp(vararg days: SchedulePickerValue) {
        days.forEachIndexed { offset, value -> programs.setScheduleDay(start.addingDays(offset), value) }
    }

    private fun schedule(days: Int): List<SchedulePickerValue> {
        val entries = db.setBuddyQueries.selectScheduleForProgram(programs.activeProgram()!!.id).executeAsList()
            .associateBy { CalendarDate(it.year.toInt(), it.month.toInt(), it.day.toInt()) }
        return (0 until days).map { offset ->
            val entry = entries[start.addingDays(offset)]
            val workoutId = entry?.workoutId
            if (entry == null || entry.isRestDay == 1L || workoutId == null) rest
            else SchedulePickerValue.AssignedWorkout(Uuid.parse(workoutId))
        }
    }

    init {
        programs.createFirstProgram("Test")
        a = SchedulePickerValue.AssignedWorkout(Uuid.parse(programs.addWorkout("A").id))
        b = SchedulePickerValue.AssignedWorkout(Uuid.parse(programs.addWorkout("B").id))
        c = SchedulePickerValue.AssignedWorkout(Uuid.parse(programs.addWorkout("C").id))
    }

    @Test
    fun pullingAnUpcomingWorkoutForwardRotatesOnlyUpToItsRecurrence() {
        setUp(a, b, c, a, b, c)
        programs.setScheduleDayShiftingFollowing(start, c)
        // C moves to day 0, A and B slide back one; everything from the old C slot's successor on is untouched.
        assertEquals(listOf(c, a, b, a, b, c, rest), schedule(7))
    }

    @Test
    fun valueNotComingUpSoonInsertsAndShiftsEverything() {
        setUp(a, b, a, b)
        programs.setScheduleDayShiftingFollowing(start, c)
        assertEquals(listOf(c, a, b, a, b, rest), schedule(6))
    }

    @Test
    fun pickingTheValueADayAlreadyHasIsANoOp() {
        setUp(a, b, c, a)
        programs.setScheduleDayShiftingFollowing(start, a)
        assertEquals(listOf(a, b, c, a, rest), schedule(5))
    }

    @Test
    fun addARestDayAlwaysInsertsEvenWhenRestIsAlreadyComingUp() {
        setUp(a, rest, b)
        programs.insertRestDayShiftingFollowing(start)
        assertEquals(listOf(rest, a, rest, b, rest), schedule(5))
    }

    @Test
    fun addARestDayOnARestDayStillPushesTheSchedule() {
        setUp(rest, a, b)
        programs.insertRestDayShiftingFollowing(start)
        assertEquals(listOf(rest, rest, a, b, rest), schedule(5))
    }
}

class CardioTests {
    private val db = freshDatabase()
    private val programs = ProgramRepository(db)
    private val outlines = ProgramOutlineRepository(db)
    private val sessions = WorkoutSessionRepository(db)

    @Test
    fun switchingToCardioResetsSetCountToOne() {
        programs.createFirstProgram("Test")
        val exercise = outlines.activeProgramOutline()!!.workouts.single().exercises.single()
        assertEquals(4, exercise.setCount)

        programs.setExerciseKind(exercise.id, ExerciseKind.Cardio)
        val cardio = outlines.activeProgramOutline()!!.workouts.single().exercises.single()
        assertEquals(ExerciseKind.Cardio, cardio.kind)
        assertEquals(1, cardio.setCount)

        // Switching back leaves the count alone.
        programs.setExerciseKind(exercise.id, ExerciseKind.Strength)
        assertEquals(1, outlines.activeProgramOutline()!!.workouts.single().exercises.single().setCount)
    }

    @Test
    fun cardioSetsAreLoggedShownInHistoryAndOfferedAsReference() {
        programs.createFirstProgram("Test")
        val workout = outlines.activeProgramOutline()!!.workouts.single()
        val exerciseId = workout.exercises.single().id
        programs.setExerciseKind(exerciseId, ExerciseKind.Cardio)

        val day = CalendarDate(2026, 1, 1)
        val sessionId = Uuid.parse(sessions.getOrCreateActiveSession(workout.id, day).id)
        sessions.updateCardioLoggedSet(sessionId, exerciseId, 0, minutes = 22.5, maxHeartRate = 161)
        sessions.completeSession(sessionId, workout.name)

        val history = HistoryRepository(db)
        val line = history.sessionDetail(sessionId)!!.exerciseGroups.single().sets.single()
        assertEquals(ExerciseKind.Cardio, line.kind)
        assertEquals(22.5, line.cardioMinutes)
        assertEquals(161, line.maxHeartRate)
        assertEquals(0.0, line.volume)
        assertEquals(0.0, history.completedRows().single().totalVolume)

        val reference = sessions.mostRecentLoggedValuesByExercise()[exerciseId]!![0]!!
        assertEquals(22.5, reference.cardioMinutes)
        assertEquals(161L, reference.maxHeartRate)
    }

    @Test
    fun workoutsAddedInAppKeepAppendOrderNotNamingHeuristicOrder() {
        programs.createFirstProgram("Test")
        programs.addWorkout("Cardio 1")
        programs.addWorkout("Push 1")
        assertEquals(listOf("Workout 1", "Cardio 1", "Push 1"), outlines.activeProgramOutline()!!.workouts.map { it.name })
    }
}
