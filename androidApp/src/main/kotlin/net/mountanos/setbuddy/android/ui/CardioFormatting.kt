package net.mountanos.setbuddy.android.ui

/** Whole minutes without a decimal ("30"), otherwise one decimal place ("22.5"). */
fun formatCardioMinutes(minutes: Double): String =
    if (minutes == Math.floor(minutes)) minutes.toLong().toString() else "%.1f".format(minutes)
