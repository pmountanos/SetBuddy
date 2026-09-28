package net.mountanos.setbuddy.shared.db

import android.content.Context
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver

actual class DatabaseDriverFactory(private val context: Context) {
    actual fun createDriver(): SqlDriver {
        val driver = AndroidSqliteDriver(SetBuddyDatabase.Schema, context, "setbuddy.db")
        driver.execute(null, "PRAGMA foreign_keys=ON;", 0)
        return driver
    }
}
