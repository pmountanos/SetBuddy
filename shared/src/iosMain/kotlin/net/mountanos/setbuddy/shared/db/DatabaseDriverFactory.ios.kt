package net.mountanos.setbuddy.shared.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver

/**
 * Stub for Phase 2 (wiring the shared framework into the Xcode build). Compiles today so the iOS target builds
 * alongside Android, but nothing on the iOS app calls into this yet.
 */
actual class DatabaseDriverFactory {
    actual fun createDriver(): SqlDriver {
        val driver = NativeSqliteDriver(SetBuddyDatabase.Schema, "setbuddy.db")
        driver.execute(null, "PRAGMA foreign_keys=ON;", 0)
        return driver
    }
}
