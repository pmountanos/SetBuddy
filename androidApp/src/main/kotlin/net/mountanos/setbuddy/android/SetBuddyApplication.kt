package net.mountanos.setbuddy.android

import android.app.Application
import net.mountanos.setbuddy.android.importxlsx.ProgramXlsxImporter
import net.mountanos.setbuddy.android.notifications.DailyNotificationScheduler
import net.mountanos.setbuddy.shared.data.HistoryRepository
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import net.mountanos.setbuddy.shared.data.WorkoutSessionRepository
import net.mountanos.setbuddy.shared.db.DatabaseDriverFactory
import net.mountanos.setbuddy.shared.db.createDatabase

class SetBuddyApplication : Application() {
    lateinit var programRepository: ProgramRepository
        private set
    lateinit var sessionRepository: WorkoutSessionRepository
        private set
    lateinit var historyRepository: HistoryRepository
        private set
    lateinit var outlineRepository: ProgramOutlineRepository
        private set
    lateinit var notificationScheduler: DailyNotificationScheduler
        private set
    lateinit var programXlsxImporter: ProgramXlsxImporter
        private set

    override fun onCreate() {
        super.onCreate()
        val database = createDatabase(DatabaseDriverFactory(this))
        programRepository = ProgramRepository(database)
        sessionRepository = WorkoutSessionRepository(database)
        historyRepository = HistoryRepository(database)
        outlineRepository = ProgramOutlineRepository(database)
        notificationScheduler = DailyNotificationScheduler(this, programRepository)
        programXlsxImporter = ProgramXlsxImporter(database)

        if (programRepository.activeProgram() == null) {
            programRepository.createFirstProgram("My program")
        }
    }
}
