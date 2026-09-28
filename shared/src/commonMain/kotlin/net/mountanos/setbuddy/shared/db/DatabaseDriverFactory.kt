package net.mountanos.setbuddy.shared.db

import app.cash.sqldelight.db.SqlDriver

expect class DatabaseDriverFactory {
    fun createDriver(): SqlDriver
}

fun createDatabase(factory: DatabaseDriverFactory): SetBuddyDatabase =
    SetBuddyDatabase(factory.createDriver())
