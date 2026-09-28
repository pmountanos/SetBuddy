package net.mountanos.setbuddy.android.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import net.mountanos.setbuddy.android.SetBuddyApplication

/** Exact alarms are cleared on reboot; re-derive them from the schedule once the device is back up. */
class BootRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val app = context.applicationContext as SetBuddyApplication
        app.notificationScheduler.requestReschedule()
    }
}
