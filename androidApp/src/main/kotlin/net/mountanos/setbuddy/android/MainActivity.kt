package net.mountanos.setbuddy.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import net.mountanos.setbuddy.android.history.HistoryScreen
import net.mountanos.setbuddy.android.program.ProgramScreen
import net.mountanos.setbuddy.android.settings.SettingsScreen
import net.mountanos.setbuddy.android.today.TodayScreen

private sealed class Tab(val route: String, val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    data object Today : Tab("today", "Today", Icons.Default.CalendarToday)
    data object Program : Tab("program", "Program", Icons.Default.List)
    data object History : Tab("history", "History", Icons.Default.History)
    data object Settings : Tab("settings", "Settings", Icons.Default.Settings)
}

private val tabs = listOf(Tab.Today, Tab.Program, Tab.History, Tab.Settings)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as SetBuddyApplication
        setContent {
            MaterialTheme {
                val navController = rememberNavController()
                Scaffold(
                    bottomBar = {
                        NavigationBar {
                            val backStackEntry by navController.currentBackStackEntryAsState()
                            val currentDestination = backStackEntry?.destination
                            tabs.forEach { tab ->
                                NavigationBarItem(
                                    icon = { Icon(tab.icon, contentDescription = tab.label) },
                                    label = { Text(tab.label) },
                                    selected = currentDestination?.hierarchy?.any { it.route == tab.route } == true,
                                    onClick = {
                                        navController.navigate(tab.route) {
                                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    },
                                )
                            }
                        }
                    },
                ) { innerPadding ->
                    NavHost(
                        navController = navController,
                        startDestination = Tab.Today.route,
                        modifier = Modifier.padding(innerPadding),
                    ) {
                        composable(Tab.Today.route) {
                            TodayScreen(
                                programRepository = app.programRepository,
                                outlineRepository = app.outlineRepository,
                                sessionRepository = app.sessionRepository,
                                notificationScheduler = app.notificationScheduler,
                                onOpenWorkout = { workoutId, day ->
                                    navController.navigate("logging/$workoutId/${day.year}/${day.month}/${day.day}")
                                },
                            )
                        }
                        composable(
                            "logging/{workoutId}/{year}/{month}/{day}",
                        ) { backStackEntry ->
                            net.mountanos.setbuddy.android.logging.WorkoutLoggingScreen(
                                sessionRepository = app.sessionRepository,
                                programRepository = app.programRepository,
                                notificationScheduler = app.notificationScheduler,
                                workoutId = backStackEntry.arguments?.getString("workoutId")!!,
                                year = backStackEntry.arguments?.getString("year")!!.toInt(),
                                month = backStackEntry.arguments?.getString("month")!!.toInt(),
                                day = backStackEntry.arguments?.getString("day")!!.toInt(),
                                onDone = { navController.popBackStack() },
                            )
                        }
                        composable(Tab.Program.route) {
                            ProgramScreen(
                                programRepository = app.programRepository,
                                outlineRepository = app.outlineRepository,
                                notificationScheduler = app.notificationScheduler,
                            )
                        }
                        composable(Tab.History.route) {
                            HistoryScreen(historyRepository = app.historyRepository, sessionRepository = app.sessionRepository)
                        }
                        composable(Tab.Settings.route) {
                            SettingsScreen(
                                programRepository = app.programRepository,
                                outlineRepository = app.outlineRepository,
                                historyRepository = app.historyRepository,
                                notificationScheduler = app.notificationScheduler,
                                programXlsxImporter = app.programXlsxImporter,
                            )
                        }
                    }
                }
            }
        }
    }
}
